# Changelog

### v1.5
* Validate every input in `iodined.sh` before it reaches iodined's argument
  vector: `IODINE_HOST` must be a valid multi-label DNS name, `IODINE_PASSWORD`
  must not be flag-shaped or contain control characters, `IODINE_TUNNEL_IP`
  must be a strict dotted-quad IPv4. Closes an argument-injection path where
  e.g. `IODINE_HOST=-u` would have been parsed by iodined as an option
* Support `IODINE_PASSWORD_FILE` (Docker/Compose/Kubernetes `_FILE` secret
  convention); it takes precedence over `IODINE_PASSWORD` and is never logged
* Exit `78` (`EX_CONFIG`) on configuration errors so orchestration can
  distinguish misconfiguration from a crash
* Emit timestamped, levelled diagnostics (`<UTC> <LEVEL> <message>`) including
  the effective configuration, with the password source but never the password
* Warn (without refusing) on tunnel passwords shorter than 8 characters
* Add `healthcheck.sh` and a Dockerfile `HEALTHCHECK` so orchestrators can tell
  a running tunnel from a dead one
* Rotate `/var/log/iodined.log` at `IODINE_LOG_MAX_BYTES` (10 MiB default) and
  create it owner-readable only, so a long-lived container cannot fill the host
  disk or leak tunnel metadata
* `docker-compose.yml`: replace `privileged: true` with `cap_drop: [ALL]` plus
  `NET_ADMIN`/`MDEV`, `--device /dev/net/tun`, `no-new-privileges` and bounded
  host-side log rotation. Document the equivalent plain-`docker` flags; the
  image no longer needs `--privileged`
* Add `IODINE_DRY_RUN=1` to validate configuration without starting the server
* Expand `tests/test_entrypoint.sh` from 3 to 25 tests: full validation matrix,
  secret-file handling, log format, healthcheck branches, and a container smoke
  test that now also asserts in-image config validation and `HEALTHCHECK`. The
  smoke test preflights the Docker daemon so it skips instead of hanging
* Add `Makefile` (`make check`) with the same lint and test commands CI runs
* CI: split into `lint` / `test` / `build` / `security-scan`, add Trivy image
  scanning with SARIF upload to the Security tab, least-privilege workflow
  permissions, concurrency cancellation and per-job timeouts
* Add Dependabot for the base image digest and GitHub Actions versions
* Add `SECURITY.md` (disclosure policy, supported versions, threat model) and
  expand the README with a threat model, capabilities table and a documented
  list of known weaknesses

### v1.4
* Harden `iodined.sh`: fail fast with a clear error when `IODINE_HOST` or `IODINE_PASSWORD` is missing (`set -eu`, quoted arguments)
* Add entrypoint tests (`tests/test_entrypoint.sh`) and a CI workflow (build, hadolint, shellcheck, tests)
* Add `docker-compose.yml` and `.env.example` for one-command startup
* Pin the base image to a digest and modernize the Dockerfile (`LABEL`, `COPY`, `--no-install-recommends`)
* Expand README with architecture, security, and testing notes

### v1.3
* Remove copying of `authorized_keys` into image
* Use `passenger/baseimage` v0.9.16
* Run `apt-get update` before installing `net-tools` and `iodine`
* Add ENV variable to configure tunnel IP

### v1.2
* Initial import of [FiloSottile/Dockerfiles/iodine](https://github.com/FiloSottile/Dockerfiles/tree/master/iodine)