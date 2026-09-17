#!/usr/bin/env bash
# scripts/audit-nvim.sh — the one gate for dotfiles-nvim.
# ──────────────────────────────────────────────────────────────────────────────
# "Is the editor healthy?" has exactly one definition and this is it. CI, pre-commit
# and `make audit` all call this script, so a green run here is a green run there.
#
# THE SECTIONS LIVE IN scripts/audit/NN-name.sh — one numbered fragment per subject —
# and this file is the dispatcher that globs them in NN order and SOURCES them into its
# own shell: one set of counters, one summary, one exit code, one EXIT trap, one CLI.
# Adding a section is adding a file; there is no registry to update. Ported from
# dotfiles-core's scripts/audit-core.sh, which arrived at this shape in #699.
#
# THE FRAGMENTS ARE SOURCED LIBRARIES, so they carry no shebang, stay mode 100644, and
# must not install an EXIT trap of their own — `trap … EXIT` REPLACES rather than
# appends, so a second one would silently take this script's cleanup with it.
# scripts/audit/05-shape.sh asserts all of that, and fails the run if a fragment has no
# NN- prefix or two fragments wear the same section id.
#
# WHAT THIS GATE HAS THAT CORE'S DOES NOT: §4, a real `Lazy! restore` onto the committed
# pins followed by a headless start and `:checkhealth gerrrt`. That check is the whole
# reason the editor was extracted — Core's audit lints the Lua and walks the module
# graph, but it never starts the editor with the plugin set a host would actually get,
# which is the change class this tree receives most (NVIM-SPLIT-PROPOSAL.md §3.3).
#
# `set -e` is deliberately NOT used: one failing section must not abort the rest, or the
# first red hides every other finding and the gate takes N runs to clear instead of one.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 2

# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

STRICT=0
JSON=0
# SC2034: OFFLINE is assigned here and read by the SOURCED fragments under scripts/audit/,
# which ShellCheck cannot follow from this file. Same reason STRICT is exempt below.
# shellcheck disable=SC2034
OFFLINE="${DOTFILES_NVIM_OFFLINE:-0}"

# SC2034 again, for the same reason as the assignment above — and on the LOOP, because a
# ShellCheck directive is only valid in front of a complete command, never a case branch.
# shellcheck disable=SC2034
while (($#)); do
  case "$1" in
  -q | --quiet) QUIET=1 ;;
  --strict) STRICT=1 ;;
  --offline) OFFLINE=1 ;;
  --json)
    JSON=1
    QUIET=1
    CORE_JSON=1
    export CORE_JSON
    ;;
  --color) shift || true; _core_set_color "${1:-}" || { printf 'audit-nvim.sh: --color wants auto|always|never\n' >&2; exit 2; } ;;
  --color=*) _core_set_color "${1#--color=}" || { printf 'audit-nvim.sh: --color wants auto|always|never\n' >&2; exit 2; } ;;
  -h | --help)
    cat <<'EOF'
usage: audit-nvim.sh [options]

  -q, --quiet     only the summary and any failures
      --strict    a tool-absent SKIP is red (what CI runs)
      --offline   skip the sections that need the network (the plugin sync)
      --color WHEN  auto (default) | always | never; NO_COLOR still wins
      --json      machine-readable summary on stdout (implies --quiet)
  -h, --help      show this help and exit
EOF
    exit 0
    ;;
  *)
    printf 'audit-nvim.sh: unexpected argument: %s\n' "$1" >&2
    printf 'try: audit-nvim.sh --help\n' >&2
    exit 2
    ;;
  esac
  shift
done

SECONDS=0

# One throwaway sandbox for the whole run, cleaned up no matter how we exit. §4 builds a
# complete XDG tree in here and syncs 60-odd plugins into it, so it is not small — which
# is exactly why the cleanup is a trap and not a line at the bottom.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/nvim-audit.XXXXXX")"
# ONE handler, because `trap … EXIT` REPLACES rather than appends.
# shellcheck disable=SC2317,SC2329  # invoked indirectly, by the EXIT trap installed below
_nvim_audit_cleanup() {
  rm -rf "$SANDBOX"
  return 0
}
trap '_nvim_audit_cleanup' EXIT

