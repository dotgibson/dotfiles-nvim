# Contributing to dotfiles-nvim

## The one gate

`scripts/audit-nvim.sh` is the single definition of "the editor is healthy". CI and
`make audit` call the same script, so a green run here is a green run there.

```bash
make audit          # the full gate
make audit-offline  # everything except the plugin install (no network)
make test           # only the behavioral suite
```

`set -e` is deliberately absent from both dispatchers: one failing section must not abort the
rest, or the first red hides every other finding and the gate takes N runs to clear.

## Adding a section

Add a file. `scripts/audit/NN-name.sh` and `scripts/test/NN-name.sh` are globbed in `NN`
order and **sourced** into the dispatcher's shell — there is no registry to update. Three
rules, all of them asserted by `scripts/audit/05-shape.sh` rather than assumed:

- **The `NN-` prefix is load-bearing.** Without it the glob skips the file in silence while
  the run still reports `audit OK`. That failure looks exactly like success.
- **Fragments are sourced libraries**: mode `100644`, no shebang. A shebang is a claim the
  file can run on its own; it cannot — it would start with no counters, no `$HERE` and no
  helpers.
- **No fragment installs an EXIT trap.** `trap … EXIT` *replaces* rather than appends, so a
  second handler silently takes the dispatcher's `$SANDBOX` cleanup with it — and in the
  startup section that sandbox holds sixty git clones.

A fragment may assume: the `PASS`/`SKIP`/`FAIL` counters, `$HERE` (already `cd`'d to),
`$SANDBOX`, and `have`/`pass`/`skip`/`skip_env`/`skip_note`/`fail`/`fail_detail`/`hdr` from
`scripts/lib/common.sh`. Namespace your locals with a per-fragment prefix.

## The three kinds of not-running

A gate that skipped itself green is the failure mode this repo was extracted to stop
shipping, so say which kind you mean:

| | |
| --- | --- |
| `skip` | a tool is absent — a real coverage gap. `--strict` reds on it, and CI runs `--strict`. |
| `skip_env` | the run could not cover it *here* (no network for a plugin install). Not a missing tool. |
| `skip_note` | news, not a gap. Nothing reds on it, not even `--strict`. |

The class is recorded structurally, by index, never by matching the message text — so making
the wording honest can never silently change what the gate does.

## Moving the plugin pins

`scripts/update-nvim-plugins.sh` is the only thing that writes `nvim/lazy-lock.json`. The
weekly `freshness.yml` runs it and opens a PR; that PR's CI installs the new pins and starts
the editor, which is the whole point of them landing here. Do not hand-edit the lockfile.

## Lua style

`luacheck` is the enforced linter, run from inside `nvim/` — it searches *upward* for
`.luacheckrc`, so running it from the repo root silently lints with defaults.

`stylua` is **advisory** and says so in `scripts/audit/10-lua.sh` §1b. It stays advisory
until [dotfiles-core#1123](https://github.com/dotgibson/dotfiles-core/issues/1123)'s
byte-identical first sync has landed: reformatting the tree now would break that
non-negotiable, and `NVIM-SPLIT-PROPOSAL.md` §6 is explicit that the split moves the tree and
does not edit it.

## Commits and releases

[Conventional Commits](https://www.conventionalcommits.org/) — `type(scope): summary`. A
user-visible change lands in `CHANGELOG.md` under `[Unreleased]` in the same commit;
`scripts/tag-release.sh` refuses to cut a version whose section is empty, and
`release.yml` refuses to publish one.

`RELEASE`: `make tag`, land the PR, then `make publish`. The tag is created last — see the
README for why.

## Known gaps

- `pr-link-check` is not ported from Core. If PR volume here ever stops being "one numbered
  step of the split at a time", port it.
- The health module still announces itself as `dotfiles-core:`. See `CHANGELOG.md`'s
  *Known gaps* for why that has to wait.
