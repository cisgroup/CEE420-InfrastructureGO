# InfrastructureGO. Each target is one step and says what it writes. Run make with no target to list them.

.DEFAULT_GOAL := help
.PHONY: help sync inlets facts convert match check test swift web map smoke verify

help:    ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  %-9s %s\n", $$1, $$2}'

sync:    ## install the locked Python environment
	uv sync --locked

inlets:  ## derive the inlet ids, each inlet's zone and the files the app, the backend and the web map share
	uv run python -m igo.inlets

facts:   ## write the game's fact cards from the counts of the inlets step
	uv run python -m igo.facts

convert: ## turn the phone's files in data/private/originals into upright sRGB JPEGs without metadata and list the captures
	uv run python -m igo.convert
	uv run python -m igo.convert --check

match:   ## say which drain each photograph shows, and draw a sheet for every stop that needs a decision
	uv run python -m igo.match --sheets

check:   ## derive everything again and compare with the files on disk, then check the game's data and the shared cases
	uv run python -m igo.inlets --check
	uv run python -m igo.facts --check
	uv run python -m igo.game

test:    ## run the pipeline's tests
	uv run pytest

swift:   ## build the game rules in Swift and run their tests on the Mac, no simulator needed
	swift test --package-path app

web:     ## run the tests of the town's map, which need node and no package
	node --test web/tests

map:     ## serve the town's map at http://localhost:8000, stop with control C
	python3 -m http.server --directory web 8000

smoke:   ## run a trained network through the whole Core ML export and through Vision, on the Mac only
	uv run --project pipeline/export python pipeline/export/smoke.py

verify:  ## run every local check and keep the output in build/
	scripts/verify.sh
