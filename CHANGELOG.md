# Changelog

All notable changes to this repo are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/). `scripts/tag-release.sh` reads the top section
verbatim as the GitHub Release body, so a version with an empty section refuses to publish.

## [Unreleased]

## [v1.0.0] - 2026-09-17

### Added

- **`dotfiles-nvim` exists, and the editor finally has a gate that starts it**
  ([dotfiles-core#1122](https://github.com/dotgibson/dotfiles-core/issues/1122)).
  The Neovim tree — 6,404 lines of Lua across 98 files, 61 pinned plugins — was authored in
  `dotfiles-core` and vendored into nine OS repos. It is now authored here, with its history
  preserved: `nvim/` carries the same tree object it had in Core, so the first sync back is
  byte-identical by construction rather than by inspection.

  `scripts/audit-nvim.sh` is the gate, in Core's dispatcher shape — numbered fragments under
  `scripts/audit/`, sourced into one shell with one summary and one exit code. Four sections
  came across (the gate's own layout, luacheck, module reachability, the palette contract);
  **§4 is new and is the reason the repo exists**. It installs the committed pins with
  `:Lazy! restore`, starts the editor for real, and runs `:checkhealth gerrrt`. Core's audit
  lints the Lua and walks the module graph but has never started nvim with the plugin set a
  host would actually get — and a `lazy-lock.json` bump is the change this tree receives
  most. 30 of the 102 nvim commits in Core's last quarter were that bot; every one of them
  now gets that check before it can reach a lock.

  `scripts/update-nvim-plugins.sh`, `scripts/nvim-reachability.sh` and the two behavioral
  fragments moved with their history. `scripts/test/80-nvim-reachability.sh` came across as
  `scripts/test/20-reachability.sh` with its other half left behind: lines 18–113 gated a
  `.claude/commands` ↔ workflow contract that has nothing to do with the editor.

- **`theme/palette.toml` is vendored in, and the assertion nothing was running now runs**
  ([dotfiles-core#1122](https://github.com/dotgibson/dotfiles-core/issues/1122)).
  `NVIM-SPLIT-PROPOSAL.md` §3.2/§7(1) describe a `# core:theme:gen` block in the nvim
  colours. There is none and there never was — the editor holds zero hex literals and asks
  the plugin. The real coupling is the reverse: Core's `gen-theme.sh --refresh` resolves the
  palette from the tokyonight revision pinned in `nvim/lazy-lock.json`, at the style named
  in `nvim/lua/gerrrt/utils/palette.lua`, and asserts both agree before it writes. That
  assertion is maintainer-only and never runs on a `--check` path, so across the whole fleet
  it ran nowhere.

  After the split the pin moves here while `palette.toml` stays in Core, so a bump would
  have staled Core's rendered colours silently. `scripts/audit/30-theme.sh` carries the
  assertion, in pure bash, in the repo where the pin now moves — and reads an empty parse as
  its own failure, because two empty strings compare equal.

- **A release line of its own.** `scripts/tag-release.sh` is Core's two-phase shape: phase 1
  proves the tree green and commits `nvim.version` + `CHANGELOG.md` and creates no tag;
  `--publish` resolves the release commit on `origin/main`, then pushes `vX.Y.Z` and the
  moving `vN` alias in one atomic, leased push. Nothing fans out on release —
  `dotfiles-core` bumps its `nvim.lock` with its next release, at its own pace
  (`NVIM-SPLIT-PROPOSAL.md` §7(3)).

- **`stylua.toml`**, and an advisory stylua leg. Nothing has ever formatted this tree; Core
  wired neither shfmt nor stylua. The config is the tree's measured near-fixed-point (Tabs,
  120 columns: 7 of 98 files differ, against 27 at 100), so the leg reports and never reds.
  It becomes a gate once
  [dotfiles-core#1123](https://github.com/dotgibson/dotfiles-core/issues/1123)'s
  byte-identical first sync has landed — until then a red here would be a gate arguing with
  a non-negotiable.

### Fixed

- **The release entry point shipped `100644`, and the gate had no reason to notice.**
  `make publish` died with `Permission denied` before reading a single guard.
  `scripts/audit/05-shape.sh` asserted one direction of the exec-bit rule — every *sourced*
  fragment is non-executable — and nothing asserted the other. Neither the audit nor the
  tests execute `tag-release.sh`, so a full green CI run said nothing. §0a closes it.

### Known gaps

- `pr-link-check` is not ported. Core's version delegates to a 213-line policy script; every
  PR here is currently a numbered step of the split, and porting that policy is scope this
  repo has not earned yet.
- The `:checkhealth` sections still announce themselves as `dotfiles-core:`, and the
  `gerrrt.health` module still calls itself that. Renaming them is a one-line change and the
  wrong one right now: it would break the byte-identical first sync
  ([dotfiles-core#1123](https://github.com/dotgibson/dotfiles-core/issues/1123)), and
  `NVIM-SPLIT-PROPOSAL.md` §6 is explicit that the split moves the tree and does not edit it.

[Unreleased]: https://github.com/dotgibson/dotfiles-nvim/compare/v1.0.0...HEAD
[v1.0.0]: https://github.com/dotgibson/dotfiles-nvim/releases/tag/v1.0.0
