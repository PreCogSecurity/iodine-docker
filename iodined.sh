#!/bin/sh
set -eu

# iodine-docker service entrypoint.
#
# Installed as the runit service /etc/service/iodined/run, so runit supervises
# the iodined process and restarts it if it dies.
#
# Responsibilities, in order:
#   1. Validate every operator-supplied value *before* it reaches iodined's
#      argument vector.
#   2. Create the /dev/net/tun device node iodine needs.
#   3. exec iodined in the foreground.
#
# Exit codes: 78 (EX_CONFIG) for bad configuration, 1 for a setup failure.

# EX_CONFIG, so orchestration can distinguish "operator misconfigured the
# container" from "the service crashed".
EX_CONFIG=78

# Default only applies when the variable is unset: an explicitly empty value is
# an operator mistake and is rejected below rather than silently defaulted.
TUNNEL_IP=${IODINE_TUNNEL_IP-"10.0.0.1"}

IODINE_LOG=${IODINE_LOG:-/var/log/iodined.log}
IODINE_LOG_MAX_BYTES=${IODINE_LOG_MAX_BYTES:-10485760}

# Every diagnostic line is timestamped and levelled so the output can be
# grepped and shipped to a log collector without post-processing. Diagnostics
# go to stderr (i.e. `docker logs`); iodined's own output is appended to
# IODINE_LOG, which is the file documented in the README.
log() {
    printf '%s %s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" >&2
}

# Accept only a plausible DNS label: 1-63 chars, lowercase alphanumerics and
# hyphens, not starting or ending with a hyphen. Anything outside this set is
# rejected, which is also what keeps flag-shaped values out of iodined's argv.
check_dns_label() {
    _lbl=$1
    case $_lbl in
        ''|-*|*[!a-z0-9-]*) return 1 ;;
        *-) return 1 ;;
    esac
    [ "${#_lbl}" -le 63 ] || return 1
    return 0
}

# A full DNS name: <=253 chars, no leading/trailing/doubled dots, at least two
# labels (iodine tunnels under a subdomain, so a bare single-label host is
# always a mistake).
validate_dns_name() {
    _name=$1
    case $_name in
        ''|.*|*.|*..*) return 1 ;;
    esac
    [ "${#_name}" -le 253 ] || return 1

    _rest=$_name
    _labels=0
    while [ -n "$_rest" ]; do
        if [ "${_rest#*.}" != "$_rest" ]; then
            _label=${_rest%%.*}
            _rest=${_rest#*.}
        else
            _label=$_rest
            _rest=''
        fi
        check_dns_label "$_label" || return 1
        _labels=$((_labels + 1))
    done

    [ "$_labels" -ge 2 ] || return 1
    return 0
}

# Strict dotted-quad IPv4. Leading zeros are rejected: "010.0.0.1" is parsed
# as octal by some resolvers and is always a typo here.
validate_ipv4() {
    _addr=$1
    case $_addr in
        ''|*[!0-9.]*) return 1 ;;
    esac

    _rest=$_addr
    _octets=0
    while [ -n "$_rest" ]; do
        if [ "${_rest#*.}" != "$_rest" ]; then
            _octet=${_rest%%.*}
            _rest=${_rest#*.}
        else
            _octet=$_rest
            _rest=''
        fi
        case $_octet in
            ''|0[0-9]*) return 1 ;;
        esac
        [ "${#_octet}" -le 3 ] || return 1
        [ "$_octet" -le 255 ] || return 1
        _octets=$((_octets + 1))
    done

    [ "$_octets" -eq 4 ] || return 1
    return 0
}

# Required configuration: fail fast with a clear message instead of letting
# iodined start with an empty host or password.
if [ -z "${IODINE_HOST:-}" ]; then
    log ERROR "IODINE_HOST environment variable is required (e.g. t.example.com)"
    exit "$EX_CONFIG"
fi

# Secret handling: a mounted secret file takes precedence over the environment
# variable. Docker, Compose and Kubernetes all follow this *_FILE convention,
# which keeps the password out of `docker inspect` output, shell history and
# process listings of the orchestrator.
IODINE_PASSWORD_SOURCE=env
if [ -n "${IODINE_PASSWORD_FILE:-}" ]; then
    if [ ! -r "$IODINE_PASSWORD_FILE" ]; then
        log ERROR "IODINE_PASSWORD_FILE is set to '${IODINE_PASSWORD_FILE}' but that file is not readable"
        exit "$EX_CONFIG"
    fi
    # Command substitution strips the trailing newline written by secret files.
    IODINE_PASSWORD=$(cat "$IODINE_PASSWORD_FILE" 2>/dev/null) || IODINE_PASSWORD=''
    IODINE_PASSWORD_SOURCE=file
fi

if [ -z "${IODINE_PASSWORD:-}" ]; then
    log ERROR "IODINE_PASSWORD (or IODINE_PASSWORD_FILE) environment variable is required"
    exit "$EX_CONFIG"
