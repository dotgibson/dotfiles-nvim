# dotfiles-nvim

The Neovim configuration for the [dotgibson](https://github.com/dotgibson) dotfiles system —
authored here, vendored into [`dotfiles-core`](https://github.com/dotgibson/dotfiles-core)
and from there into every OS repo's `core/nvim`.

lazy.nvim, 61 pinned plugins, 28 LSP servers, Tokyo Night. Neovim **≥ 0.12** (nvim-treesitter
is pinned to `main`).

## Why this is its own repo

It lived in `dotfiles-core` until `NVIM-SPLIT-PROPOSAL.md` measured what that cost: **44% of
Core releases carried an editor change**, a third of the nvim commits were the freshness bot
moving plugin pins, and each such release fanned nine sync PRs out to repos whose shells had
not changed. The editor's cadence was imposed on the shell's.

The other half of the argument is the one that matters more. Core's gate lints the Lua and
walks the module graph — but nothing there has ever **started** the editor with the plugin
set a host would actually get. A pin bump is the change this tree receives most, and it
shipped through a gate that could not see the thing it breaks.

So `make audit` here installs the committed pins with `:Lazy! restore`, starts nvim for real
and runs `:checkhealth gerrrt`. That check is the reason the tree was extracted rather than
frozen.

## Layout

| Path | |
| --- | --- |
| `nvim/` | the editor tree — `init.lua`, `lazy-lock.json`, `lua/gerrrt/{config,plugins,servers,utils}` |
| `theme/palette.toml` | vendored from `dotfiles-core`; `theme/.core-ref` records from where |
| `scripts/audit-nvim.sh` + `scripts/audit/` | the gate: the dispatcher and its numbered fragments |
| `scripts/test-nvim.sh` + `scripts/test/` | the behavioral suite, same shape |
| `scripts/update-nvim-plugins.sh` | the one thing allowed to move `lazy-lock.json` |
| `scripts/nvim-reachability.sh` | the module-graph backstop |
| `scripts/tag-release.sh` | two-phase release: commit, then tag `origin/main` |

`nvim/` keeps its path deliberately. Core vendors it to `nvim/`, and `dotfiles-Windows`
mirrors the same directory with `nvim-sync.ps1` — so re-pointing either consumer at this
repo is a change of URL, not of shape.

## Working on it

```bash
make                  # the discoverable target list
make audit            # the one gate — luacheck, reachability, theme, startup, checkhealth
make audit-offline    # the same without the plugin install (no network)
make test             # only the behavioral suite
make check-pins       # are the plugin pins behind upstream? changes nothing
```

`make audit` needs `nvim`, `git`, `luacheck` (against Lua 5.4 — luacheck 1.2.0 will not load
under 5.5) and the network. A missing tool is a **skip**, never a silent pass; CI runs
`--strict`, where a tool-absent skip is red, because on a runner every tool is installed on
purpose and a skip there means an install step quietly did not happen.

## How it reaches a machine

```text
dotfiles-nvim  ──vendored──▶  dotfiles-core/nvim/  ──vendored──▶  <os-repo>/core/nvim
                                                                        │
                                                              bootstrap symlinks
                                                                        ▼
                                                                ~/.config/nvim
```

`dotfiles-Windows` vendors no `core/` and consumes this repo directly.

Core adopts a release of this repo **with its next release**, never on every one of ours
(`NVIM-SPLIT-PROPOSAL.md` §7(3)): adopting each editor release as it lands would reimport,
through the lock, exactly the churn the split removed. Nothing here fans anything out.

## Releasing

```bash
make tag        # phase 1: prove green, commit nvim.version + CHANGELOG — creates NO tag
# push the branch, open the PR, merge it
make publish    # phase 2: tag origin/main, push vX.Y.Z + the moving vN alias, atomically
```

The tag is created last on purpose. A `vX.Y.Z` sitting on an unmerged commit lives in shared
`.git` state that any concurrent process can push; in Core that happened, fired the release
path against an unmerged commit, and burned a version number.

## Licence

[MIT](LICENSE).
