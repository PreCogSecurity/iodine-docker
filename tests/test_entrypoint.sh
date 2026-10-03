#!/usr/bin/env bash
#
# Tests for the iodine-docker service scripts.
#
# Covered here (no Docker, no root required):
#   * every validation rule in iodined.sh, via IODINE_DRY_RUN=1
#   * the structured log format of those diagnostics
#   * every branch of the healthcheck decision tree, via IODINE_SERVICE_DIR
#   * the container smoke test (build + boot + HEALTHCHECK), skipped
#     automatically when no Docker daemon is reachable or when privileged mode
#     is unavailable (e.g. GitHub-hosted runners)
#
# Usage:
#   bash tests/test_entrypoint.sh
#   RUN_DOCKER_TESTS=0 bash tests/test_entrypoint.sh   # never touch Docker
#   RUN_DOCKER_TESTS=1 bash tests/test_entrypoint.sh   # require Docker
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/iodined.sh"
HEALTHCHECK="$ROOT/healthcheck.sh"

# auto = run the container tests only when a Docker daemon answers.
RUN_DOCKER_TESTS=${RUN_DOCKER_TESTS:-auto}

# Set IODINE_TEST_IMAGE to test an image that has already been built (CI does
# this so the image is built once and then both smoke-tested and scanned). When
# unset, the suite builds and tags its own image.
TEST_IMAGE=${IODINE_TEST_IMAGE:-}

PASS=0
FAIL=0
SKIP=0

TEST_TMP=""
cleanup() {
    if [ -n "$TEST_TMP" ] && [ -d "$TEST_TMP" ]; then
        rm -rf "$TEST_TMP"
    fi
    return 0
}
trap cleanup EXIT

# run_test <description> <command...>
# Exit code 2 from the command under test is reported as a skip.
run_test() {
    local name="$1"
    local rc=0
    shift
    "$@" || rc=$?
    case "$rc" in
        0)
            echo "PASS: $name"
            PASS=$((PASS + 1))
            ;;
        2)
            echo "SKIP: $name"
            SKIP=$((SKIP + 1))
            ;;
        *)
            echo "FAIL: $name"
            FAIL=$((FAIL + 1))
            ;;
    esac
}

# The entrypoint is validated in dry-run mode so the suite needs neither a
# container nor root. Every variable the script reads is cleared first, so a
# developer's ambient environment cannot influence a result.
clean_env=(
    -u IODINE_HOST
    -u IODINE_PASSWORD
    -u IODINE_PASSWORD_FILE
    -u IODINE_TUNNEL_IP
    -u IODINE_LOG
    -u IODINE_LOG_MAX_BYTES
)

# entry_output <env assignments...> -> combined stdout/stderr
entry_output() {
    IODINE_DRY_RUN=1 env "${clean_env[@]}" "$@" sh "$SCRIPT" 2>&1
}

# entry_rejects <expected substring> <env assignments...>
# Passes when the entrypoint exits non-zero and says something about $1.
entry_rejects() {
    local want="$1"
    shift
    local output=""
    local rc=0
    output=$(entry_output "$@") || rc=$?
    [ "$rc" -ne 0 ] || return 1
    printf '%s' "$output" | grep -qF "$want"
}

# entry_accepts <env assignments...>
entry_accepts() {
    local output=""
    local rc=0
    output=$(entry_output "$@") || rc=$?
    if [ "$rc" -ne 0 ]; then
        printf '%s\n' "$output" >&2
        return 1
    fi
}

#
# Configuration validation: required variables
#

test_missing_host() {
    entry_rejects "IODINE_HOST" IODINE_PASSWORD=secretpassword
}

test_missing_password() {
    entry_rejects "IODINE_PASSWORD" IODINE_HOST=t.example.com
}

test_unreadable_password_file() {
    entry_rejects "IODINE_PASSWORD_FILE" IODINE_HOST=t.example.com \
        IODINE_PASSWORD_FILE="$TEST_TMP/does-not-exist"
}

test_empty_password_file() {
    : > "$TEST_TMP/empty-password"
    entry_rejects "IODINE_PASSWORD" IODINE_HOST=t.example.com \
        IODINE_PASSWORD_FILE="$TEST_TMP/empty-password"
}

# A secret mounted as a file is the preferred way to pass the password; it must
# be accepted, including the trailing newline secret files usually carry.
test_password_from_file() {
    printf 'file-provided-secret\n' > "$TEST_TMP/password"
    entry_accepts IODINE_HOST=t.example.com \
        IODINE_PASSWORD_FILE="$TEST_TMP/password"
}

