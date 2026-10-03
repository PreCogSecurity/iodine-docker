# Convenience targets for working on iodine-docker.
#
# Everything here is also what CI runs, so `make check` locally is equivalent
# to a green pipeline (minus the container smoke test, which needs Docker).
#
#   make help      list targets
#   make test      run the shell test suite (no Docker required)
#   make lint      shellcheck + hadolint
#   make check     lint + test, the pre-commit gate
#   make build     build the image locally
#   make smoke     run the container smoke test against a local image

SHELL := /bin/bash

SHELLCHECK ?= shellcheck
SHELLCHECK_TARGETS := iodined.sh healthcheck.sh tests/test_entrypoint.sh
HADOLINT ?= hadolint
IMAGE ?= iodine-docker:local
TEST_IMAGE ?= iodine-docker:local

.PHONY: help check test lint lint-shell lint-docker build smoke clean

help:
	@echo "Targets:"
	@echo "  check         lint + test (run this before opening a PR)"
	@echo "  test          run tests/test_entrypoint.sh (no Docker needed)"
	@echo "  lint          shellcheck $(SHELLCHECK_TARGETS) + hadolint Dockerfile"
	@echo "  build         docker build -t $(IMAGE) ."
	@echo "  smoke         build then run the container smoke test (needs Docker)"

check: lint test

test:
	bash tests/test_entrypoint.sh

lint: lint-shell lint-docker

lint-shell:
	$(SHELLCHECK) $(SHELLCHECK_TARGETS)

lint-docker:
	$(HADOLINT) Dockerfile

build:
	docker build -t $(IMAGE) .

smoke: build
	RUN_DOCKER_TESTS=1 IODINE_TEST_IMAGE=$(TEST_IMAGE) bash tests/test_entrypoint.sh

clean:
	rm -f image.tar.gz