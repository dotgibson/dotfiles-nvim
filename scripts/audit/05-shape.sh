# scripts/audit/05-shape.sh
# the gate's own layout contract: fragments are numbered and sourced, entry points are runnable
#
# A SOURCED FRAGMENT of scripts/audit-nvim.sh — not a standalone script. It runs in the
# dispatcher's shell and uses its state: the PASS/SKIP/FAIL counters, $HERE (already cd'd
# to), $SANDBOX, and the pass/skip/fail/hdr/have helpers from scripts/lib/common.sh. NO
# EXIT TRAP HERE: the dispatcher installs the one that removes $SANDBOX, and
# `trap … EXIT` REPLACES rather than appends.

# ── 0. the gate's own layout (scripts/audit/, scripts/test/) ──────────────────
# Both dispatchers glob `[0-9][0-9]-*.sh`. That is the right shape — there is no registry
# to forget — but it buys that at the price of a new way to write a gate that never runs:
# drop `scripts/audit/helpers.sh` in beside the others and the glob skips it in silence
# while the run reports `audit OK`. That failure looks exactly like success, which is the
# class of defect this gate exists to catch everywhere else. So the layout is asserted,
# not assumed. Ported from dotfiles-core's scripts/audit/05-shape.sh and
# scripts/test/05-suite-shape.sh, which are the same check on the same glob.
# Pure bash, and numbered 05 so it runs before anything it describes.
hdr "the gate's own layout (scripts/audit/, scripts/test/)"

_as_stray='' _as_exec='' _as_untracked='' _as_unbannered='' _as_shebang=''
_as_total=0
for _as_dir in "$HERE/scripts/audit" "$HERE/scripts/test"; do
  _as_rel="${_as_dir#"$HERE"/}"
  for _as_f in "$_as_dir"/*.sh; do
    [[ -e "$_as_f" ]] || break
    _as_b="${_as_rel}/${_as_f##*/}"
    case "${_as_f##*/}" in
    [0-9][0-9]-*.sh) _as_total=$((_as_total + 1)) ;;
    *) _as_stray="${_as_stray:+$_as_stray }$_as_b" ;;
    esac
    # Sourced libraries, so 100644. The working tree is what actually gets sourced and
    # what a stray `chmod +x` would break first, so check that rather than the index.
    [[ -x "$_as_f" ]] && _as_exec="${_as_exec:+$_as_exec }$_as_b"
    # A shebang on a sourced library is a claim it can be run on its own. It cannot: it
    # would start with no counters, no $HERE and no helpers, and report nothing.
    head -1 "$_as_f" | grep -q '^#!' && _as_shebang="${_as_shebang:+$_as_shebang }$_as_b"
    # Every fragment is a gate, and a gate announces itself with at least one
    # `# ── <id>. ` banner. A file with none is a slice that lost its banner in a cut.
    grep -qE '^# ── [0-9][0-9a-z-]*\. ' "$_as_f" || grep -qE '^# ── ' "$_as_f" ||
      _as_unbannered="${_as_unbannered:+$_as_unbannered }$_as_b"
    # Untracked fragments run locally and vanish in CI — coverage that exists on exactly
    # one machine.
    git ls-files --error-unmatch -- "$_as_f" >/dev/null 2>&1 ||
      _as_untracked="${_as_untracked:+$_as_untracked }$_as_b"
  done
done

if ((_as_total == 0)); then
  fail "gate layout: no numbered fragments found — the dispatchers should have refused to run at all"
elif [[ -n "$_as_stray" ]]; then
  fail "gate layout: not matched by the dispatcher's [0-9][0-9]-*.sh glob, so never sourced: $_as_stray — rename it with an NN- prefix, or it is a gate that reads as coverage"
else
  pass "gate layout: all $_as_total fragments carry the NN- prefix the dispatchers glob (none silently unsourced)"
fi

if [[ -z "$_as_exec" ]]; then
  pass "gate layout: every fragment is non-executable (a sourced library, not a script)"
else
  fail "gate layout: executable fragment(s): $_as_exec — sourced libraries are 100644; chmod -x"
fi

if [[ -z "$_as_shebang" ]]; then
  pass "gate layout: no fragment carries a shebang"
else
  fail "gate layout: fragment(s) with a shebang: $_as_shebang — a sourced library cannot run standalone; drop it"
fi

if [[ -z "$_as_untracked" ]]; then
  pass "gate layout: every fragment is tracked (runs in CI, not only here)"
else
  fail "gate layout: untracked fragment(s): $_as_untracked — git add them, or they are coverage on one machine"
fi

if [[ -z "$_as_unbannered" ]]; then
  pass "gate layout: every fragment names its section with a ── banner"
else
  fail "gate layout: fragment(s) with no section banner: $_as_unbannered — a gate that names nothing cannot be cited"
fi

# ── 0a. the RUNNABLE scripts are executable ───────────────────────────────────
# The other direction of the rule above, and it is not symmetry for its own sake: a
# dispatcher committed 100644 is a gate nobody can run. `make audit` dies with "Permission
# denied" before a single section is sourced — which is at least loud — but
# scripts/tag-release.sh was committed 100644 in this repo's first commit and the omission
# survived a full green CI run, because nothing on the gate's path executes it. It surfaced
# only when someone tried to cut a release.
#
# So: everything directly under scripts/ has a shebang and is meant to be run; everything
# under scripts/lib/, scripts/audit/ and scripts/test/ is sourced. Assert both halves.
_as_notexec=''
for _as_f in "$HERE"/scripts/*.sh; do
  [[ -e "$_as_f" ]] || break
  [[ -x "$_as_f" ]] || _as_notexec="${_as_notexec:+$_as_notexec }scripts/${_as_f##*/}"
done
if [[ -z "$_as_notexec" ]]; then
  pass "gate layout: every runnable script under scripts/ is executable"
else
  fail "gate layout: non-executable runnable script(s): $_as_notexec — chmod +x, or it is an entry point nothing can call"
fi
unset _as_notexec

# ── 0b. no fragment installs its own EXIT trap ────────────────────────────────
# `trap … EXIT` REPLACES rather than appends, so a second handler anywhere under
# scripts/{audit,test}/ would silently take the dispatcher's $SANDBOX cleanup with it —
# leaving a directory per run under /tmp for nobody to notice, and, in the plugin-sync
# section, a directory with 60-odd git clones in it.
_as_traps="$(grep -lE '^[[:space:]]*trap[[:space:]].*EXIT' "$HERE"/scripts/audit/[0-9][0-9]-*.sh "$HERE"/scripts/test/[0-9][0-9]-*.sh 2>/dev/null || true)"
if [[ -z "$_as_traps" ]]; then
  pass "gate layout: no fragment installs an EXIT trap (the dispatcher owns the only one)"
else
  fail "gate layout: fragment(s) installing an EXIT trap:"
  fail_detail "$_as_traps"
fi

unset _as_dir _as_rel _as_f _as_b _as_stray _as_exec _as_untracked _as_unbannered \
  _as_shebang _as_total _as_traps
