# InfrastructureGO. Each target is one step and says what it writes. Run make with no target to list them.

.DEFAULT_GOAL := help
.PHONY: help sync inlets check test verify

help:    ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-9s %s\n", $$1, $$2}'

sync:    ## install the locked Python environment
	uv sync --locked

inlets:  ## derive the inlet ids, each inlet's zone and the files the app, the backend and the web map share
	uv run python -m igo.inlets

check:   ## derive again and compare with the files on disk, writing nothing
	uv run python -m igo.inlets --check

test:    ## run the pipeline's tests
	uv run pytest

verify:  ## run every local check and keep the output in build/
	scripts/verify.sh