summary() {
  if ((JSON)); then
    local _result _first=1 _s _tool_skips
    ((FAIL == 0)) && _result=ok || _result=failed
    _tool_skips="$(_core_tool_skip_count)"
    printf '{"pass":%d,"skip":%d,"fail":%d,"seconds":%d,"strict":%d,"tool_skips":%s,"skipped":[' \
      "$PASS" "$SKIP" "$FAIL" "$SECONDS" "$STRICT" "$_tool_skips"
    for _s in ${_CORE_SKIPS[@]+"${_CORE_SKIPS[@]}"}; do
      _s="${_s//\\/\\\\}"
      _s="${_s//\"/\\\"}"
      ((_first)) || printf ','
      printf '"%s"' "$_s"
      _first=0
    done
    printf '],"result":"%s"}\n' "$_result"
    return 0
  fi
  printf '\n%s──────── audit summary ────────%s\n' "$c_blu" "$c_rst"
  printf '  %spass %d%s   %sskip %d%s   %sfail %d%s   %s(%ds)%s\n' \
    "$c_grn" "$PASS" "$c_rst" "$c_yel" "$SKIP" "$c_rst" "$c_red" "$FAIL" "$c_rst" \
    "$c_blu" "$SECONDS" "$c_rst"
  local _s
  for _s in ${_CORE_SKIPS[@]+"${_CORE_SKIPS[@]}"}; do
    printf '  %s• %s%s\n' "$c_yel" "$_s" "$c_rst"
  done
}

# ── source every section, in NN order ─────────────────────────────────────────
# An EMPTY GLOB is a hard failure, never a clean run: a dispatcher that finds no
# sections and exits 0 reads as coverage, which is the one thing a gate must never do.
_nvim_frags=0
for _nvim_frag in "$HERE"/scripts/audit/[0-9][0-9]-*.sh; do
  [[ -e "$_nvim_frag" ]] || break
  # shellcheck source=/dev/null
  source "$_nvim_frag"
  _nvim_frags=$((_nvim_frags + 1))
done
if ((_nvim_frags == 0)); then
  printf 'audit-nvim.sh: no sections found under scripts/audit/ — the gate checked NOTHING\n' >&2
  exit 2
fi
unset _nvim_frag _nvim_frags

# ── the behavioral suite, folded into this run ────────────────────────────────
# CORE_TEST_NESTED=1 tells test-nvim.sh the audit owns the summary: it prints its
# sections, suppresses its own totals, and signals only through its exit code.
hdr "behavioral suite (scripts/test-nvim.sh)"
if CORE_TEST_NESTED=1 QUIET="$QUIET" "$HERE/scripts/test-nvim.sh"; then
  pass "behavioral suite"
else
  fail "behavioral suite reported failures — see above"
fi

summary

# --strict turns a tool-absent SKIP red. That is what CI runs, because on a runner every
# gate tool is installed on purpose: a skip there means the install step silently did not
# happen, and a gate that skipped itself green is the failure this posture exists to catch.
_strict_gap=0
if ((STRICT)); then
  _strict_gap="$(_core_tool_skip_count)"
  ((_strict_gap == 0)) || printf '%s✗ --strict: %s section(s) skipped for a missing tool%s\n' \
    "$c_red" "$_strict_gap" "$c_rst" >&2
fi

if ((FAIL == 0)) && ((_strict_gap == 0)); then
  if ((JSON)); then :; elif ((SKIP > 0)); then
    printf '%saudit OK — PARTIAL (%d skipped)%s\n' "$c_grn" "$SKIP" "$c_rst"
  else
    printf '%saudit OK%s\n' "$c_grn" "$c_rst"
  fi
  exit 0
fi
((JSON)) || printf '%saudit FAILED%s\n' "$c_red" "$c_rst" >&2
exit 1
