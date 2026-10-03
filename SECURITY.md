# Security Policy

## Reporting a vulnerability

Please report suspected vulnerabilities privately to **security@precogsecurity.io**
rather than opening a public issue or pull request. Do not run automated
scanners against infrastructure you do not own.

Include as much of the following as you can:

* the image tag or commit you tested
* the exact `docker run` flags / `docker-compose.yml` used
* the configuration (`IODINE_HOST`, secret source, `IODINE_TUNNEL_IP`) with the
  secret itself redacted
* the observed and expected behaviour, and the container logs
  (`docker logs` plus `/var/log/iodined.log`)

We aim to acknowledge a report within three business days and to send an
initial assessment, including severity and whether a fix or mitigation is
planned, within ten business days. We will keep you updated while a fix is
prepared and will credit you in the release notes unless you prefer otherwise.

Please give us a reasonable opportunity to ship a fix before disclosing
publicly.

## Supported versions

Only the latest released tag receives security fixes. Untagged
`master`/`main` builds are for development and testing; do not run them in
production.

| Version | Supported |
| --- | --- |
| `latest` / most recent tag | yes |
| Older tags | no |

## Scope

In scope:

* the container image, its entrypoint (`iodined.sh`) and its healthcheck
  (`healthcheck.sh`) in this repository
* the `Dockerfile` and `docker-compose.yml` as shipped

Out of scope (report upstream instead):

* vulnerabilities in [iodine](http://code.kryo.se/iodine/) itself – please see
  the upstream project's contact details
* vulnerabilities in the `phusion/baseimage` base image – see the image's own
  issue tracker
* misconfiguration of the Docker daemon, the host firewall or the surrounding
  network

## Threat model and hardening baseline

The image runs a DNS-facing server that holds a shared secret and creates a
network tunnel. Its exposure is the secret (recoverable from captured or
observed DNS traffic) and the host (the container needs network-administration
rights to create its TUN interface).

The baseline this repository maintains, and what a reviewer should check is
still true of any deployment:

1. **Least privilege.** Run with `--device /dev/net/tun --cap-add NET_ADMIN
   --cap-drop ALL --security-opt no-new-privileges`, not `--privileged`.
2. **Validated input.** `iodined.sh` rejects anything that is not a valid DNS
   name, secret or IPv4 address before the value reaches iodined's argument
   vector, and exits `78` (`EX_CONFIG`) on bad configuration.
3. **Secrets out of the environment where possible.** Prefer
   `IODINE_PASSWORD_FILE` with a mounted secret over `IODINE_PASSWORD`.
4. **Bounded logs.** `IODINE_LOG_MAX_BYTES` in the container, `max-size` /
   `max-file` on the host. A tunnel server that can fill the host disk is an
   availability bug.
5. **No secrets in the repository.** `.env` is git-ignored; only
   `.env.example` is committed.
6. **Dependency and image scanning.** Trivy runs in CI on every push and pull
   request and uploads results to the Security tab.

## Known accepted risk

The image is pinned to `phusion/baseimage:0.9.16`, a 2015 snapshot of Ubuntu
14.04 that is out of standard support. Its accumulated CVEs cannot be fixed by
pinning package versions, because the distribution itself no longer receives
updates. This is why the Trivy job reports by default instead of blocking, and
why the README asks operators to run the image on a dedicated host or to move to
a supported base image before production use. Moving off this base image is
the single most valuable security change available for this project.