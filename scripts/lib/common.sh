# shellcheck shell=bash
# scripts/lib/common.sh — shared output helpers for this repo's gate scripts.
# ──────────────────────────────────────────────────────────────────────────────
# ONE definition of the colour palette + pass/skip/fail/hdr/have that audit-nvim.sh,
# test-nvim.sh, nvim-reachability.sh and update-nvim-plugins.sh all need.
#
# PORTED FROM dotfiles-core's scripts/lib/common.sh, trimmed to what this repo calls.
# The API is deliberately byte-compatible with Core's: the two moved scripts and the two
# moved test fragments came across unedited, and a future reader diffing them against
# Core's copies should see no helper-shaped noise. What is NOT ported is Core's fleet
# half — load_os_repos, the sibling-repo resolvers, the ~25 hit-scanners — none of which
# has anything to read here.
#
# The palette is hand-rolled rather than sourced from Core's lib/ux.sh on purpose:
# ux.sh carries a `# core:theme:gen` block that Core's gen-theme.sh owns, and vendoring
# a generated file across a repo boundary is the drift class this split exists to avoid.
# The c_* names below are plain ANSI — they were never palette colours.
#
# This is a SOURCED library, not a runnable script — so, exactly like the nvim Lua
# modules, it carries NO shebang and stays mode 100644. The `# shellcheck shell=bash`
# directive above keeps the linter in bash mode without one. bash 3.2-safe (no
# associative arrays / mapfile) so it runs on macOS too.
#
# Usage (from any scripts/*.sh):
#   source "${BASH_SOURCE[0]%/*}/lib/common.sh"
# ──────────────────────────────────────────────────────────────────────────────

# Idempotent: a second source is a no-op (a script + the audit both sourcing it, or
# future nesting, must not redefine or re-zero the counters).
[[ -n "${_CORE_COMMON_SH:-}" ]] && return 0
_CORE_COMMON_SH=1

# Colour MODE, re-evaluable so a script's `--color WHEN` flag can override the default
# AFTER this lib is sourced (the gate scripts source it before their arg loop).
#   auto   (default) — colour on a TTY (or CLICOLOR_FORCE), off when piped/redirected
#   always           — colour regardless of TTY (e.g. piping into `less -R`)
#   never            — never
# NO_COLOR (https://no-color.org) is a hard override-OFF that wins over `always`.
: "${CORE_COLOR:=auto}"

_core_palette() {
  local on=0
  case "${CORE_COLOR:-auto}" in
  always) on=1 ;;
  never) on=0 ;;
  *) { [[ -t 1 || -n "${CLICOLOR_FORCE:-}" ]]; } && on=1 ;;
  esac
  [[ -n "${NO_COLOR:-}" ]] && on=0
  if ((on)); then
    c_grn=$'\e[32m' c_yel=$'\e[33m' c_red=$'\e[31m' c_blu=$'\e[34m' c_rst=$'\e[0m'
  else
    c_grn='' c_yel='' c_red='' c_blu='' c_rst=''
  fi
}
_core_palette

# _core_set_color <when> — validate WHEN (auto|always|never) and re-evaluate the palette.
# Non-zero on a bad value so the caller can usage-error. Every gate script's `--color`
# flag routes through this; `CORE_COLOR=<when>` in the environment works without a flag.
_core_set_color() {
  case "$1" in
  auto | always | never)
    CORE_COLOR="$1"
    _core_palette
    return 0
    ;;
  *) return 1 ;;
  esac
}

# Tallies + quiet flag. Initialised with `:=` so a caller that runs under `set -u`
# (all of them) never trips an unbound-variable error on the first pass()/skip().
# A script that doesn't count (update-nvim-plugins) simply ignores the totals.
: "${QUIET:=0}"
: "${PASS:=0}"
: "${SKIP:=0}"
: "${FAIL:=0}"

# Labels of the checks that SKIPPED, so a caller can report exactly WHICH gates didn't
# run (e.g. a CI-installed linter absent locally) instead of just a count — the
# difference between "green" and "green but partial".
_CORE_SKIPS=()
# ENVIRONMENT skips — a distinct class. A skip is one of:
#   · tool absent    — a real coverage gap; --strict reds on it
#   · environment    — the run COULD NOT cover it here (no network for a plugin sync)
# Recorded STRUCTURALLY, by index, rather than by matching the message text: making the
# wording honest must never silently change gate behaviour.
_CORE_ENV_SKIPS=()
_CORE_ENV_SKIP_IDX=()
_CORE_NOTE_SKIP_IDX=()

have() { command -v "$1" >/dev/null 2>&1; }

pass() {
  PASS=$((PASS + 1))
  ((QUIET)) || printf '%s✓%s %s\n' "$c_grn" "$c_rst" "$*"
}

