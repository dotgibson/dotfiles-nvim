#!/usr/bin/env bash
# scripts/tag-release.sh — finish a release, in TWO phases: commit, then (after the PR
# merges) publish the tags.
# ──────────────────────────────────────────────────────────────────────────────
# PORTED FROM dotfiles-core's scripts/tag-release.sh, which is where the shape and every
# guard below were paid for. Adapted, not copied: this repo's version file is
# nvim.version, it has no vendored CHANGELOG digest to carry in the release commit, and
# nothing fans out on release (see the closing note in phase 2).
#
# WHY TWO PHASES — the tag is created LAST, never before the merge:
#
# Committing AND tagging in one go leaves a local vX.Y.Z sitting on a commit that is not
# yet on main. That window is not safe, and no amount of `--no-follow-tags` discipline
# closes it: the flag governs YOUR push, while the tag lives in SHARED .git state any
# other process can push. In Core it happened — a concurrent session with
# `push.followTags` set carried a release tag to origin and fired the release path against
# an unmerged commit, and the version number had to be retired.
#
# So the invariant is structural rather than procedural:
#
#     a vX.Y.Z tag only ever exists on a commit that is already on origin/main.
#
# Usage:
#   ./scripts/tag-release.sh              # phase 1: commit nvim.version + CHANGELOG
#   ./scripts/tag-release.sh --publish    # phase 2: tag origin/main + push (AFTER merge)
#   make tag                              # phase 1, via the Makefile façade
#   make publish                          # phase 2
#
# Env:
#   TAG_SKIP_AUDIT=1   skip the green-tree gate (escape hatch for a tree you just audited)
# ──────────────────────────────────────────────────────────────────────────────
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HERE" || exit 1

# shellcheck source=scripts/lib/common.sh
source "${BASH_SOURCE[0]%/*}/lib/common.sh"

VERFILE=nvim.version
CHANGELOG=CHANGELOG.md
PUBLISH=0

usage() {
  cat <<'EOF'
usage: tag-release.sh [--publish]

  (no flag)     PHASE 1 — prove the tree green and commit nvim.version + CHANGELOG.md.
                Creates NO tag: until the commit is on origin/main there must be no
                vX.Y.Z for a stray push to carry to the remote. Prints the land recipe.

  --publish     PHASE 2 — run AFTER the release PR merges. Proves origin/main really
                carries this nvim.version, then creates the annotated vX.Y.Z and moves
                the vN alias AT THE RELEASE COMMIT, and pushes both atomically.
EOF
}

while (($#)); do
  case "$1" in
  --publish) PUBLISH=1 ;;
  -h | --help) usage; exit 0 ;;
  *)
    printf 'tag-release.sh: unexpected argument: %s\n' "$1" >&2
    usage >&2
    exit 2
    ;;
  esac
  shift
done

have git || { printf 'tag-release.sh: git not found\n' >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  printf 'tag-release.sh: not inside a git checkout\n' >&2
  exit 1
}
[[ -r "$VERFILE" && -r "$CHANGELOG" ]] || {
  printf 'tag-release.sh: %s and %s must both be readable\n' "$VERFILE" "$CHANGELOG" >&2
  exit 1
}

VERSION="$(tr -d '[:space:]' <"$VERFILE")"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "tag-release.sh: $VERFILE is '$VERSION' — must be a clean X.Y.Z"
  exit 2
fi
TAG="v$VERSION"
MAJOR="v${VERSION%%.*}"

# BREAKING on a non-major is refused with no escape hatch, because publish FORCE-MOVES the
# $MAJOR alias: shipping a breaking change under the alias every consumer pins to would
# break them silently, at a moment nobody chose.
CHANGELOG_SECTION="$(awk -v tag="$TAG" '
  index($0, "## [" tag "]") == 1 { f = 1; next }
  f && index($0, "## [") == 1 { exit }
  f { print }
' "$CHANGELOG")"
if [[ "$VERSION" != *.0.0 ]] && grep -qE '^- \*\*BREAKING|BREAKING CHANGE:' <<<"$CHANGELOG_SECTION"; then
  fail "tag-release.sh: $TAG's CHANGELOG section declares a BREAKING change on a non-major version"
  fail "publish force-moves $MAJOR — cut this as a major, or the break reaches every consumer pinned to the alias"
  exit 1
fi

