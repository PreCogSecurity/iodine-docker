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
    docker run -d --privileged -p 53:53/udp \
      -e IODINE_HOST=t.example.com \
      -e IODINE_PASSWORD=1234password \
      wingrunr21/iodine-docker

## Environment Variables

* `IODINE_HOST` - the domain where your iodine server is running (required)
* `IODINE_PASSWORD` - the password for your iodine server (required)
* `IODINE_TUNNEL_IP` - the server tunnel ip. Optional and defaults to 10.0.0.1.

The entrypoint fails fast with a clear error if `IODINE_HOST` or
`IODINE_PASSWORD` is missing.

## Architecture

The image is built from `phusion/baseimage` (pinned by digest) with the
`iodine` server installed via apt. `iodined.sh` is installed as a
[runit](http://smarden.org/runit/) service under `/etc/service/iodined/run`
and is executed by the base image's init system (`/sbin/my_init`) when the
container starts:

1. `iodined.sh` validates `IODINE_HOST` and `IODINE_PASSWORD`.
2. It creates the `/dev/net/tun` device node needed by iodine.
3. It execs `iodined` in the foreground, logging to `/var/log/iodined.log`.

## Security Notes

* Iodine requires a TUN/TAP device, so the container must run with
  `--privileged` (or equivalent device access). This grants the container
  significantly more access to the host than a normal container; only run
  it on hosts you trust and avoid exposing it to untrusted networks.
* The container exposes UDP port 53, the standard DNS port. Make sure the
  host firewall allows only the traffic you intend.
* `IODINE_PASSWORD` is passed as a plain environment variable. Treat it as
  a secret: do not commit it to version control (see `.env.example` and
  `.gitignore`), and prefer Docker secrets or an orchestration platform's
  secret management where available.

## Testing

The entrypoint tests verify the required-environment validation and run
without Docker:

    bash tests/test_entrypoint.sh

The same script includes a container smoke test (build + boot) that is
skipped automatically when Docker or privileged mode is unavailable. CI
(`.github/workflows/ci.yml`) runs the tests, `shellcheck`, and `hadolint`
on every push and pull request.

## Troubleshooting

* **`/dev/net/tun` errors** - the container must be started with
  `--privileged` (see Security Notes).
* **Port 53 already in use** - stop any local DNS resolver or change the
  published port, e.g. `-p 5353:53/udp`.
* **Logs** - the entrypoint writes to `/var/log/iodined.log` inside the
  container: `docker exec <container> tail -f /var/log/iodined.log`.
