#!/bin/sh

set -e

while true; do
  sleep 43200 # 12 hours
  /usr/share/easy-rsa/easyrsa gen-crl # update certificate revocation list
done
