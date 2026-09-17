# scripts/audit/20-reachability.sh
# the module-graph backstop: orphans, dangling requires, the LSP registry
#
# A SOURCED FRAGMENT of scripts/audit-nvim.sh — see scripts/audit/05-shape.sh's header
# for the contract.

# ── 2. nvim module reachability ───────────────────────────────────────────────
# Ported from dotfiles-core's scripts/audit/20-lua.sh §4b. The editor ships as a whole
# directory — nothing enumerates its modules file by file — so no manifest-shaped check
# can see a module that fell out of the graph. scripts/nvim-reachability.sh walks it:
# from nvim/init.lua and gerrrt.health, through require/import edges and the servers
# registry, reporting orphans, dangling requires, duplicate module ids, files no require
# could address, empty lazy imports, and registry↔file disagreements in both directions.
#
# GATE ON BOTH OUTPUT AND EXIT STATUS. The script documents `0 = clean, 1 = findings,
# 2 = usage` as its CLI contract; findings-with-rc-0 and rc≠0-with-no-output are each
# their own failure, because either one means the contract this section keys off has
# broken and a future silent pass is one refactor away. scripts/test/20-reachability.sh
# drives the same script against ~18 synthetic fixtures — this section is the live run.
hdr "nvim module reachability"
if [[ ! -d "$HERE/nvim/lua/gerrrt" ]]; then
  fail "reachability: nvim/lua/gerrrt is missing — this repo IS the editor tree"
elif ! have git; then
  # The script asserts it is inside a work tree before it lists anything.
  skip "nvim module reachability (git not installed)"
else
  _nr_out="$("$HERE/scripts/nvim-reachability.sh" --root "$HERE" 2>&1)"
  _nr_rc=$?
  if ((_nr_rc == 0)) && [[ -z "$_nr_out" ]]; then
    pass "reachability: every module under nvim/lua/gerrrt is reachable, and every require resolves"
  elif ((_nr_rc == 0)) && [[ -n "$_nr_out" ]]; then
    fail "reachability: the script reported findings but exited 0 — its own CLI contract has broken, so a real finding could pass silently"
    fail_detail "$_nr_out"
  elif ((_nr_rc != 0)) && [[ -z "$_nr_out" ]]; then
    fail "reachability: the script exited $_nr_rc and said nothing — a failure with no finding is not a finding to act on"
  else
    while IFS= read -r _nr_line; do
      [[ -n "$_nr_line" ]] && fail "reachability: $_nr_line"
    done <<<"$_nr_out"
  fi
  unset _nr_out _nr_rc _nr_line
fi