# The password file wins over a stale environment variable.
test_password_file_takes_precedence() {
    printf 'from-the-file-value\n' > "$TEST_TMP/password"
    local output=""
    output=$(entry_output IODINE_HOST=t.example.com \
        IODINE_PASSWORD=from-the-environment \
        IODINE_PASSWORD_FILE="$TEST_TMP/password") || return 1
    printf '%s' "$output" | grep -qF "password_source=file"
}

# The password is never echoed to the log, whatever its source.
test_never_logs_the_password() {
    printf 'super-secret-value\n' > "$TEST_TMP/password"
    local output=""
    output=$(entry_output IODINE_HOST=t.example.com \
        IODINE_PASSWORD=super-secret-value-2 \
        IODINE_PASSWORD_FILE="$TEST_TMP/password") || return 1
    if printf '%s' "$output" | grep -qF "super-secret-value"; then
        return 1
    fi
    printf '%s' "$output" | grep -qF "configuration accepted"
}

#
# IODINE_HOST validation
#
# iodined is invoked as `iodined ... "$IODINE_HOST" ...`, so an unvalidated
# value is an argument-injection vector: IODINE_HOST="-u" would be parsed by
# iodined as a flag. These tests pin that control.
#

test_rejects_flag_shaped_host() {
    local host
    for host in "-u" "--version" "-f" "-P"; do
        entry_rejects "IODINE_HOST" IODINE_HOST="$host" \
            IODINE_PASSWORD=secretpassword || return 1
    done
}

test_rejects_malformed_host() {
    local host
    for host in "example" "t..example.com" ".t.example.com" "t.example.com." \
        "t_example.com" "-t.example.com" "t.example.com " "t example.com" \
        't.example.com/id' 't.example.com?' '*' '1.2.3.4/24' \
        "$(printf 't.example.com\nrm -rf /')"; do
        entry_rejects "IODINE_HOST" IODINE_HOST="$host" \
            IODINE_PASSWORD=secretpassword || return 1
    done
}

# 64 characters: one over the DNS label limit.
test_rejects_overlong_label() {
    entry_rejects "IODINE_HOST" \
        IODINE_HOST="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.example.com" \
        IODINE_PASSWORD=secretpassword
}

test_accepts_valid_host() {
    entry_accepts IODINE_HOST=tunnel.iodine.example.com \
        IODINE_PASSWORD=secretpassword
}

# DNS is case-insensitive; the value is canonicalised rather than rejected.
test_lowercases_host() {
    local output=""
    output=$(entry_output IODINE_HOST=Tunnel.Iodine.Example.COM \
        IODINE_PASSWORD=secretpassword) || return 1
    printf '%s' "$output" | grep -qF "tunnel.iodine.example.com"
}

#
# IODINE_PASSWORD validation
#

test_rejects_flag_shaped_password() {
    entry_rejects "IODINE_PASSWORD" IODINE_HOST=t.example.com \
        IODINE_PASSWORD="-f" || return 1
    entry_rejects "IODINE_PASSWORD" IODINE_HOST=t.example.com \
        IODINE_PASSWORD="--direct" || return 1
}

# A newline in the password would corrupt the log stream and the iodined
# invocation alike.
test_rejects_control_characters_in_password() {
    entry_rejects "IODINE_PASSWORD" IODINE_HOST=t.example.com \
        IODINE_PASSWORD="$(printf 'pass\nword')" || return 1
    entry_rejects "IODINE_PASSWORD" IODINE_HOST=t.example.com \
        IODINE_PASSWORD="$(printf 'pass\tword')" || return 1
}

# A short tunnel password is a real weakness but must not break an existing
# deployment, so it warns instead of refusing.
test_warns_on_short_password() {
    local output=""
    output=$(entry_output IODINE_HOST=t.example.com IODINE_PASSWORD=short) || return 1
    printf '%s' "$output" | grep -qF "WARN"
}

#
# IODINE_TUNNEL_IP validation
#

test_rejects_malformed_tunnel_ip() {
    local ip
    for ip in "10.0.0" "10.0.0.1.2" "999.1.1.1" "10.0.0.256" "010.0.0.1" \
        "abc" "-1.2.3.4" "10.0.0." "10..0.1" "0x0a.0.0.1" "" \
        "10.0.0.1 -f"; do
        entry_rejects "IODINE_TUNNEL_IP" IODINE_HOST=t.example.com \
            IODINE_PASSWORD=secretpassword IODINE_TUNNEL_IP="$ip" || return 1
    done
}

test_accepts_valid_tunnel_ip() {
    entry_accepts IODINE_HOST=t.example.com IODINE_PASSWORD=secretpassword \
        IODINE_TUNNEL_IP=172.16.254.1
}

