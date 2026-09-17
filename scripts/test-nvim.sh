#!/usr/bin/env bash
# scripts/test-nvim.sh — the behavioral suite for dotfiles-nvim.
# ──────────────────────────────────────────────────────────────────────────────
# THE SECTIONS LIVE IN scripts/test/NN-name.sh — one numbered fragment per subject —
# and this file is the dispatcher that globs them in NN order and SOURCES them into its
# own shell: one $SANDBOX, one set of counters, one summary. Adding a section is adding
# a file; there is no registry to update. Same shape, same reasons, as audit-nvim.sh.
#
# THE FRAGMENTS ARE SOURCED LIBRARIES: no shebang, mode 100644, and no EXIT trap of
# their own — this script owns the one that removes $SANDBOX, and `trap … EXIT`
# replaces rather than appends.
#
# BOTH FRAGMENTS CAME ACROSS FROM dotfiles-core UNEDITED except for their headers:
# 15-nvim.sh is scripts/test/15-nvim.sh verbatim, and 20-reachability.sh is the nvim
# half of scripts/test/80-nvim-reachability.sh (its other half gated a Core routine
# contract that has nothing to do with the editor, and stayed there). That is why
# SCOPE_NVIM still exists below: in this repo every fragment is in scope by
# construction, but pinning it to 1 here keeps the moved files diffable against Core's
# copies for as long as both exist, which matters while the split is still landing.
#
# `set -e` is deliberately NOT used — one failing section must not abort the rest.
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 2

# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

JSON=0
# Everything in this repo is the editor, so every fragment is in scope. See the header.
# SC2034: read by the SOURCED fragments under scripts/test/, which ShellCheck cannot
# follow from this file.
# shellcheck disable=SC2034
SCOPE_NVIM=1

while (($#)); do
  case "$1" in
  -q | --quiet) QUIET=1 ;;
  --json)
    JSON=1
    QUIET=1
    CORE_JSON=1
    export CORE_JSON
    ;;
  --color) shift || true; _core_set_color "${1:-}" || { printf 'test-nvim.sh: --color wants auto|always|never\n' >&2; exit 2; } ;;
  --color=*) _core_set_color "${1#--color=}" || { printf 'test-nvim.sh: --color wants auto|always|never\n' >&2; exit 2; } ;;
  -h | --help)
    cat <<'EOF'
usage: test-nvim.sh [options]

  -q, --quiet     only the summary and any failures
      --color WHEN  auto (default) | always | never; NO_COLOR still wins
      --json      machine-readable summary on stdout (implies --quiet)
  -h, --help      show this help and exit
EOF
    exit 0
    ;;
  *)
    printf 'test-nvim.sh: unexpected argument: %s\n' "$1" >&2
    printf 'try: test-nvim.sh --help\n' >&2
    exit 2
    ;;
  esac
  shift
done

# STOP CORE_JSON AT THIS PROCESS BOUNDARY. CORE_JSON=1 means "stdout carries only the
# JSON object", which is right for THIS script and wrong for every child it runs: the
# fragments execute real scripts and assert on their human-readable output, skip() lines
# included. `export -n` keeps the value readable here while no child inherits it.
export -n CORE_JSON 2>/dev/null || true

SECONDS=0

# When invoked from audit-nvim.sh (CORE_TEST_NESTED=1) the audit owns the summary, so we
# suppress ours and signal pass/fail only through the exit code.
NESTED="${CORE_TEST_NESTED:-0}"
summary() {
  [[ "$NESTED" == 1 ]] && return 0
  if ((JSON)); then
    local _result _first=1 _s
    ((FAIL == 0)) && _result=ok || _result=failed
    printf '{"pass":%d,"skip":%d,"fail":%d,"seconds":%d,"skipped":[' \
      "$PASS" "$SKIP" "$FAIL" "$SECONDS"
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
  printf '\n%s──────── test summary ────────%s\n' "$c_blu" "$c_rst"
  printf '  %spass %d%s   %sskip %d%s   %sfail %d%s   %s(%ds)%s\n' \
    "$c_grn" "$PASS" "$c_rst" "$c_yel" "$SKIP" "$c_rst" "$c_red" "$FAIL" "$c_rst" \
    "$c_blu" "$SECONDS" "$c_rst"
}

# One throwaway sandbox for the whole run; clean it up no matter how we exit.
SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/nvim-test.XXXXXX")"
# shellcheck disable=SC2317,SC2329  # invoked indirectly, by the EXIT trap installed below
_nvim_test_cleanup() {
  rm -rf "$SANDBOX"
  return 0
}
trap '_nvim_test_cleanup' EXIT

_nvim_frags=0
for _nvim_frag in "$HERE"/scripts/test/[0-9][0-9]-*.sh; do
  [[ -e "$_nvim_frag" ]] || break
  # shellcheck source=/dev/null
  source "$_nvim_frag"
  _nvim_frags=$((_nvim_frags + 1))
done
if ((_nvim_frags == 0)); then
  printf 'test-nvim.sh: no fragments found under scripts/test/ — the suite ran NOTHING\n' >&2
  exit 2
fi
unset _nvim_frag _nvim_frags

summary
if ((FAIL == 0)); then
  { [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests OK%s\n' "$c_grn" "$c_rst"
  exit 0
fi
{ [[ "$NESTED" == 1 ]] || ((JSON)); } || printf '%stests FAILED%s\n' "$c_red" "$c_rst" >&2
exit 1
