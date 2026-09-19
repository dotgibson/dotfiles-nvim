<!-- Back to top link -->
<a id="readme-top"></a>

<!-- Project Shields -->
<div align="center"><nobr>

[![dotgibson][dotgibson-shield]][dotgibson-url]<!--
-->[![CI][ci-shield]][ci-url]<!--
-->![Last Commit][lastcommit-shield]<!--
-->[![Contributors][contributors-shield]][contributors-url]<!--
-->[![Forks][forks-shield]][forks-url]<!--
-->[![Stargazers][stars-shield]][stars-url]<!--
-->[![Issues][issues-shield]][issues-url]<!--
-->[![MIT License][license-shield]][license-url]

</nobr></div>

# dotfiles-nvim

The Neovim configuration for the [dotgibson](https://github.com/dotgibson) dotfiles system —
authored here, vendored into [`dotfiles-core`](https://github.com/dotgibson/dotfiles-core)
and from there into every OS repo's `core/nvim`.

lazy.nvim, 61 pinned plugins, 28 LSP servers, Tokyo Night. Neovim **≥ 0.12** (nvim-treesitter
is pinned to `main`).

## Built with

- [![Neovim][neovim-shield]][neovim-url]
- [![Lua][lua-shield]][lua-url]
- [![lazy.nvim][lazy-shield]][lazy-url]

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

<!-- Markdown Links & Images -->
[dotgibson-shield]: https://img.shields.io/github/v/release/dotgibson/dotfiles-core?style=plastic&label=dotgibson&labelColor=181717&logo=data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAF1klEQVR4nLSWbUxT7RnHr9PT09MXSltaoC9QXkqR16Iwhb0Iw8VYYE7jPri5aBaZzpmFZbpolpn4QeMyM%2BM%2B7MVt0Q9LNJIlxCzqxGWS6aKAig51vBQKIi3QltpCS0%2Fbc879pD1N3%2Bnz4fG5Pl2977v%2F331d131f5%2BZrddWQZAgAgy9uCRlefICzT6GeIsP%2FXF15kahmu9JglGmLRQoRQdIQWgu77BuWGe%2Fo%2BOqym8odApaWomTT1%2Bl2HqirahaTuJ9kQMggkgYhDRGfRiQDZBi9fuf52%2BD7l1b3ZhRcmq%2FMnBHmibuO7fvWoTalVoDjQRwL8RGgEOtzB0MbtBDnkRjGR0AgTK%2BQfNukr1LKXlhXKZpJSxTKGoFSq9vf16tQ8%2FiEh094Vu0L449mLGMup20DRWuFYVCiFm%2BvU36nTbOlMB%2BnCDxIOBzhvv6nFpc3TS0dUKDRHzh1Jk9O8wlPYN326Oa%2FJobnN8shAOxqKjrdXa8WSnGKWPewR%2FuHLG5P8oKUFJHi%2FH19F6UKEQ%2BnbJap27%2B%2BtWR15VAHgLkV%2F%2F0xW6OuQCfNE4PgmyX6f0xZKYbJDuj43lmtoYqHU%2FaZdwNXr4eoUG51zqgw%2B%2FCtrbm0UCeRynBhqVj2YC4RNC%2FuqStbKkydAODzeO7%2B6QYTpnOIYgB729R729RY9DAGafb0wDOHLwAA5vKK1mJNFoCpsxeLLn%2Fy91uU359719%2FfVXL%2BSM35IzU9rcXciCcQujz0imOfbGhOB0jkGo2hFQBW7Quzr0Zzq6vyBT%2FuKY%2BHErfBmQWLK1Lhr6l1OkleCqC0poPb%2FuTwv3OrA8DPDhgkokgLmLX77o86kqcGJmaj5xjr1JWlAAr1Js75MDEGAAI%2B1mvWX%2F1JY29XmYDPS5ZoNsrM24si1xSh3%2FRbGBYlz%2F73g41ztqliqYv1onyVHgDocMjjXASAKycavlqnZBHa2ajcasjv%2B8MbAPhRV9nI5MezB41crIPPHWOW9Gtl9XhDDCMCokIqSwGQ4shvyucFhEQCnqlSdm9k%2BdKt6XM%2FqO7aof7t8YbIIW5SHdpVIhUTAOAP0L8bmM3MHgJwByidQCgnhSmAqOEYnQ8AgRBr%2FuUzKsgggIs3pyVCfkeTCgAmFtaNOgm39C%2F3511r2W8JYvIAJbIaAwQ3vKAEoVgRaTQIBYKxqxgMs6euvdUXiQDgeHd5rV7K1fb2kC2rOgaYghQBMJ5grI3HUGuuhQiNIOWq8sy%2FLTgCKplgT0ZtCyprWw7%2FvKCyNr6yQqYg8cim59a9KQDnwv84R1%2F99UwAzsMya4vxeOYLN7YePGG%2BcAPjxXS%2BoavknFfOlRTAh8nHKNqLa1v2ZwK6dxQZtHk5ahu3%2FcYmLsoh%2B%2FsUgN%2BztDQzEvkYFBurGnan%2FS1%2B1P98L1FbxLIPzh193X%2FtwbmjiGUBYHd5nVFRCABPlxdtfh%2B3LHGKxof%2Bqo90C6yj58yi9Tm1kWjr94ZXsGhTuDuynAx2z0245yY4X06Kf9HWFd0N%2BuPbsUR64%2B3a57Erig2qIoOIlJSUNE69GWTZRFufXvRNL%2Fo2ywyJE1fMP6xWqHBEP5yfvP7%2FbAAAsFufG01mkVCqkGvLyrbNTD2mw9kfDckmE0oudx9rUZfhiF5Zd%2F%2F00QDF0NkBTJhanB3e0riHJIRKhXarqWfdu%2Bx0WnOot1ftuNR90lhQzEO0L7B2YvCm3b%2BWNI%2ByffSLq757%2BPcquYaIvBtgdcXycuzO9MzTFdccd9IwDNMVlDaXbzPXtxsVhQRDEQzl8i6d%2Buf12Y%2BONDVMo6vOfHWJxHLz3l811u8WAEZABCNAAHSI8n8k2HABKRJjLJ8JECxFMAE%2BHXhiGb7yn35vcCNDKVsEcSuv%2BEpn%2B7Etla0CwAQIOBLBhrkt85kAnwm8mX95e%2FTOa9vUZiIxQI43r0Kura9uN5SYNMoyuVDGZ2nK73C65iy28Rezo44152bSKYAvz3ifVA1lDn0WAAD%2F%2F%2FWvXexgMwqgAAAAAElFTkSuQmCC
[dotgibson-url]: https://github.com/dotgibson/dotfiles-core/releases/latest
[ci-shield]: https://img.shields.io/github/check-runs/dotgibson/dotfiles-nvim/main?style=plastic&logo=githubactions&logoColor=white&label=CI
[ci-url]: https://github.com/dotgibson/dotfiles-nvim/actions/workflows/ci.yml
[lastcommit-shield]: https://img.shields.io/github/last-commit/dotgibson/dotfiles-nvim?branch=main&style=plastic&logo=git&logoColor=white
[contributors-shield]: https://img.shields.io/github/contributors/dotgibson/dotfiles-nvim.svg?style=plastic&logo=github
[contributors-url]: https://github.com/dotgibson/dotfiles-nvim/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/dotgibson/dotfiles-nvim.svg?style=plastic&logo=github
[forks-url]: https://github.com/dotgibson/dotfiles-nvim/network/members
[stars-shield]: https://img.shields.io/github/stars/dotgibson/dotfiles-nvim.svg?style=plastic&logo=github
[stars-url]: https://github.com/dotgibson/dotfiles-nvim/stargazers
[issues-shield]: https://img.shields.io/github/issues/dotgibson/dotfiles-nvim?style=plastic&logo=github
[issues-url]: https://github.com/dotgibson/dotfiles-nvim/issues
[license-shield]: https://img.shields.io/github/license/dotgibson/dotfiles-nvim.svg?style=plastic
[license-url]: https://github.com/dotgibson/dotfiles-nvim/blob/main/LICENSE
[neovim-shield]: https://img.shields.io/github/v/release/neovim/neovim?style=plastic&logo=neovim&logoColor=white&label=Neovim&labelColor=57A143&color=3D59A1
[neovim-url]: https://github.com/neovim/neovim
[lua-shield]: https://img.shields.io/github/v/tag/lua/lua?sort=semver&style=plastic&logo=lua&logoColor=white&label=Lua&color=000080
[lua-url]: https://github.com/lua/lua
[lazy-shield]: https://img.shields.io/github/v/release/folke/lazy.nvim?style=plastic&logo=gnometerminal&logoColor=24283B&label=lazy.nvim&labelColor=BB9AF7&color=3D59A1
[lazy-url]: https://github.com/folke/lazy.nvim
