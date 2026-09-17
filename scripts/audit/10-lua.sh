# scripts/audit/10-lua.sh
# luacheck over the editor tree, plus stylua as an advisory formatter report
#
# A SOURCED FRAGMENT of scripts/audit-nvim.sh — see scripts/audit/05-shape.sh's header
# for the contract.

# ── 1. luacheck (nvim/) ───────────────────────────────────────────────────────
# Ported from dotfiles-core's scripts/audit/20-lua.sh §4, verbatim in behaviour, and it
# STAYS THERE TOO: per NVIM-SPLIT-PROPOSAL.md §7(2) Core keeps its own luacheck leg over
# the vendored copy, because a corrupt sync is a failure a vendored tree has and a source
# tree does not. This is the source tree's copy.
hdr "luacheck (nvim/)"
if ! have luacheck; then
  # luacheck 1.2.0 needs Lua 5.4: 5.5 made some locals const and luacheck's own source
  # fails to load under it. The CI legs pin the interpreter for that reason.
  skip "luacheck (not installed — luarocks --local install luacheck, against Lua 5.4)"
else
  # PROBE FIRST, and separately. A broken luarocks wrapper exits non-zero with a stack
  # trace, and running it straight at the tree would report a toolchain fault as a defect
  # in nvim/ — sending the reader to the wrong file.
  _lua_probe_out="$(luacheck --version 2>&1)"
  _lua_probe_rc=$?
  # The `cd` is MANDATORY, not tidiness: luacheck searches UPWARD from the working
  # directory for .luacheckrc, so running it from the repo root would silently lint the
  # tree with default settings — no `vim` global, and a line-length limit the tree has
  # never observed.
  _lua_out="$( (cd "$HERE/nvim" && luacheck . --no-color) 2>&1)"
  _lua_rc=$?
  case "$(_core_luacheck_verdict "$_lua_probe_rc" "$_lua_rc")" in
  ok) pass "luacheck: nvim/ is clean ($(luacheck --version 2>/dev/null | head -1))" ;;
  broken)
    fail "luacheck: the tool itself failed to run — this is a toolchain fault, not a defect in nvim/"
    fail_detail "$_lua_probe_out"
    ;;
  broken-midrun)
    fail "luacheck: ran, then died with exit $_lua_rc — a rc luacheck never uses for findings"
    fail_detail "$_lua_out"
    ;;
  *)
    fail "luacheck: findings in nvim/"
    fail_detail "$_lua_out"
    ;;
  esac
  unset _lua_probe_out _lua_probe_rc _lua_out _lua_rc
fi

# ── 1b. stylua — ADVISORY, deliberately, until the vendoring lands ────────────
# Nothing has ever formatted this tree: dotfiles-core wired neither shfmt nor stylua into
# any gate (.editorconfig says so outright), and stylua existed there only as a
# Mason-installed formatter inside nvim/lua/gerrrt/plugins/conform.lua. Against
# stylua.toml at this repo's root, seven of ninety-eight files currently differ.
#
# Reformatting them is a ONE-LINE change to make and the wrong thing to do right now, for
# two reasons that both expire at the same moment:
#   · NVIM-SPLIT-PROPOSAL.md §6 — the split MOVES the tree, it does not edit it;
#   · dotgibson/dotfiles-core#1123 — Core's first sync back must be BYTE-IDENTICAL, and a
#     formatting pass here is precisely what would make it not.
# So this leg reports and never reds. It flips to a gate once that first sync has landed;
# until then a red here would be a gate arguing with a non-negotiable.
hdr "stylua (advisory)"
if ! have stylua; then
  skip_note "stylua (not installed — advisory leg, never red)"
else
  _sty_out="$(cd "$HERE" && stylua --check nvim 2>&1)"
  _sty_n="$(printf '%s\n' "$_sty_out" | grep -c '^Diff in' || true)"
  if ((_sty_n == 0)); then
    # Worth saying loudly: this is the state in which the leg can become a gate.
    pass "stylua: nvim/ is a fixed point — this leg can be made blocking (see #1123)"
  else
    skip_note "stylua: $_sty_n file(s) differ — advisory until #1123's byte-identical sync lands"
    ((QUIET)) || printf '%s\n' "$_sty_out" | grep '^Diff in' | sed 's/^/    /'
  fi
  unset _sty_out _sty_n
fi