# ── PHASE 2 — publish the tags. Runs AFTER the release PR merges. ─────────────
if ((PUBLISH)); then
  hdr "publish $TAG (tags origin/main)"

  # --force because $MAJOR is a MOVING alias: without it a stale local vN silently wins
  # and every check below reasons about the wrong commit. stderr is not swallowed — a
  # fetch that failed for a reason worth reading must not look like a missing tag.
  if ! fetch_err="$(git fetch --force --tags origin 2>&1 >/dev/null)"; then
    fail "tag-release.sh: git fetch failed — refusing to publish against stale refs"
    [[ -n "$fetch_err" ]] && printf '%s\n' "$fetch_err" >&2
    exit 1
  fi
  git rev-parse -q --verify origin/main >/dev/null || {
    fail "tag-release.sh: no origin/main to tag"
    exit 1
  }

  # THE guard, and it must identify the RELEASE COMMIT — not merely today's tip.
  # nvim.version does not change again until the NEXT release, so "origin/main carries
  # $VERSION" stays true for every commit that lands afterwards. Tagging the tip would
  # sweep changes still under [Unreleased] into the release, and they would ship
  # undescribed because the Release body comes from the [vX.Y.Z] section.
  RELEASE_SHA=''
  while IFS= read -r _sha; do
    [[ -n "$_sha" ]] || continue
    if [[ "$(git show "$_sha:$VERFILE" 2>/dev/null | tr -d '[:space:]')" == "$VERSION" ]]; then
      RELEASE_SHA="$_sha"
    else
      # First commit going back that does NOT carry $VERSION — everything older predates
      # the bump, so the last match we saw is the commit that introduced it.
      break
    fi
  done < <(git rev-list origin/main -- "$VERFILE")

  if [[ -z "$RELEASE_SHA" ]]; then
    fail "tag-release.sh: no commit on origin/main sets $VERFILE to '$VERSION' as its newest change"
    fail "either the release PR has not merged, or main has already moved on to a newer release"
    exit 1
  fi
  pass "release commit on origin/main: $(git rev-parse --short "$RELEASE_SHA") (sets $VERFILE to $VERSION)"

  if [[ "$RELEASE_SHA" != "$(git rev-parse origin/main)" ]]; then
    skip "origin/main has advanced $(git rev-list --count "$RELEASE_SHA..origin/main") commit(s) since the release — tagging the release commit, not the tip"
  fi

  # The Release body comes from this COMMIT's [vX.Y.Z] section, so validate it there
  # rather than in the working tree. Captured, NOT piped into `grep -q`: under
  # `set -o pipefail` that pipeline reports failure on a successful match, because grep -q
  # exits on the first hit and git show then dies of SIGPIPE part-way through.
  RELEASE_CHANGELOG="$(git show "$RELEASE_SHA:$CHANGELOG" 2>/dev/null)"
  if ! grep -qE "^## +\[v?${VERSION//./\\.}\]" <<<"$RELEASE_CHANGELOG"; then
    fail "tag-release.sh: the release commit's $CHANGELOG has no '## [$TAG]' heading"
    fail "release.yml builds the Release body from that section — refusing to publish a tag it would fail on"
    exit 1
  fi
  # A heading is not enough: release.yml also rejects an EMPTY section, and publishing
  # would push the immutable tag and only then fail — burning the version for a reason
  # that was knowable up front. Same awk release.yml uses, so the two cannot disagree
  # about what "empty" means.
  RELEASE_BODY="$(awk -v tag="$TAG" '
    $0 ~ "^## +\\[" tag "\\]" { f = 1; next }
    f && /^## +\[/ { exit }
    f && NF { p = 1 }
    f && p { buf[++n] = $0 }
    END { while (n > 0 && buf[n] ~ /^[[:space:]]*$/) n--; for (i = 1; i <= n; i++) print buf[i] }
  ' <<<"$RELEASE_CHANGELOG")"
  if [[ -z "${RELEASE_BODY//[[:space:]]/}" ]]; then
    fail "tag-release.sh: the [$TAG] section in $CHANGELOG is EMPTY — write the notes first"
    exit 1
  fi
  pass "the release commit's $CHANGELOG carries a non-empty [$TAG] section"

  # Never clobber a published release.
  if git ls-remote --tags --exit-code origin "refs/tags/$TAG" >/dev/null 2>&1; then
    fail "tag-release.sh: $TAG already exists on origin — a published release tag is immutable"
    exit 1
  fi

  # Capture the remote alias NOW, well before the push: it is the LEASE for the force
  # below, and reading it here rather than immediately before the push widens the window
  # it protects.
  REMOTE_MAJOR="$(git ls-remote origin "refs/tags/$MAJOR" 2>/dev/null | awk 'NR==1{print $1}')"

  # The lease alone is not enough. It covers changes AFTER this read — but a newer
  # publisher that finished BEFORE it makes us read THEIR alias as our expected value, and
  # the leased push then moves $MAJOR backward with the lease perfectly satisfied. So
  # require the move to be FORWARD as well.
  if [[ -n "$REMOTE_MAJOR" ]]; then
    REMOTE_MAJOR_COMMIT="$(git rev-parse -q --verify "$REMOTE_MAJOR^{commit}" 2>/dev/null || echo '')"
    if [[ -z "$REMOTE_MAJOR_COMMIT" ]]; then
      fail "tag-release.sh: cannot resolve origin's $MAJOR ($REMOTE_MAJOR) locally — refusing to move an alias blind"
      exit 1
    fi
    if [[ "$REMOTE_MAJOR_COMMIT" != "$RELEASE_SHA" ]] &&
      ! git merge-base --is-ancestor "$REMOTE_MAJOR_COMMIT" "$RELEASE_SHA" 2>/dev/null; then
      fail "tag-release.sh: origin's $MAJOR points at $(git rev-parse --short "$REMOTE_MAJOR_COMMIT"), which is not an ancestor of this release"
      fail "moving it would roll $MAJOR backward for every consumer pinned to it — refusing"
      exit 1
    fi
  fi

  # ANNOTATED (-fa … -m), not a bare `git tag -f`: under `tag.gpgsign = true` git makes any
  # tag signed — therefore annotated — so the message-less form aborts with "no tag
  # message?" and the publish dies here. That is invisible on a box with signing off,
  # which is exactly how it survived in Core until an operator with signing on cut a
  # release. Annotating is the better artefact for a force-moved pointer anyway: it
  # records who moved the alias and when, which a lightweight ref cannot.
  if ! git tag -fa "$TAG" "$RELEASE_SHA" -m "$TAG"; then
    fail "tag-release.sh: could not create $TAG at the release commit ($RELEASE_SHA)"
    exit 1
  fi
  pass "tagged $TAG at $(git rev-parse --short "$RELEASE_SHA")"
  if ! git tag -fa "$MAJOR" "$RELEASE_SHA" -m "$MAJOR" >/dev/null; then
    fail "tag-release.sh: could not move major tag $MAJOR"
    exit 1
  fi
  pass "moved major tag $MAJOR → $(git rev-parse --short "$RELEASE_SHA")"

  # ONE atomic push, not two. Pushed separately these can half-land: vX.Y.Z lands, vN does
  # not, release.yml fires while the alias consumers pin to is stale — and re-running
  # --publish then refuses, because the immutable tag now exists. The leading + forces
  # ONLY the alias, so a non-fast-forward on the immutable tag is still rejected.
  push_args=(--atomic origin "refs/tags/$TAG")
  if [[ -n "$REMOTE_MAJOR" ]]; then
    push_args+=(--force-with-lease="refs/tags/$MAJOR:$REMOTE_MAJOR" "+refs/tags/$MAJOR")
  else
    push_args+=("refs/tags/$MAJOR")
  fi
  if ! git push "${push_args[@]}"; then
    fail "tag-release.sh: atomic tag push failed — nothing was published"
    fail "if $MAJOR moved under you, another publisher won the race: re-fetch and re-run 'make publish'"
    exit 1
  fi
  pass "pushed $TAG and $MAJOR atomically"

  printf '\n%s──────── %s published ────────%s\n' "$c_blu" "$TAG" "$c_rst"
  cat <<EOF
  release.yml publishes the GitHub Release from the CHANGELOG section.

  NOTHING FANS OUT, and that is the design. dotfiles-core bumps its nvim.lock WITH ITS
  NEXT RELEASE, never on every one of ours (NVIM-SPLIT-PROPOSAL.md §7(3)) — adopting each
  editor release as it lands would reimport, through the lock, exactly the churn the split
  removed. Core's freshness job reports the lag so "at Core's pace" cannot decay into
  "never".

  verify:  gh run list --workflow release --limit 1