test_defaults_tunnel_ip() {
    local output=""
    output=$(entry_output IODINE_HOST=t.example.com \
        IODINE_PASSWORD=secretpassword) || return 1
    printf '%s' "$output" | grep -qF "10.0.0.1"
}

#
# Diagnostics
#

# Every line is "<UTC timestamp> <LEVEL> <message>" so the output can be
# grepped and shipped without post-processing.
test_structured_log_lines() {
    local output=""
    output=$(entry_output IODINE_HOST=t.example.com \
        IODINE_PASSWORD=secretpassword) || return 1
    printf '%s' "$output" |
        grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z (INFO|WARN|ERROR) '
}

test_error_lines_are_structured() {
    local output=""
    output=$(entry_output IODINE_PASSWORD=secretpassword) || true
    printf '%s' "$output" |
        grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z ERROR '
}

# 78 is EX_CONFIG: orchestration needs to be able to tell a configuration
# mistake apart from a crash.
test_exits_with_ex_config() {
    local rc=0
    entry_output IODINE_PASSWORD=secretpassword >/dev/null 2>&1 || rc=$?
    [ "$rc" -eq 78 ]
}

#
# Healthcheck
#

# healthcheck_run <s6-svstat output> <log body>
# Runs healthcheck.sh against a fake runit service root and a fake log file.
healthcheck_run() {
    local status="$1"
    local body="$2"
    local bin="$TEST_TMP/bin"
    local service="$TEST_TMP/service"
    local log_file="$TEST_TMP/iodined.log"

    mkdir -p "$bin" "$service/iodined"
    printf '#!/bin/sh\necho "%s"\n' "$status" > "$bin/s6-svstat"
    chmod +x "$bin/s6-svstat"
    printf '%s' "$body" > "$log_file"

    PATH="$bin:$PATH" IODINE_SERVICE_DIR="$service" IODINE_LOG="$log_file" \
        sh "$HEALTHCHECK"
}

test_healthcheck_unhealthy_without_service() {
    local rc=0
    IODINE_SERVICE_DIR="$TEST_TMP/no-such-service" IODINE_LOG="$TEST_TMP/iodined.log" \
        sh "$HEALTHCHECK" >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 0 ]
}

test_healthcheck_unhealthy_when_service_down() {
    local rc=0
    healthcheck_run "down (pid 0) 0s" "2026-01-02T03:04:05Z listening" \
        >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 0 ]
}

# Process alive but never served: iodine failed to come up cleanly.
test_healthcheck_unhealthy_when_log_empty() {
    local rc=0
    healthcheck_run "up (ready) 5s" "" >/dev/null 2>&1 || rc=$?
    [ "$rc" -ne 0 ]
}

test_healthcheck_healthy() {
    healthcheck_run "up (ready) 5s" "2026-01-02T03:04:05Z listening" >/dev/null 2>&1
}

#
# Container smoke test
#

# `command -v docker` only proves the CLI is installed. Confirm the engine
# actually answers before starting a build that would otherwise hang.
docker_daemon_available() {
    case "$RUN_DOCKER_TESTS" in
        0) return 1 ;;
        1) return 0 ;;
    esac
    command -v docker >/dev/null 2>&1 || return 1
    if command -v timeout >/dev/null 2>&1; then
        timeout 60 docker info >/dev/null 2>&1 || return 1
    else
        docker info >/dev/null 2>&1 || return 1
    fi
    return 0
}

