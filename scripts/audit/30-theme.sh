# scripts/audit/30-theme.sh
# the palette contract across the vendor boundary: the tokyonight pin and the style
#
# A SOURCED FRAGMENT of scripts/audit-nvim.sh — see scripts/audit/05-shape.sh's header
# for the contract.

# ── 3. theme/palette.toml ⇄ the editor ────────────────────────────────────────
# WHY THIS SECTION EXISTS, AND WHY IT IS HERE AND NOT IN CORE.
#
# dotfiles-core's rule is "colour is generated, not typed": theme/palette.toml is the one
# place a hex is authored, and gen-theme.sh renders every consumer from it. The editor was
# always the exception that proved it — nvim/ holds zero hex literals and asks the plugin
# (nvim/lua/gerrrt/utils/palette.lua), so it carries no generated block and never did.
# NVIM-SPLIT-PROPOSAL.md §3.2/§7(1) describe one; there is none, and never was.
#
# What DOES couple the two is the other direction, and it is real: palette.toml's resolved
# colours are produced by `gen-theme.sh --refresh` from the tokyonight revision pinned in
# nvim/lazy-lock.json, at the style named in palette.lua. --refresh asserts both of those
# agree before it writes — but --refresh is maintainer-only, needs a live nvim with the
# plugin installed, and deliberately never runs on the --check path, so on every CI leg in
# the fleet those two assertions run NOWHERE.
#
# Before the split that was survivable: one repo, one commit, one reviewer. After it the
# freshness bot moves the tokyonight pin HERE while palette.toml stays THERE, and Core's
# rendered colours go quietly stale against a plugin revision no longer installed anywhere.
# So palette.toml is vendored in (theme/.core-ref records which Core commit from), and the
# assertion half of --refresh runs on every pin bump, in the repo where the pin now moves.
# Pure sed+bash: no nvim, no plugin, no network — so it cannot skip itself green.
#
# The precedent for vendoring this file rather than its outputs is dotfiles-Windows, which
# has no core/ at all: theme-sync.ps1 copies palette.toml beside a theme/.core-ref and its
# CI hash-gates the pair. This is the second such consumer.
hdr "theme/palette.toml ⇄ the editor"

_th_pal="$HERE/theme/palette.toml"
_th_lock="$HERE/nvim/lazy-lock.json"
_th_lua="$HERE/nvim/lua/gerrrt/utils/palette.lua"
_th_ref="$HERE/theme/.core-ref"

if [[ ! -r "$_th_pal" ]]; then
  fail "theme: $_th_pal is unreadable — the vendored palette is the input this section checks"
elif [[ ! -r "$_th_lock" || ! -r "$_th_lua" ]]; then
  fail "theme: nvim/lazy-lock.json or nvim/lua/gerrrt/utils/palette.lua is unreadable"
else
  # The same anchored one-line sed expressions gen-theme.sh uses, deliberately: a second
  # spelling of "read the tokyonight pin" is a second thing to keep in step.
  _th_lock_sha="$(sed -n 's/.*"tokyonight\.nvim": *{ *"branch": *"[^"]*", *"commit": *"\([0-9a-f]*\)".*/\1/p' "$_th_lock")"
  _th_pal_sha="$(sed -n 's/^source_commit[[:space:]]*=[[:space:]]*"\([0-9a-f]*\)".*/\1/p' "$_th_pal")"
  _th_lua_style="$(sed -n 's/^M\.style[[:space:]]*=[[:space:]]*"\([a-z]*\)".*/\1/p' "$_th_lua")"
  _th_pal_style="$(sed -n 's/^style[[:space:]]*=[[:space:]]*"\([a-z]*\)".*/\1/p' "$_th_pal")"

  # An EMPTY read is its own failure, never a silent pass. Two empty strings compare
  # equal, so a lockfile whose format changed would otherwise green this section forever —
  # which is exactly the shape of gate this repo was extracted to stop shipping.
  if [[ -z "$_th_lock_sha" ]]; then
    fail "theme: no tokyonight.nvim pin could be read out of nvim/lazy-lock.json — the format changed, and the comparison below would have passed on two empty strings"
  elif [[ -z "$_th_pal_sha" ]]; then
    fail "theme: theme/palette.toml has no source_commit — re-vendor it from dotfiles-core"
  elif [[ "$_th_lock_sha" == "$_th_pal_sha" ]]; then
    pass "theme: palette.toml's source_commit matches the tokyonight pin (${_th_lock_sha:0:12})"
  else
    fail "theme: the tokyonight pin moved and dotfiles-core's palette did not follow it"
    fail_detail "nvim/lazy-lock.json : $_th_lock_sha
theme/palette.toml  : $_th_pal_sha
fix: in dotfiles-core, run ./scripts/gen-theme.sh --refresh against this pin, then
     re-vendor theme/palette.toml here (theme/.core-ref records where it came from)"
  fi

  if [[ -z "$_th_lua_style" ]]; then
    fail "theme: no M.style could be read out of nvim/lua/gerrrt/utils/palette.lua"
  elif [[ -z "$_th_pal_style" ]]; then
    fail "theme: theme/palette.toml has no style — re-vendor it from dotfiles-core"
  elif [[ "$_th_lua_style" == "$_th_pal_style" ]]; then
    pass "theme: palette.lua's M.style matches palette.toml's style ($_th_lua_style)"
  else
    fail "theme: the editor's tokyonight style disagrees with the palette Core renders from"
    fail_detail "nvim/lua/gerrrt/utils/palette.lua : $_th_lua_style
theme/palette.toml                : $_th_pal_style"
  fi
  unset _th_lock_sha _th_pal_sha _th_lua_style _th_pal_style
fi

# ── 3b. theme/.core-ref — where the vendored palette came from ────────────────
# A vendored file with no provenance is a file nobody can re-derive. The shape is
# dotfiles-Windows' nvim/.core-ref and theme/.core-ref: flat `key = value`, with `commit`
# the load-bearing one.
if [[ ! -r "$_th_ref" ]]; then
  fail "theme: theme/.core-ref is missing — theme/palette.toml is vendored, and a vendored file with no provenance cannot be re-derived or checked for lag"
else
  _th_ref_commit="$(sed -n 's/^commit[[:space:]]*=[[:space:]]*\([0-9a-f]\{7,40\}\).*/\1/p' "$_th_ref")"
  _th_ref_src="$(sed -n 's/^source[[:space:]]*=[[:space:]]*\(.*\)$/\1/p' "$_th_ref")"
  if [[ -z "$_th_ref_commit" ]]; then
    fail "theme: theme/.core-ref names no commit — it records nothing"
  elif [[ "$_th_ref_src" != *dotfiles-core* ]]; then
    fail "theme: theme/.core-ref's source is '$_th_ref_src' — the palette is authored in dotfiles-core and vendored from there"
  else
    pass "theme: palette.toml's provenance is recorded (dotfiles-core ${_th_ref_commit:0:12})"
  fi
  unset _th_ref_commit _th_ref_src
fi

unset _th_pal _th_lock _th_lua _th_ref
