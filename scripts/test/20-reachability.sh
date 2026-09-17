# scripts/test/20-reachability.sh
# nvim orphan backstop
#
# A SOURCED FRAGMENT of scripts/test-nvim.sh — not a standalone script. It runs in the
# dispatcher's shell and uses its state: PASS/SKIP/FAIL, $SANDBOX, $HERE, and the
# pass/skip/fail/hdr/have helpers from scripts/lib/common.sh. See the header of
# scripts/test-nvim.sh for the contract.

# Fragments embed shell code as single-quoted literals on purpose: the `$…` inside them
# must be expanded by the CHILD, not by this bash parent. SC2016 is therefore a
# false positive file-wide, exactly as it is in the dispatcher.
# shellcheck disable=SC2016

# ── nvim orphan backstop (scripts/nvim-reachability.sh) ───────────────────────
# The editor tree ships whole — nothing enumerates its modules file by file, so no
# manifest check can see an orphan. scripts/nvim-reachability.sh is the backstop, and
# this proves the backstop actually catches what it claims to, rather than merely
# existing — the same lesson the atuin-guard verification exists to enforce. Hermetic: a
# synthetic git repo with a miniature gerrrt tree, so it asserts the LOGIC, never this
# repo's tree.
#
# Every negative fixture asserts BOTH the finding text and exit status 1, because the
# script documents `1 = findings` as its CLI contract and audit-nvim.sh keys off the
# output — matching one without the other would leave half the contract untested.
if have git; then
  hdr "nvim orphan backstop (nvim-reachability.sh)"
  NVR="$HERE/scripts/nvim-reachability.sh"
  NREPO="$SANDBOX/nvimrepo"

  _nvr_fresh() { # build a minimal, fully REACHABLE gerrrt tree
    rm -rf "$NREPO"
    mkdir -p "$NREPO/nvim/lua/gerrrt/config" "$NREPO/nvim/lua/gerrrt/plugins" \
             "$NREPO/nvim/lua/gerrrt/servers" "$NREPO/nvim/lua/gerrrt/utils"
    git -C "$NREPO" init -q
    git -C "$NREPO" config user.email t@example.com
    git -C "$NREPO" config user.name tester
    printf 'require("gerrrt")\n'                          >"$NREPO/nvim/init.lua"
    printf 'require("gerrrt.config")\n'                   >"$NREPO/nvim/lua/gerrrt/init.lua"
    printf 'local M={} function M.check() end return M\n' >"$NREPO/nvim/lua/gerrrt/health.lua"
    printf 'require("gerrrt.config.lazy")\n'              >"$NREPO/nvim/lua/gerrrt/config/init.lua"
    # one explicit require, lazy's directory import, and the dynamic servers arm
    printf 'require("gerrrt.utils.term")\nrequire("lazy").setup({ { import = "gerrrt.plugins" } })\nrequire("gerrrt.servers")\n' \
                                                          >"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
    printf 'return {}\n'                                  >"$NREPO/nvim/lua/gerrrt/utils/term.lua"
    printf 'return {}\n'                                  >"$NREPO/nvim/lua/gerrrt/plugins/anything.lua"
    printf 'local servers = {\n\t"lua_ls",\n}\nfor _, n in ipairs(servers) do pcall(require, "gerrrt.servers." .. n) end\n' \
                                                          >"$NREPO/nvim/lua/gerrrt/servers/init.lua"
    printf 'return {}\n'                                  >"$NREPO/nvim/lua/gerrrt/servers/lua_ls.lua"
    git -C "$NREPO" add -A >/dev/null 2>&1
  }
  # Capture output and status TOGETHER. Note the deliberate absence of a pipeline here:
  # `"$NVR" … | grep -q` would return the SCRIPT's status under `set -o pipefail` (1
  # whenever findings exist), silently inverting every assertion below into the wrong
  # branch — which is exactly what the first version of this section did.
  _nvr_catches() { # <grep-pattern> <label>
    git -C "$NREPO" add -A >/dev/null 2>&1
    local out rc
    out="$(env -u CORE_JSON "$NVR" --root "$NREPO" 2>&1)"
    rc=$?
    if grep -q "$1" <<<"$out" && [[ $rc -eq 1 ]]; then
      pass "nvim-reachability: $2"
    else
      fail "nvim-reachability: $2 (rc=$rc, output=${out:-<empty>})"
    fi
  }
  _nvr_clean() { # <label>
    git -C "$NREPO" add -A >/dev/null 2>&1
    local out rc
    out="$(env -u CORE_JSON "$NVR" --root "$NREPO" 2>&1)"
    rc=$?
    if [[ -z "$out" && $rc -eq 0 ]]; then
      pass "nvim-reachability: $1"
    else
      fail "nvim-reachability: $1 (rc=$rc, output=${out:-<empty>})"
    fi
  }

  _nvr_fresh
  _nvr_clean "a fully reachable tree is clean"

  # the gap this whole section exists to close: a utils/ module nothing requires
  _nvr_fresh; printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/dead.lua"
  _nvr_catches 'gerrrt\.utils\.dead' "catches an orphaned utils/ module"

  # a stray top-level lua/gerrrt/*.lua (health.lua is the only legitimate one)
  _nvr_fresh; printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/junk.lua"
  _nvr_catches 'gerrrt\.junk' "catches a stray top-level module"

  # THE reason this is a graph walk and not a mention-scan: two dead modules that
  # require each other have a non-zero indegree but are reachable from nothing.
  _nvr_fresh
  printf 'require("gerrrt.utils.beta")\nreturn {}\n' >"$NREPO/nvim/lua/gerrrt/utils/alpha.lua"
  printf 'require("gerrrt.utils.alpha")\nreturn {}\n' >"$NREPO/nvim/lua/gerrrt/utils/beta.lua"
  _nvr_catches 'gerrrt\.utils\.alpha' "catches a disconnected require cycle"

  # a module named only in a COMMENT is not reached — comments are stripped before edges
  _nvr_fresh
  printf -- '-- require("gerrrt.utils.ghost")\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/ghost.lua"
  _nvr_catches 'gerrrt\.utils\.ghost' "a commented-out require does not count as an edge"

  # health.lua must NOT be flagged — Neovim discovers lua/**/health.lua by runtimepath
  _nvr_fresh; _nvr_clean "exempts health.lua (:checkhealth root)"

  # plugins/ must NOT be flagged — lazy imports the directory wholesale
  _nvr_fresh; printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/plugins/another.lua"
  _nvr_clean "exempts plugins/ (lazy imports the dir)"

  # an LSP module absent from the registry is dead config
  _nvr_fresh; printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/servers/pyright.lua"
  _nvr_catches 'pyright.*registry' "catches an unlisted LSP module"

  # the reverse — a registry name with no file is a RUNTIME load error
  _nvr_fresh
  printf 'local servers = {\n\t"lua_ls",\n\t"ghostls",\n}\n' >"$NREPO/nvim/lua/gerrrt/servers/init.lua"
  _nvr_catches 'ghostls' "catches a registry entry with no module file"

  # an unparseable registry must FAIL CLOSED — not emit N bogus findings, not go quiet
  _nvr_fresh
  printf 'local servers = vim.tbl_flatten({\n\t"lua_ls",\n})\n' >"$NREPO/nvim/lua/gerrrt/servers/init.lua"
  _nvr_catches 'could not parse' "fails closed on an unparseable registry"

  # …and so must a MISSING one: skipping it silently would disable the whole servers arm
  _nvr_fresh; rm -f "$NREPO/nvim/lua/gerrrt/servers/init.lua"
  _nvr_catches 'missing.*servers/init\.lua' "fails closed on a missing registry"

  # a `package.loaded["gerrrt.x"]` PEEK is not a load — health.lua uses exactly this to
  # inspect the registry without forcing it to load, and counting it as an edge would let
  # the whole servers/ arm look reachable from the health root with no real require left.
  _nvr_fresh
  printf 'local _ = package.loaded["gerrrt.utils.peeked"]\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/peeked.lua"
  _nvr_catches 'gerrrt\.utils\.peeked' "a package.loaded peek is not an edge"

  # a require inside a MULTILINE --[[ ]] block is still a comment; a line-only stripper
  # leaves the block interior searchable and would forge the edge
  _nvr_fresh
  printf -- '--[[\nrequire("gerrrt.utils.blockghost")\n]]\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/blockghost.lua"
  _nvr_catches 'gerrrt\.utils\.blockghost' "a multiline block comment is not an edge"

  # lua long comments come in levels — --[=[ … ]=], --[==[ … ]==] — and the closing
  # delimiter must match the opener's `=` count, so it cannot be hardcoded
  _nvr_fresh
  printf -- '--[=[\nrequire("gerrrt.utils.levelghost")\n]=]\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/levelghost.lua"
  _nvr_catches 'gerrrt\.utils\.levelghost' "a --[=[ level long comment is not an edge"

  # require() of a DIRECTORY is a runtime error, not a lazy import: it must be reported,
  # and it must NOT mark the directory's children reachable
  _nvr_fresh
  printf 'require("gerrrt.utils")\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/onlychild.lua"
  _nvr_catches 'dangling require' "reports require() of a module that does not exist"
  _nvr_catches 'gerrrt\.utils\.onlychild' "require() of a directory does not expand children"

  # a lazy import naming nothing at all is dead config, not a silent no-op
  _nvr_fresh
  printf 'require("lazy").setup({ { import = "gerrrt.nosuchdir" } })\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  _nvr_catches 'imports "gerrrt.nosuchdir"' "reports a lazy import that matches no module"

  # the inventory must map module names the way LUA does, or the walk marks the wrong rows
  # visited. Two files claiming one name: lua loads exactly one (package.path order), so
  # the other is dead config riding on its twin's reachability.
  _nvr_fresh
  mkdir -p "$NREPO/nvim/lua/gerrrt/utils/dup"
  printf 'require("gerrrt.utils.dup")\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/dup.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/dup/init.lua"
  _nvr_catches 'duplicate module id' "catches two files claiming one module id"

  # a dot inside a filename is not a path separator to lua: require("gerrrt.a.b") resolves
  # a/b.lua, never a.b.lua — so the file is unaddressable, and must not masquerade as the
  # module some other file legitimately owns
  _nvr_fresh
  printf 'require("gerrrt.utils.shadow")\n' >>"$NREPO/nvim/lua/gerrrt/config/lazy.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/shadow.lua"
  printf 'return {}\n' >"$NREPO/nvim/lua/gerrrt/utils/shadow.init.lua"
  _nvr_catches 'unaddressable module file' "catches a literal-dot filename lua cannot address"

  # a repo with no nvim/ (every OS repo) is silently clean, not an error
  _nvr_fresh; rm -rf "$NREPO/nvim"
  _nvr_clean "no nvim/ tree is a clean no-op"
fi
