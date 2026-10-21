# Pull Request Template

## Description

Please describe the change you are making and why.

## Checklist

- [ ] I have run `make check` locally and all tests pass.
- [ ] I have added or updated tests in `tests/test_entrypoint.sh` to cover my change.
- [ ] My change follows the conventions in `CONTRIBUTING.md`.
- [ ] I have updated `DEPENDENCIES.md` if relevant (apt package versions, base image digest, Action SHAs).
- [ ] I have verified that the Trivy security scan results are reviewed (CI job `security-scan`).

## Type of Change

- [ ] Bug fix (non-breaking change which fixes an issue)
- [ ] New feature (non-breaking change which adds functionality)
- [ ] Documentation update
- [ ] Refactoring
- [ ] Other (please describe):

## Screenshot / Output (if applicable)

<!-- Include relevant output, such as `make check` results or Trivy scan excerpts. -->