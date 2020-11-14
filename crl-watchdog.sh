#!/bin/sh

set -e

inotifywait -mq -e moved_to --format %w%f ${EASYRSA_PKI} | while IFS= read -r FILE; do
  [ "${FILE}" = "${EASYRSA_PKI}/crl.pem" ] && chmod 644 "${FILE}"
done
