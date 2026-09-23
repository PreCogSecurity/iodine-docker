#!/usr/bin/env bash
#
# Tests for the iodine-docker entrypoint script (iodined.sh).
#
# The validation tests execute the entrypoint directly and require neither
# Docker nor root privileges, because input validation runs before any
# device setup. The container smoke test builds the image and boots it with
# the required environment variables; it is skipped automatically when
# Docker or privileged mode is unavailable (e.g. GitHub-hosted runners).
#
# Usage: bash tests/test_entrypoint.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/iodined.sh"

PASS=0
FAIL=0
SKIP=0

run_test() {
    local name="$1"
    shift
    if "$@"; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name"
        FAIL=$((FAIL + 1))
    fi
}

# The entrypoint must exit non-zero with a clear message when IODINE_HOST
# is not set, instead of silently starting iodined with an empty host.
test_missing_host() {
    local output rc
    output=$(IODINE_PASSWORD=secret sh "$SCRIPT" 2>&1) || rc=$?
    rc=${rc:-0}
    [ "$rc" -ne 0 ] || return 1
    printf '%s' "$output" | grep -q "IODINE_HOST" || return 1
}

# Same for IODINE_PASSWORD.
test_missing_password() {
    local output rc
    output=$(IODINE_HOST=t.example.com sh "$SCRIPT" 2>&1) || rc=$?
    rc=${rc:-0}
    [ "$rc" -ne 0 ] || return 1
    printf '%s' "$output" | grep -q "IODINE_PASSWORD" || return 1
}

# Build the image and verify the container boots and stays up when the
# required environment variables are provided. Returns 2 when the test
# cannot run in this environment (no Docker daemon / no privileged mode).
test_docker_smoke() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "SKIP: docker not available; skipping container smoke test"
        return 2
    fi
    echo "Building image (this may take a while)..."
    docker build -t iodine-docker:test "$ROOT"
    # /dev/net/tun requires --privileged, which is not available on all CI
    # runners; skip rather than fail when it is unsupported.
    if ! docker run --rm --privileged iodine-docker:test /bin/true >/dev/null 2>&1; then
        echo "SKIP: privileged mode unavailable in this environment; skipping container smoke test"
        return 2
    fi
    local cid state log
    cid=$(docker run -d --privileged \
        -e IODINE_HOST=t.example.com \
        -e IODINE_PASSWORD=testpass \
        iodine-docker:test)
    sleep 5
    state=$(docker inspect -f '{{.State.Running}}' "$cid")
    log=$(docker exec "$cid" cat /var/log/iodined.log 2>/dev/null || true)
    docker rm -f "$cid" >/dev/null 2>&1 || true
    [ "$state" = "true" ] || return 1
    [ -n "$log" ] || return 1
}

run_test "iodined.sh exits non-zero when IODINE_HOST is missing" test_missing_host
run_test "iodined.sh exits non-zero when IODINE_PASSWORD is missing" test_missing_password

if test_docker_smoke; then
    echo "PASS: container boots and stays up with required env vars"
    PASS=$((PASS + 1))
else
    rc=$?
    if [ "$rc" -eq 2 ]; then
        echo "SKIP: container smoke test (docker or privileged mode unavailable)"
        SKIP=$((SKIP + 1))
    else
        echo "FAIL: container boots and stays up with required env vars"
        FAIL=$((FAIL + 1))
    fi
fi

echo
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]
