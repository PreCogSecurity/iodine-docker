# Changelog

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
