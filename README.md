# iodine-docker

Docker image for [Iodine](http://code.kryo.se/iodine/), a tool for tunneling
IPv4 data through a DNS server. Originally based on the Dockerfile from
[FiloSottile](https://github.com/FiloSottile/Dockerfiles/tree/master/iodine).

## Quick start

The fastest way to get a server running is with Docker Compose:

    cp .env.example .env   # then edit IODINE_HOST and IODINE_PASSWORD
    docker compose up -d

Or with plain Docker:

    docker pull wingrunr21/iodine-docker
    docker run -d \
      --device /dev/net/tun --cap-add NET_ADMIN --cap-drop ALL \
      --security-opt no-new-privileges \
      -p 53:53/udp \
      -e IODINE_HOST=t.example.com \
      -e IODINE_PASSWORD=1234password \
      wingrunr21/iodine-docker

`--privileged` is **not** required. Iodine only needs the TUN device node and
`CAP_NET_ADMIN` to create its tunnel interface. See
[Security Notes](#security-notes) for the full threat model and for the cases
that genuinely do need `--privileged`.

## Environment Variables

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `IODINE_HOST` | yes | – | Fully qualified domain to serve the tunnel on (e.g. `t.example.com`). Lowercased on startup. |
| `IODINE_PASSWORD` | yes* | – | Shared secret for the tunnel. At least 8 characters recommended. |
| `IODINE_PASSWORD_FILE` | yes* | – | Path to a file containing the password. Takes precedence over `IODINE_PASSWORD`. |
| `IODINE_TUNNEL_IP` | no | `10.0.0.1` | IPv4 address handed to connecting clients. IPv6 is not supported. |
| `IODINE_LOG` | no | `/var/log/iodined.log` | Path for iodined's own output. |
| `IODINE_LOG_MAX_BYTES` | no | `10485760` | Size at which the log is rotated, keeping one previous generation. |
| `IODINE_DRY_RUN` | no | `0` | Set to `1` to validate configuration and exit without starting the server. |

\* One of `IODINE_PASSWORD` or `IODINE_PASSWORD_FILE`.

The entrypoint **validates every value before it reaches iodined** and exits
`78` (`EX_CONFIG`) with a timestamped, levelled error message on
`stderr`/`docker logs` if anything is wrong:

* `IODINE_HOST` must be a valid DNS name of at most 253 characters with at
  least two dot-separated labels of at most 63 characters each, drawn from
  `a-z`, `0-9` and `-`. Uppercase is accepted and canonicalised to lowercase.
  This is also what stops a flag-shaped value such as `IODINE_HOST=-u` from
  being parsed by iodined as an option.
* `IODINE_PASSWORD` must not begin with `-` and must not contain control
  characters. Values shorter than 8 characters log a `WARN` but still start, so
  an existing deployment is never broken silently.
* `IODINE_TUNNEL_IP` must be a dotted-quad IPv4 address with four octets in
  `0`-`255` and no leading zeros.

### Supplying the password as a secret

Prefer a mounted secret file. `IODINE_PASSWORD_FILE` follows the `_FILE`
convention used by Docker, Compose and Kubernetes, which keeps the password out
of `docker inspect` output and shell history:

    printf 'a-long-tunnel-password' > ./iodine-password
    docker run -d --device /dev/net/tun --cap-add NET_ADMIN --cap-drop ALL \
      -v ./iodine-password:/run/secrets/iodine:ro \
      -e IODINE_HOST=t.example.com \
      -e IODINE_PASSWORD_FILE=/run/secrets/iodine \
      -p 53:53/udp wingrunr21/iodine-docker

With Compose:

```yaml
services:
  iodine:
    image: wingrunr21/iodine-docker
    cap_drop: [ALL]
    cap_add: [NET_ADMIN, MDEV]
    devices: ["/dev/net/tun:/dev/net/tun"]
    security_opt: ["no-new-privileges:true"]
    ports: ["53:53/udp"]
    secrets: [iodine_password]
    environment:
      IODINE_HOST: t.example.com
      IODINE_PASSWORD_FILE: /run/secrets/iodine_password

secrets:
  iodine_password:
    file: ./iodine-password
```

The password is never written to the container log – not even its length – and
the log records only its source (`password_source=file` or `=env`).

## Architecture

The image is built from `phusion/baseimage` (pinned by digest) with the
`iodine` server installed via apt. `iodined.sh` is installed as a
[runit](http://smarden.org/runit/) service under `/etc/service/iodined/run`
and is executed by the base image's init system (`/sbin/my_init`) when the
container starts:

1. `iodined.sh` validates and canonicalises `IODINE_HOST`, the password source
   and `IODINE_TUNNEL_IP`.
2. It rotates `/var/log/iodined.log` if it has grown past
   `IODINE_LOG_MAX_BYTES`, so a long-lived container cannot fill the host disk.
3. It creates the `/dev/net/tun` device node if the host node was not mounted in.
4. It `exec`s `iodined` in the foreground, so runit supervises the real process
   and restarts it if it dies.

## Health and observability

The image ships a `HEALTHCHECK` (`healthcheck.sh`) that reports unhealthy when
runit is no longer supervising `iodined`, or when iodined has not yet produced
any output. It deliberately does **not** check the age of the log file: iodined
logs one line per relayed DNS query, so a healthy but idle server writes nothing
and a recency check would report a false "unhealthy".

    docker inspect --format '{{ .State.Health.Status }}' <container>

Configuration errors go to `stderr` (`docker logs`); iodined's own output is
appended to `/var/log/iodined.log`:

    docker exec <container> tail -f /var/log/iodined.log

Both streams use the same `<UTC timestamp> <LEVEL> <message>` format, for
example:

    2026-10-02T09:14:07Z INFO configuration accepted: host=t.example.com tunnel=10.0.0.1 password_source=env

`docker-compose.yml` additionally caps the host-side container log
(`max-size`/`max-file`) so the log cannot grow without bound on the host either.

## Security Notes

### Threat model in one paragraph

This container is a **DNS-facing server on the internet** that holds a shared
secret and creates a network tunnel. Its real exposure is (a) the secret, which
an attacker who captures or observes DNS traffic will try to recover or brute
force, and (b) the host, because a container that creates TUN interfaces is a
container that has been granted network-administration rights. Everything below
follows from those two facts.

### Capabilities, not `--privileged`

`--privileged` grants every capability, every device and disables the seccomp
profile and AppArmor confinement. Iodine needs much less:

| Need | Grant |
| --- | --- |
| Create/configure the tunnel interface | `NET_ADMIN` |
| Create `/dev/net/tun` when the host node is not mounted in | `MDEV` |
| Read the host TUN device | `--device /dev/net/tun` |

`docker-compose.yml` already applies exactly this: `cap_drop: [ALL]` plus
those two capabilities, `--device`, and `no-new-privileges`. Use `--privileged`
only if you have a concrete reason, and never expose this container to an
untrusted network.

### Input validation

All configuration is validated before it reaches iodined's argument vector
(see [Environment Variables](#environment-variables)). iodined is a
C program that parses short options, so an unvalidated `IODINE_HOST` or
`IODINE_TUNNEL_IP` would otherwise be an argument-injection primitive.

### Secrets

* `IODINE_PASSWORD` in the environment is visible in `docker inspect`. Use
  `IODINE_PASSWORD_FILE` where you can. Anyone who can inspect the container
  can already read everything in it, so treat Docker access as root access.
* iodined's only password option is `-P <value>`, so the password is visible in
  the container's process table (`/proc/<pid>/cmdline`). This is inherent to
  upstream iodined, not to this image, and is covered by the same control as
  the point above.
* `.env` is git-ignored; `.env.example` is committed. Never commit a real
  password.

### Known weaknesses (please read before deploying)

* **The base image is a frozen, end-of-life distribution.**
  `phusion/baseimage:0.9.16` is a 2015 snapshot of Ubuntu 14.04, which has
  been out of standard support since 2019. It therefore carries a large backlog
  of CVEs that will never be patched in place – no amount of apt pinning fixes
  that. CI publishes the full Trivy report to the Security tab on every run;
  treat that backlog as the dominant risk in this image and prefer running it on
  a dedicated host, or move to a supported base image before production use.
  Dependabot (`.github/dependabot.yml`) tracks the base image digest and the CI
  action versions.
* **Container runs as root.** runit, `my_init` and the `mknod` of
  `/dev/net/tun` all require it. The capability boundary, not a non-root user,
  is what limits the blast radius.
* **Port 53 is a privileged, high-value port.** Allow only the traffic you
  intend in the host firewall.
* **Confidentiality of tunneled traffic.** iodine wraps traffic in DNS but does
  not encrypt it. Do not treat this as a substitute for a VPN.

## Testing

The test suite covers every validation rule, the structured log format, and
every branch of the healthcheck, and needs neither Docker nor root:

    bash tests/test_entrypoint.sh          # or: make test

A container smoke test (build + boot + `HEALTHCHECK`) is included and is
skipped automatically when no Docker daemon is reachable or when privileged
mode is unavailable. Control it explicitly with:

    RUN_DOCKER_TESTS=0 bash tests/test_entrypoint.sh   # never touch Docker
    RUN_DOCKER_TESTS=1 bash tests/test_entrypoint.sh   # require Docker

Linting (the same commands CI runs):

    make lint          # shellcheck iodined.sh healthcheck.sh tests/... + hadolint
    make check         # lint + test

CI (`.github/workflows/ci.yml`) runs four jobs on every push and pull request:
`lint` (shellcheck + hadolint), `test`, `build` (image build + container smoke
test) and `security-scan` (Trivy, results uploaded to the Security tab).

The Trivy job **reports but does not block** by default, because the frozen base
image means a blocking gate would be permanently red. Run it with
`block_on_vulns=1` from the *Actions* tab to enforce the gate, or change the
default once the base image is modernised.

## Troubleshooting

* **`/dev/net/tun errors`** - start the container with
  `--device /dev/net/tun --cap-add NET_ADMIN` (see
  [Security Notes](#security-notes)). `docker-compose.yml` already does.
* **`cannot create /dev/net/tun`** - the container has `NET_ADMIN` but not
  `MDEV` and the host TUN node was not mounted in. Add `--cap-add MDEV`.
* **`docker compose up` fails immediately with a capability error** - the
  frozen `phusion/baseimage` init scripts occasionally want a capability that
  iodine itself never uses. Temporarily drop the `cap_drop: [ALL]` line (keep
  `cap_add`) to confirm the diagnosis, then re-add capabilities one at a time
  until it starts. This is a property of the 2015 base image, not of iodine.
* **Port 53 already in use** - stop any local DNS resolver or change the
  published port, e.g. `-p 5353:53/udp`.
* **Container reports unhealthy right after start** - iodined needs a moment to
  come up; the `HEALTHCHECK` has a 60s start period. Check
  `docker logs <container>` for the `configuration accepted` line and for the
  reason iodined exited.
* **Debug the configuration without starting a server** - run the image with
  `IODINE_DRY_RUN=1`; it validates everything and exits `0` or `78`.
* **Logs** - `docker logs <container>` for entrypoint diagnostics and service
  failures, `docker exec <container> tail -f /var/log/iodined.log` for iodined's
  own output.

## Reporting vulnerabilities

Please see [SECURITY.md](SECURITY.md).