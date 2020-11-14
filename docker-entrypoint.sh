#!/bin/bash

set -e

cidr2classful() {
  # convert CIDR network into classful network
  local networkCidr=$1
  if sipcalc ${networkCidr} | grep -q '\-\[ERR :'; then
    echo 'ERROR: Wrong CIDR notation ...'
    exit 1
  else
    local networkAddress=`sipcalc ${networkCidr} | grep '^Network address' | awk '{print $4}'`
    local networkClassfulMask=`sipcalc ${networkCidr} | grep '^Network mask\s\s' | awk '{print $4}'`
    echo ${networkAddress} ${networkClassfulMask}
  fi
}

classful2cidr() {
  # convert classful network into CIDR network
  local networkClassful=$1
  if sipcalc ${networkClassful} | grep -q '\-\[ERR :'; then
    echo 'ERROR: Wrong classful notation ...'
    exit 1
  else
    local networkAddress=`sipcalc ${networkClassful} | grep '^Network address' | awk '{print $4}'`
    local networkCidrMask=`sipcalc ${networkClassful} | grep '^Network mask (bits)' | awk '{print $5}'`
    echo ${networkAddress}/${networkCidrMask}
  fi
}

create_pki() {
  # initialize the PKI directory
  echo "INFO: Initializing Easy-RSA PKI instance on ${EASYRSA_PKI} ..."
  /usr/share/easy-rsa/easyrsa init-pki > /dev/null 2>&1

  # building the CA
  echo 'INFO: Building the CA ...'
  /usr/share/easy-rsa/easyrsa --batch --req-cn="Easy-RSA CA" build-ca nopass > /dev/null 2>&1

  # create private key and a certificate request for the server
  echo 'INFO: Creating private key and a certificate request for the server ...'
  /usr/share/easy-rsa/easyrsa --batch --req-cn="server" gen-req server nopass > /dev/null 2>&1

  # sign the certificate request for the server
  echo 'INFO: Signing the certificate request for the server ...'
  /usr/share/easy-rsa/easyrsa --batch sign-req server server > /dev/null 2>&1

  # generate Diffie-Hellman parameters
  echo 'INFO: Generating Diffie-Hellman parameters ...'
  /usr/share/easy-rsa/easyrsa gen-dh > /dev/null 2>&1
}

get_options() {
  local -n options=$1

  # server mode options
  options+=( '--server' `cidr2classful "${OPENVPN_SERVER:-10.8.0.0/24}"` )
  options+=( '--max-clients' "${OPENVPN_MAX_CLIENTS:-1024}" )

  # tunnel options
  options+=( '--dev' "${OPENVPN_DEV:-tun}" )
  options+=( '--port' '1194' )
  if [ "${OPENVPN_PROTO:-udp}" = 'tcp' ]; then
    options+=( '--proto' 'tcp-server' )
  else
    options+=( '--proto' 'udp' )
  fi
  options+=( '--topology' "${OPENVPN_TOPOLOGY:-net30}" )
  options+=( '--keepalive' "${OPENVPN_KEEPALIVE_INTERVAL:-0}" "${OPENVPN_KEEPALIVE_TIMEOUT:-0}" )

  # control channel options
  options+=( '--ca' "${EASYRSA_PKI}/ca.crt" )
  options+=( '--cert' "${EASYRSA_PKI}/issued/server.crt" )
  options+=( '--key' "${EASYRSA_PKI}/private/server.key" )
  options+=( '--dh' "${EASYRSA_PKI}/dh.pem" )
  options+=( '--crl-verify' "${EASYRSA_PKI}/crl.pem" )
  options+=( '--tls-crypt' "${OPENVPN_HOME}/ta.key" )
  options+=( '--tls-version-min' "${OPENVPN_TLS_VERSION_MIN:-1.0}" )

  # data channel options
  options+=( '--auth' "${OPENVPN_AUTH:-SHA1}" )
  options+=( '--cipher' "${OPENVPN_CIPHER:-BF-CBC}" )
  options+=( '--ncp-ciphers' "${OPENVPN_NCP_CIPHERS:-AES-256-GCM:AES-128-GCM}" )

  # add "push route" directives
  ROUTES_CIDR=( ${OPENVPN_PUSH_ROUTE} )
  for ROUTE_CIDR in "${ROUTES_CIDR[@]}"
  do
    local ROUTE_CLASSFUL=`cidr2classful "${ROUTE_CIDR}"`
    options+=( '--push' "\"route ${ROUTE_CLASSFUL}\"" )
  done

  # add "compress" directive
  case "${OPENVPN_COMPRESS}" in
    lz4|lz4-v2)
      options+=( '--compress' "${OPENVPN_COMPRESS}" )
      options+=( '--push' '"compress"' )
      ;;
    lzo)
      options+=( '--compress' "${OPENVPN_COMPRESS}" )
      options+=( '--push' '"comp-lzo yes"' ) # deprecated option for client backward compatibility
      ;;
  esac

  # add client config directory directive
  if [ -d ${OPENVPN_HOME}/ccd ]; then
    options+=( '--client-config-dir' "${OPENVPN_HOME}/ccd" )
  fi

  # unprivileged mode options
  options+=( '--user' 'openvpn' )
  options+=( '--group' 'openvpn' )
  options+=( '--persist-key' )
  options+=( '--persist-tun' )
  options+=( '--iproute' '/usr/local/sbin/unpriv-ip' )

  # logging options
  options+=( '--status' '/var/log/openvpn/status.log' )
  options+=( '--ifconfig-pool-persist' '/var/log/openvpn/ipp.txt' )
  options+=( '--verb' "${OPENVPN_VERB:-1}" )
  options+=( '--mute' "${OPENVPN_MUTE:-0}" )
}