EOF
  exit 0
fi

# ── PHASE 1 — commit the release. NO TAG IS CREATED HERE. ────────────────────
hdr "commit $TAG (from $VERFILE)"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  fail "tag-release.sh: tag $TAG already exists — bump $VERFILE or delete the tag to re-cut"
  exit 1
fi

if ! grep -qE "^## +\[v?${VERSION//./\\.}\]" "$CHANGELOG"; then
  fail "tag-release.sh: no '## [$TAG]' heading in $CHANGELOG — promote [Unreleased] first"
  exit 1
fi
if [[ -z "${CHANGELOG_SECTION//[[:space:]]/}" ]]; then
  fail "tag-release.sh: the [$TAG] section in $CHANGELOG is EMPTY — write the notes first"
  exit 1
fi

if [[ "${TAG_SKIP_AUDIT:-0}" == 1 ]]; then
  skip "audit (TAG_SKIP_AUDIT=1)"
else
  hdr "audit (tag must be green)"
  if ./scripts/audit-nvim.sh --quiet; then
    pass "audit green"
  else
    fail "audit FAILED — fix before tagging (or TAG_SKIP_AUDIT=1 to override a just-audited tree)"
    exit 1
  fi
fi

# The explicit pathspec commits ONLY these two files, so unrelated staged work is never
# swept into the release commit. Re-running after the commit landed is a no-op, not an error.
if git diff --quiet HEAD -- "$VERFILE" "$CHANGELOG"; then
  pass "release commit already present ($VERFILE/$CHANGELOG match HEAD)"
elif git commit -q -m "release $TAG" -- "$VERFILE" "$CHANGELOG"; then
  pass "committed release $TAG"
else
  fail "tag-release.sh: commit failed"
  exit 1
fi

printf '\n%s──────── %s committed (no tag yet, by design) ────────%s\n' "$c_blu" "$TAG" "$c_rst"
cat <<EOF
  review:  git show HEAD

  NO TAG EXISTS YET, and that is the point — see this script's header.

  1. land the commit:
       git push origin HEAD:release/$TAG
       gh pr create --base main --head release/$TAG --title "release $TAG"
  2. publish the tags AFTER the PR merges:
       make publish          # refuses unless origin/main really carries $VERFILE $VERSION
EOF
