FROM alpine:3.12
LABEL maintainer="Harald Baier <hbaier@users.noreply.github.com>"

ENV EASYRSA=/usr/share/easy-rsa \
    EASYRSA_ALGO=rsa \
    EASYRSA_CA_EXPIRE=3650 \
    EASYRSA_CERT_EXPIRE=1080 \
    EASYRSA_CERT_RENEW=30 \
    EASYRSA_CRL_DAYS=180 \
    EASYRSA_CURVE=secp521r1 \
    EASYRSA_DN=cn_only \
    EASYRSA_KEY_SIZE=4096 \
    EASYRSA_REQ_CITY="San Francisco" \
    EASYRSA_REQ_COUNTRY=US \
    EASYRSA_REQ_EMAIL=me@example.net \
    EASYRSA_REQ_ORG="Copyleft Certificate Co" \
    EASYRSA_REQ_OU="My Organizational Unit" \
    EASYRSA_REQ_PROVINCE=California \
    OPENVPN_AUTH=SHA512 \
    OPENVPN_CIPHER=AES-256-GCM \
    OPENVPN_COMPRESS="" \
    OPENVPN_DEV=tun \
    OPENVPN_HOME=/etc/openvpn \
    OPENVPN_KEEPALIVE_INTERVAL=10 \
    OPENVPN_KEEPALIVE_TIMEOUT=120 \
    OPENVPN_MAX_CLIENTS=1024 \
    OPENVPN_MUTE=0 \
    OPENVPN_NCP_CIPHERS=AES-256-GCM:AES-256-CBC \
    OPENVPN_OPTIONS_CUSTOM="" \
    OPENVPN_PROTO=udp \
    OPENVPN_PUSH_ROUTE="" \
    OPENVPN_REMOTE_HOST=vpn.example.net \
    OPENVPN_REMOTE_PORT=1194 \
    OPENVPN_SERVER=10.8.0.0/24 \
    OPENVPN_TLS_VERSION_MIN=1.2 \
    OPENVPN_TOPOLOGY=subnet \
    OPENVPN_VERB=3

ENV EASYRSA_PKI=${OPENVPN_HOME}/pki

RUN apk --no-cache add \
    bash \
    coreutils \
    easy-rsa \
    inotify-tools \
    openvpn \
    sipcalc \
    sudo \
    supervisor \
 && mkdir -p ${OPENVPN_HOME} \
 && rm -rf ${OPENVPN_HOME}/* \
 && chmod 755 ${OPENVPN_HOME} \
 && chown root:root ${OPENVPN_HOME} \
 && mkdir -p /var/log/openvpn \
 && ln -s /usr/share/easy-rsa/easyrsa /usr/local/bin

COPY ./crl-renew.sh /usr/local/bin
COPY ./crl-watchdog.sh /usr/local/bin
COPY ./docker-entrypoint.sh /usr/local/bin
COPY ./ovpn /usr/local/bin
COPY ./supervisord.conf /etc/supervisord.conf
RUN chmod 755 /usr/local/bin/crl-renew.sh \
 && chmod 755 /usr/local/bin/crl-watchdog.sh \
 && chmod 755 /usr/local/bin/docker-entrypoint.sh \
 && chmod 755 /usr/local/bin/ovpn

EXPOSE 1194/udp
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