# Build the image and verify the container boots, stays up, serves, and that
# the image's HEALTHCHECK reports healthy. Returns 2 when the test cannot run
# in this environment (no Docker daemon / no privileged mode).
test_docker_smoke() {
    if ! docker_daemon_available; then
        echo "  no reachable Docker daemon (or RUN_DOCKER_TESTS=0); skipping"
        return 2
    fi

    if [ -n "$TEST_IMAGE" ]; then
        echo "  using pre-built image ${TEST_IMAGE}"
    else
        echo "  building image (this may take a while)..."
        docker build -t iodine-docker:test "$ROOT" || return 1
        TEST_IMAGE=iodine-docker:test
    fi

    # /dev/net/tun requires --privileged, which is not available on all CI
    # runners; skip rather than fail when it is unsupported.
    if ! docker run --rm --privileged "$TEST_IMAGE" /bin/true >/dev/null 2>&1; then
        echo "  privileged mode unavailable in this environment; skipping"
        return 2
    fi

    # Configuration validation must also work inside the real image. Run the
    # service script directly through the image's own shell and assert on its
    # output: going through CMD would race the base image's init system and
    # could pass without the entrypoint ever running.
    local dry_run_output=""
    dry_run_output=$(docker run --rm --entrypoint /bin/sh \
        -e IODINE_HOST=t.example.com -e IODINE_PASSWORD=testpass \
        -e IODINE_DRY_RUN=1 "$TEST_IMAGE" \
        /etc/service/iodined/run 2>&1) || return 1
    printf '%s' "$dry_run_output" | grep -qF "configuration accepted" || return 1

    # A rejected configuration must fail inside the image too, with the same
    # EX_CONFIG status the host-side tests assert.
    local reject_rc=0
    docker run --rm --entrypoint /bin/sh \
        -e IODINE_PASSWORD=testpass "$TEST_IMAGE" \
        /etc/service/iodined/run >/dev/null 2>&1 || reject_rc=$?
    [ "$reject_rc" -eq 78 ] || return 1

    local cid="" state="" log="" health_rc=0
    cid=$(docker run -d --privileged \
        -e IODINE_HOST=t.example.com \
        -e IODINE_PASSWORD=testpass \
        "$TEST_IMAGE") || return 1

    # Give the service a moment to start, then let the image's own HEALTHCHECK
    # decide, rather than guessing with a fixed sleep.
    local waited=0
    while [ "$waited" -lt 90 ]; do
        state=$(docker inspect -f '{{.State.Running}}' "$cid" 2>/dev/null || echo false)
        [ "$state" = "true" ] || break
        if docker exec "$cid" /healthcheck.sh >/dev/null 2>&1; then
            health_rc=0
            break
        fi
        health_rc=1
        sleep 3
        waited=$((waited + 3))
    done

    log=$(docker exec "$cid" cat /var/log/iodined.log 2>/dev/null || true)
    docker rm -f "$cid" >/dev/null 2>&1 || true

    [ "$state" = "true" ] || return 1
    [ "$health_rc" -eq 0 ] || return 1
    [ -n "$log" ] || return 1
}

#
# Test driver
#

TEST_TMP=$(mktemp -d)
: > "$TEST_TMP/iodined.log"

run_test "iodined.sh exits non-zero when IODINE_HOST is missing" test_missing_host
run_test "iodined.sh exits non-zero when IODINE_PASSWORD is missing" test_missing_password
run_test "iodined.sh rejects an unreadable IODINE_PASSWORD_FILE" test_unreadable_password_file
run_test "iodined.sh rejects an empty password file" test_empty_password_file
run_test "iodined.sh accepts a password supplied as a mounted secret file" test_password_from_file
run_test "iodined.sh prefers IODINE_PASSWORD_FILE over IODINE_PASSWORD" test_password_file_takes_precedence
run_test "iodined.sh never writes the password to the log" test_never_logs_the_password

run_test "iodined.sh rejects flag-shaped IODINE_HOST values (argument injection)" test_rejects_flag_shaped_host
run_test "iodined.sh rejects malformed IODINE_HOST values" test_rejects_malformed_host
run_test "iodined.sh rejects an over-long DNS label" test_rejects_overlong_label
run_test "iodined.sh accepts a valid IODINE_HOST" test_accepts_valid_host
run_test "iodined.sh canonicalises IODINE_HOST to lowercase" test_lowercases_host

run_test "iodined.sh rejects flag-shaped IODINE_PASSWORD values" test_rejects_flag_shaped_password
run_test "iodined.sh rejects control characters in IODINE_PASSWORD" test_rejects_control_characters_in_password
run_test "iodined.sh warns about a short IODINE_PASSWORD" test_warns_on_short_password

run_test "iodined.sh rejects malformed IODINE_TUNNEL_IP values" test_rejects_malformed_tunnel_ip
run_test "iodined.sh accepts a valid IODINE_TUNNEL_IP" test_accepts_valid_tunnel_ip
run_test "iodined.sh defaults IODINE_TUNNEL_IP to 10.0.0.1" test_defaults_tunnel_ip

run_test "iodined.sh emits timestamped, levelled log lines" test_structured_log_lines
run_test "iodined.sh emits structured ERROR lines" test_error_lines_are_structured
run_test "iodined.sh exits 78 (EX_CONFIG) on a configuration error" test_exits_with_ex_config

run_test "healthcheck.sh reports unhealthy when iodine is not supervised" test_healthcheck_unhealthy_without_service
run_test "healthcheck.sh reports unhealthy when the service is down" test_healthcheck_unhealthy_when_service_down
run_test "healthcheck.sh reports unhealthy when iodined has not served" test_healthcheck_unhealthy_when_log_empty
run_test "healthcheck.sh reports healthy when iodined is serving" test_healthcheck_healthy

run_test "container boots, serves, and passes its HEALTHCHECK" test_docker_smoke

echo
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
[ "$FAIL" -eq 0 ]