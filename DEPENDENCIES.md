# Dependencies & Pins

This repository is a pure Shell/Docker project. The following pins ensure reproducible installs and CI runs.

## Base Image

The Dockerfile uses a pinned digest of the phusion/baseimage to guarantee reproducible builds:

```
FROM phusion/baseimage@sha256:f55d261778d83def4a60d38939511cbed0268fcb91383c9e3edf2877ced289d9
```

*Digest:* `sha256:f55d261778d83def4a60d38939511cbed0268fcb91383c9e3edf2877ced289d9`

This is a frozen 2015 (Ubuntu 14.04) snapshot. It carries a large backlog of unpatched CVEs. See the ["Known weaknesses"](README.md#known-weaknesses) section of the README for context. The digest is kept current by [Dependabot](.github/dependabot.yml).

## Apt Packages

The image installs `iodine` and `net-tools` via apt:

```
apt-get update && apt-get install -y --no-install-recommends net-tools iodine && apt-get clean
```

The exact installed versions are recorded during CI (`make build` step: "Record installed package inventory") and are not pinned in the Dockerfile itself, since guessed versions would break the build on the frozen base image. Once the base image is modernised, these should be pinned to exact versions.

## GitHub Action SHAs

The following GitHub Actions are pinned in `.github/workflows/ci.yml` for reproducibility:

| Action | SHA | Job |
|---|---|---|
| `actions/checkout` | `v4` | Lint, test, build, security-scan |
| `hadolint/hadolint-action` | `v3.1.0` | Dockerfile linting |
| `aquasecurity/trivy-action` | `v0.28.0` | Security scanning |
| `github/codeql-action` | `v3` | Code scanning SARIF upload |

## Reproducible Installs

To build and test from a fresh clone:

1. `cp .env.example .env` and set `IODINE_HOST` and `IODINE_PASSWORD` (or `IODINE_PASSWORD_FILE`).
2. `make check` runs the full pre-commit gate: `make lint` + `make test`.
3. `make build` builds the image locally.
4. All CI actions are version-pinned; no `latest` or unresolved references are used.