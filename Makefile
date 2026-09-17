# Makefile — a discoverable façade over the entry points in scripts/.
# ──────────────────────────────────────────────────────────────────────────────
# This adds NO logic: every target shells out to the real script, which stays the single
# source of truth. It exists so a newcomer can type `make` and see how to lint, test,
# audit and release — instead of grepping the README for scripts/ paths. `make audit` is
# the one gate; CI and pre-commit call the same scripts/audit-nvim.sh, so `make audit` ==
# green CI.
#
# NOT the fleet `make` vocabulary. dotfiles-core's scripts/make-vocabulary.txt pins seven
# verbs every OS repo must define, and scripts/fleet-vocabulary.sh audits them. This repo
# is not one of those: Core vendors FROM it, not out TO it, so it is deliberately absent
# from scripts/os-repos.txt and from that register (NVIM-SPLIT-PROPOSAL.md §7, closing
# note). `lint` and `check` are aliased below anyway, because they cost a line and a
# reader arriving from any other repo in the org will try them.
# ──────────────────────────────────────────────────────────────────────────────
.DEFAULT_GOAL := help
.PHONY: help audit audit-offline test lint check update-nvim-plugins check-pins tag publish

help: ## Show this help
	@echo "dotfiles-nvim — make targets:"
	@grep -E '^[a-z][a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) \
		| sed -E 's/:.*## /\t/' | sort | awk -F'\t' '{printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

audit: ## Run the full gate (luacheck, reachability, theme, headless startup + checkhealth, tests) — the one gate
	@./scripts/audit-nvim.sh

audit-offline: ## The gate without the sections that need the network (skips the plugin install)
	@./scripts/audit-nvim.sh --offline

test: ## Run only the behavioral suite (scripts/test-nvim.sh, fragments in scripts/test/)
	@./scripts/test-nvim.sh

lint: audit ## Alias for audit — there is one gate, not two
check: audit ## Alias for audit — there is one gate, not two

update-nvim-plugins: ## Roll nvim/lazy-lock.json forward to upstream (needs nvim + network)
	@./scripts/update-nvim-plugins.sh

check-pins: ## Report whether the plugin pins are behind upstream, changing nothing
	@./scripts/update-nvim-plugins.sh --check

tag: ## Release phase 1 — prove green and commit nvim.version + CHANGELOG (creates NO tag)
	@./scripts/tag-release.sh

publish: ## Release phase 2 — tag origin/main and push vX.Y.Z + the vN alias (AFTER the PR merges)
	@./scripts/tag-release.sh --publish
