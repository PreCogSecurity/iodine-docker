#!/bin/sh
#
# Container healthcheck for iodine-docker.
#
# Liveness is derived from runit, which is the process supervisor that actually
# owns the iodined process: if runit reports the service down, the tunnel is
# down. Readiness additionally requires that iodined has produced output at
# least once, which proves it parsed its configuration and started serving.
#
# Deliberately *not* used: the age of the log file. iodined logs one line per
# relayed DNS query, so a healthy but idle server writes nothing and a recency
# check would report a false "unhealthy".
#
# Must be fast, dependency-free, and silent on the healthy path, because Docker
# runs it every --interval seconds.
#
# Usage: sh healthcheck.sh
set -eu

IODINE_LOG=${IODINE_LOG:-/var/log/iodined.log}
# runit service root. Overridable so the decision tree can be exercised in the
# test suite without a container; inside the image this is always /service.
IODINE_SERVICE_DIR=${IODINE_SERVICE_DIR:-/service}

# runit exposes supervised services as symlinks under /service. If the iodined
# service is not registered there, iodine is not running.
if [ ! -e "$IODINE_SERVICE_DIR/iodined" ]; then
    echo "UNHEALTHY: ${IODINE_SERVICE_DIR}/iodined is not supervised by runit" >&2
    exit 1
fi

# s6-svstat ships with phusion/baseimage; fall back to a process check so the
# script is also usable outside the image (e.g. in the test suite).
if command -v s6-svstat >/dev/null 2>&1; then
    if ! s6-svstat "$IODINE_SERVICE_DIR/iodined" 2>/dev/null | grep -qE '^up'; then
        echo "UNHEALTHY: iodined is not up" >&2
        exit 1
    fi
elif ! pgrep -x iodined >/dev/null 2>&1; then
    echo "UNHEALTHY: no iodined process found" >&2
    exit 1
fi

# iodined creates the log before exec'ing, so a non-empty file means the
# service started, parsed its configuration and is serving DNS.
if [ ! -s "$IODINE_LOG" ]; then
    echo "UNHEALTHY: ${IODINE_LOG} is missing or empty; iodined has not started serving" >&2
    exit 1
fi

exit 0