skip() {
  SKIP=$((SKIP + 1))
  _CORE_SKIPS[${#_CORE_SKIPS[@]}]="$*"
  ((QUIET)) || printf '%s•%s %s (skipped)\n' "$c_yel" "$c_rst" "$*"
}

# skip_env — the run could not COVER this here, as opposed to a tool being absent.
# Records the class by INDEX into _CORE_SKIPS, never by the message text, so the
# classifier cannot be changed by a reword.
skip_env() {
  skip "$@"
  _CORE_ENV_SKIPS[${#_CORE_ENV_SKIPS[@]}]="$*"
  _CORE_ENV_SKIP_IDX[${#_CORE_ENV_SKIP_IDX[@]}]=$((${#_CORE_SKIPS[@]} - 1))
}

# skip_note — a skip nothing should ever red on, not even --strict. Separate from the
# environment list because the two answer different questions.
skip_note() {
  skip "$@"
  _CORE_NOTE_SKIP_IDX[${#_CORE_NOTE_SKIP_IDX[@]}]=$((${#_CORE_SKIPS[@]} - 1))
}

# _core_tool_skip_count — how many skips are a real coverage gap (a tool the box lacks),
# i.e. neither environment nor note. This is what --strict reds on.
_core_tool_skip_count() {
  local i n=0 j is_classed
  for ((i = 0; i < ${#_CORE_SKIPS[@]}; i++)); do
    is_classed=0
    for j in ${_CORE_ENV_SKIP_IDX[@]+"${_CORE_ENV_SKIP_IDX[@]}"} ${_CORE_NOTE_SKIP_IDX[@]+"${_CORE_NOTE_SKIP_IDX[@]}"}; do
      [[ "$i" == "$j" ]] && { is_classed=1; break; }
    done
    ((is_classed)) || n=$((n + 1))
  done
  printf '%s' "$n"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '%s✗%s %s\n' "$c_red" "$c_rst" "$*" >&2
}

# fail_detail — the evidence under a fail(), bounded so a 4,000-line luacheck dump
# cannot bury the summary. CORE_FAIL_DETAIL_LINES=0 means unbounded.
fail_detail() {
  local lines="${CORE_FAIL_DETAIL_LINES:-40}" body="$*" n
  n="$(printf '%s\n' "$body" | grep -c . || true)"
  if ((lines > 0)) && ((n > lines)); then
    printf '%s\n' "$body" | head -n "$lines" | sed 's/^/    /' >&2
    printf '    … %s more line(s); set CORE_FAIL_DETAIL_LINES=0 for all\n' "$((n - lines))" >&2
  else
    printf '%s\n' "$body" | sed 's/^/    /' >&2
  fi
}

hdr() { ((QUIET)) || printf '\n%s== %s ==%s\n' "$c_blu" "$*" "$c_rst"; }

# _audit_ls <pathspec>… — the content-gate file set: tracked files PLUS untracked ones
# that are not ignored, deduped. Untracked matters because a gate that reads only
# `git ls-files` is blind to the file you just created and have not added yet — which is
# exactly when you want it to speak up.
_audit_ls() {
  {
    git ls-files -- "$@" 2>/dev/null
    git ls-files --others --exclude-standard -- "$@" 2>/dev/null
  } | sort -u
}

# core_files_identical <a> <b> — 0 iff byte-identical. `cmp`/`diff` are deliberately not
# used: git is the one tool every gate here already requires, and `--no-index` makes it
# answer the question without touching the index.
core_files_identical() {
  [[ -f "$1" && -f "$2" ]] || return 2
  git diff --quiet --no-index -- "$1" "$2" 2>/dev/null
}

# _core_luacheck_verdict <probe-rc> <lint-rc> — classify a luacheck run.
# The PROBE (`luacheck --version`) runs first and separately, so a broken luarocks
# wrapper is reported as a toolchain fault rather than as a defect in the Lua tree.
#   ok            — probe fine, lint clean
#   broken        — probe itself failed; the tool never ran
#   broken-midrun — probe fine but lint died the way a shell reports a tool it could not
#                   run (rc ≥ 126), which luacheck never uses for findings
#   issues        — probe fine, lint reported lint
# Verbatim from Core's copy, including the four verdict words: the audit fragment that
# renders them is a port too, and a reworded verdict here would diverge silently.
_core_luacheck_verdict() { # _core_luacheck_verdict <probe-rc> <lint-rc>
  local probe_rc="${1:-0}" lint_rc="${2:-0}"
  case "$probe_rc" in 0) ;; *) printf 'broken\n'; return 0 ;; esac
  case "$lint_rc" in 0) printf 'ok\n'; return 0 ;; esac
  if [ "$lint_rc" -ge 126 ] 2>/dev/null; then printf 'broken-midrun\n'; return 0; fi
  printf 'issues\n'
}