fi

# DNS is case-insensitive, so canonicalise to lowercase rather than rejecting
# an otherwise valid host. Command substitution also strips any trailing
# newline an operator may have pasted in.
IODINE_HOST=$(printf '%s' "$IODINE_HOST" | tr '[:upper:]' '[:lower:]')

# Argument-injection control: IODINE_HOST is passed straight to iodined, so an
# unvalidated value such as "-u" would be parsed as a flag instead of a host.
if ! validate_dns_name "$IODINE_HOST"; then
    log ERROR "IODINE_HOST must be a fully qualified DNS name with at least two dot-separated labels (got: '${IODINE_HOST}')"
    exit "$EX_CONFIG"
fi

# iodined takes the shared secret as a bare argument, so reject anything that
# would either be re-parsed as a flag or corrupt the log/terminal stream.
case "$IODINE_PASSWORD" in
    -*)
        log ERROR "IODINE_PASSWORD must not begin with '-'"
        exit "$EX_CONFIG"
        ;;
    *[[:cntrl:]]*)
        log ERROR "IODINE_PASSWORD must not contain control characters or newlines"
        exit "$EX_CONFIG"
        ;;
esac

# Warn rather than refuse: refusing would silently break an existing
# deployment, but a short tunnel password is trivially brute-forced offline
# and deserves a loud warning.
if [ "${#IODINE_PASSWORD}" -lt 8 ]; then
    log WARN "IODINE_PASSWORD is shorter than 8 characters; the tunnel is protected only by this value and should be longer"
fi

# The tunnel endpoint iodine hands out to clients. Only IPv4 is accepted; see
# the README for IPv6.
case "$TUNNEL_IP" in
    ''|*[!0-9.]*)
        log ERROR "IODINE_TUNNEL_IP must be a dotted-quad IPv4 address (got: '${TUNNEL_IP}')"
        exit "$EX_CONFIG"
        ;;
    *)
        if ! validate_ipv4 "$TUNNEL_IP"; then
            log ERROR "IODINE_TUNNEL_IP must be a valid IPv4 address with four octets in 0-255 and no leading zeros (got: '${TUNNEL_IP}')"
            exit "$EX_CONFIG"
        fi
        ;;
esac

# Keep the rotated log bounded; a bad IODINE_LOG_MAX_BYTES must not take the
# service down under `set -eu`.
case "$IODINE_LOG_MAX_BYTES" in
    ''|*[!0-9]*) IODINE_LOG_MAX_BYTES=10485760 ;;
esac
[ "$IODINE_LOG_MAX_BYTES" -gt 0 ] || IODINE_LOG_MAX_BYTES=10485760

# Record the effective configuration exactly once, so an operator can confirm
# what the service actually accepted. The password itself is never logged - not
# even its length - only where it came from.
log INFO "configuration accepted: host=${IODINE_HOST} tunnel=${TUNNEL_IP} password_source=${IODINE_PASSWORD_SOURCE}"

# IODINE_DRY_RUN=1 validates the configuration and exits without touching the
# TUN device or starting the server. Used to test the validation surface without
# Docker, and usable as a config check before rolling the image out:
#   docker run --rm -e IODINE_HOST=... -e IODINE_PASSWORD_FILE=... \
#     -v ./secret:/run/secret:ro -e IODINE_DRY_RUN=1 iodine-docker:latest
if [ "${IODINE_DRY_RUN:-0}" = "1" ]; then
    log INFO "IODINE_DRY_RUN=1; not starting iodined"
    exit 0
fi

# Logs record tunnel metadata; keep them owner-readable only.
umask 077

# The log is appended to for the lifetime of the container, so cap it before
# handing over to iodined. One previous generation is kept.
if [ -f "$IODINE_LOG" ]; then
    _log_bytes=$(wc -c < "$IODINE_LOG" 2>/dev/null || printf '0')
    _log_bytes=$((_log_bytes + 0))
    if [ "$_log_bytes" -gt "$IODINE_LOG_MAX_BYTES" ]; then
        mv -f "$IODINE_LOG" "$IODINE_LOG.1" 2>/dev/null || rm -f "$IODINE_LOG"
    fi
fi

log INFO "starting iodined"

# Thanks to https://github.com/jpetazzo/dockvpn for the tun/tap fix
if ! mkdir -p /dev/net; then
    log ERROR "cannot create /dev/net; mount the host TUN device with '--device /dev/net/tun' or grant mknod with '--cap-add MDEV'"
    exit 1
fi
if [ ! -e /dev/net/tun ]; then
    if ! mknod /dev/net/tun c 10 200; then
        log ERROR "cannot create /dev/net/tun; run the container with '--device /dev/net/tun --cap-add NET_ADMIN' (or --privileged)"
        exit 1
    fi
fi

exec iodined -c -f "$TUNNEL_IP" "$IODINE_HOST" -P "$IODINE_PASSWORD" >>"$IODINE_LOG" 2>&1