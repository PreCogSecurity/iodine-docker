#!/bin/sh
set -eu

TUNNEL_IP=${IODINE_TUNNEL_IP:-"10.0.0.1"}

# Required configuration: fail fast with a clear message instead of letting
# iodined start with an empty host or password.
if [ -z "${IODINE_HOST:-}" ]; then
    echo "ERROR: IODINE_HOST environment variable is required (e.g. t.example.com)" >&2
    exit 1
fi

if [ -z "${IODINE_PASSWORD:-}" ]; then
    echo "ERROR: IODINE_PASSWORD environment variable is required" >&2
    exit 1
fi

# Thanks to https://github.com/jpetazzo/dockvpn for the tun/tap fix
mkdir -p /dev/net
if [ ! -e /dev/net/tun ]; then
    mknod /dev/net/tun c 10 200
fi

exec iodined -c -f "$TUNNEL_IP" "$IODINE_HOST" -P "$IODINE_PASSWORD" >>/var/log/iodined.log 2>&1
