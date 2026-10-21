# Contributing to iodine-docker

Thank you for contributing! This project wraps the Iodine DNS tunneling tool in a hardened Docker container. Below are the conventions and steps to get your change reviewed and merged.

## Quick Start

```bash
# 1. Clone and set up
git clone https://github.com/PreCogSecurity/iodine-docker.git
cd iodine-docker
cp .env.example .env   # set IODINE_HOST and IODINE_PASSWORD

# 2. Run the full pre-commit gate (equivalent to CI)
make check   # runs make lint + make test

# 3. If you added a new validation rule, add a test for it in tests/test_entrypoint.sh
```

## Development Conventions

### Linting

- `make lint` runs `shellcheck iodined.sh healthcheck.sh tests/test_entrypoint.sh` + `hadolint Dockerfile`
- `shellcheck` is enforced in CI (`.github/workflows/ci.yml`). All shell scripts must pass shellcheck locally before pushing.
- `hadolint` is enforced in CI. The `.hadolint.yaml` ignores DL3008 only because the base image is a frozen 2015 snapshot; new linter warnings should be addressed.

### Testing

- `make test` runs `bash tests/test_entrypoint.sh` — no Docker required for most tests.
- All new features **must** include a test in `tests/test_entrypoint.sh` that pins the new behavior.
- Tests use the `IODINE_DRY_RUN=1` mode so they never need a container or root.
- To add a new test:
  1. Add a test function following the `test_*` naming pattern in `tests/test_entrypoint.sh`.
  2. Use `run_test "description" test_new_test` in the test driver section (bottom of the file).
  3. Ensure the test covers a single logical concern (e.g., "rejects control characters in password").

### Adding a New Validation Rule to `iodined.sh`

1. Add the validation function (e.g., `check_something()`) near the existing validation functions.
2. Call the function at the appropriate point in the script (after variable assignment, before passing to iodined).
3. Use the pattern `log ERROR "..."; exit "$EX_CONFIG"` for hard failures, or `log WARN "..."` for warnings.
4. Add a corresponding test case in `tests/test_entrypoint.sh` that exercises the new rule via `IODINE_DRY_RUN=1`.
5. Run `make check` locally to verify both the script and tests pass.

### Commit Style

- Keep each feature or fix in its own commit (or small PR) that includes the tests proving the new behavior.
- Avoid bulk commits that mix formatting, refactors, and features; they hide the mineable work.
- Reference related issues or PR numbers in commit messages.

## CI Pipeline

The CI workflow (`.github/workflows/ci.yml`) runs on every push and pull request:

| Job | Description |
|---|---|
| `lint` | shellcheck + hadolint |
| `test` | `bash tests/test_entrypoint.sh` (no Docker needed) |
| `build` | Docker image build + container smoke test |
| `security-scan` | Trivy image scan with SARIF upload |

The `security-scan` job reports but does not block by default (`block_on_vulns=0`). This is intentional until the base image is modernised; see the ["Known weaknesses"](README.md#known-weaknesses) section. To enforce the gate, run the workflow dispatch with `block_on_vulns=1` from the **Actions** tab.

## Pull Request Process

1. Open a PR against the `master` branch.
2. Ensure `make check` passes locally.
3. The PR description should summarize the change and confirm tests are included.
4. A checklist item will confirm `bash tests/test_entrypoint.sh` was run locally (see PR template below).

A maintainer will review the change, verify the tests, and merge once the CI pipeline is green.