# initializing empty OpenVPN home directory
if [ -z "$(ls -A ${OPENVPN_HOME})" ]; then
  # create Easy-RSA PKI instance
  if [ ! -d ${EASYRSA_PKI} ]; then
    create_pki
  fi

  # create tls-crypt shared secret key
  if [ ! -f ${OPENVPN_HOME}/ta.key ]; then
    echo 'INFO: Creating tls-crypt shared secret key ...'
    openvpn --genkey --secret ${OPENVPN_HOME}/ta.key
  fi

  # create client config directory
  echo 'INFO: Creating client config directory ...'
  mkdir -p ${OPENVPN_HOME}/ccd
fi

# create or update certificate revocation list
echo 'INFO: Creating or updating certificate revocation list ...'
/usr/share/easy-rsa/easyrsa gen-crl > /dev/null 2>&1
if [ -f ${EASYRSA_PKI}/crl.pem ]; then
  # CRL needs to be readable by the unprivileged OpenVPN user
  chmod 755 ${EASYRSA_PKI}
  chmod 644 ${EASYRSA_PKI}/crl.pem
fi

# create TUN device
echo 'INFO: Creating TUN device ...'
mkdir -p /dev/net
if [ ! -c /dev/net/tun ]; then
  mknod /dev/net/tun c 10 200
fi

# check if IP forwarding is enabled
if [ `cat /proc/sys/net/ipv4/ip_forward` -eq 1 ]; then
  echo 'INFO: Masquerading all traffic from clients ...'
  if iptables -t nat -F POSTROUTING; then
    # masquerading all traffic from clients
    iptables -t nat -I POSTROUTING -s ${OPENVPN_SERVER:-10.8.0.0/24} -o eth0 -j MASQUERADE
  fi
else
  echo "ERROR: IP forwarding isn't enabled on the Docker host ..."
  exit 1
fi

# unprivileged mode prerequisites
echo 'INFO: Creating prerequisites for the unprivileged mode ...'
echo 'openvpn ALL=(ALL) NOPASSWD: /sbin/ip' | (su -c 'EDITOR="tee" visudo -f /etc/sudoers.d/openvpn') > /dev/null 2>&1
mkdir -p /usr/local/sbin
echo '#!/bin/sh' > /usr/local/sbin/unpriv-ip
echo 'sudo /sbin/ip $*' >> /usr/local/sbin/unpriv-ip
chmod 755 /usr/local/sbin/unpriv-ip

# get OpenVPN server options
OPENVPN_OPTIONS_REGULAR=() && get_options OPENVPN_OPTIONS_REGULAR
export OPENVPN_OPTIONS="${OPENVPN_OPTIONS_REGULAR[@]} ${OPENVPN_OPTIONS_CUSTOM}"

# launch OpenVPN server, crl-renew and crl-watchdog through Supervisor process control system
if [ $# -eq 0 ] || [ "${1:0:1}" = '-' ]; then
  exec /usr/bin/supervisord -c /etc/supervisord.conf "$@"
fi

exec "$@"
