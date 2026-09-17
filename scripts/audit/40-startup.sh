# scripts/audit/40-startup.sh
# THE gate: install the committed pins, start the editor, and ask it if it is healthy
#
# A SOURCED FRAGMENT of scripts/audit-nvim.sh — see scripts/audit/05-shape.sh's header
# for the contract.

# ── 4. headless startup + :checkhealth, against the real pins ─────────────────
# THIS SECTION IS WHY THE REPO EXISTS. dotfiles-core lints the Lua (luacheck), walks the
# module graph (reachability) and loads every module in isolation with the runtimepath
# faked (scripts/test/15-nvim.sh) — but nothing there has ever installed the plugin set
# and STARTED the editor. So the one change class this tree receives most, a lazy-lock.json
# pin bump from the freshness bot, ships through a gate that cannot see the thing it
# breaks: lazy resolves a new revision, a plugin's setup() signature moved under it, and
# the first host to open nvim finds out. NVIM-SPLIT-PROPOSAL.md §3.3 calls this the gate
# Core cannot give the editor and the reason extraction beats a freeze.
#
# `:Lazy! restore`, NOT `sync`. restore checks out exactly the revisions in the lockfile;
# sync rolls them forward. This section's question is "do the pins we are about to ship
# actually work", so it must install the pins under review and nothing else.
# scripts/update-nvim-plugins.sh is the one thing allowed to MOVE them, and it is a
# separate entry point for that reason.
#
# Everything happens in a throwaway XDG tree with config/nvim symlinked at the repo, the
# same construction update-nvim-plugins.sh uses — so the run reads THIS repo's real config
# and touches nothing in $HOME.
hdr "headless startup + :checkhealth (real pins)"

_st_skip=''
have nvim || _st_skip='neovim is not installed'
[[ -z "$_st_skip" ]] && { have git || _st_skip='git is not installed'; }

if [[ -n "$_st_skip" ]]; then
  skip "headless startup + :checkhealth ($_st_skip)"
elif ((OFFLINE)); then
  # A plugin install needs the network. Declared as an ENVIRONMENT skip, not a tool skip:
  # --strict reds on a missing tool because CI installs every one on purpose, and reading
  # "no network" as "you forgot to install something" sends the reader to the wrong place.
  skip_env "headless startup + :checkhealth (offline — a plugin install needs the network)"
else
  _st_root="$SANDBOX/startup"
  mkdir -p "$_st_root/config" "$_st_root/data" "$_st_root/state" "$_st_root/cache"
  ln -s "$HERE/nvim" "$_st_root/config/nvim"

  # 4a. install the committed pins.
  # DOTFILES_OFFLINE=0 so the config's own offline guard never suppresses the install we
  # are explicitly asking for.
  if HOME="$_st_root" XDG_CONFIG_HOME="$_st_root/config" XDG_DATA_HOME="$_st_root/data" \
    XDG_STATE_HOME="$_st_root/state" XDG_CACHE_HOME="$_st_root/cache" DOTFILES_OFFLINE=0 \
    nvim --headless "+Lazy! restore" +qa </dev/null >"$_st_root/restore.log" 2>&1; then
    _st_n="$(find "$_st_root/data/nvim/lazy" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | grep -c . || true)"
    if ((_st_n > 0)); then
      pass "plugins: :Lazy! restore installed $_st_n plugin(s) at the committed revisions"
    else
      fail "plugins: :Lazy! restore exited 0 but installed nothing — a green run that did no work is not a pass"
      fail_detail "$(tail -n 20 "$_st_root/restore.log" 2>/dev/null)"
      _st_skip=installed-nothing
    fi
  else
    fail "plugins: :Lazy! restore failed against the committed pins"
    fail_detail "$(tail -n 25 "$_st_root/restore.log" 2>/dev/null)"
    _st_skip=restore-failed
  fi

  # 4b. the lockfile must survive the restore unchanged.
  # lazy seeds $XDG_STATE_HOME/nvim/lazy-lock.json from the repo copy (#465) and rewrites
  # it as it works. After a RESTORE the two must still agree: a difference means a pin in
  # the committed lock could not be honoured — the plugin's remote moved, a revision was
  # force-pushed away, a repo was deleted — which is the fresh-bootstrap failure mode
  # NVIM-SPLIT-PROPOSAL.md §4 names as the risk a freeze leaves armed. It is invisible to
  # every other check here, because the Lua on disk is unchanged and perfectly lintable.
  #
  # ONE ENTRY IS EXCLUDED, AND IT IS NOT AN EXCEPTION TO THE RULE — it is outside the rule.
  # lazy.nvim bootstraps ITSELF: nvim/lua/gerrrt/config/lazy.lua git-clones it at
  # `--branch=stable` and prepends it to the runtimepath BEFORE any lockfile is read, so
  # lazy is already running at whatever that branch pointed to by the time restore could
  # have a say. Its lockfile line is therefore a RECORD of what the bootstrap fetched, not
  # a pin anything honours, and it moves on every box whose stable branch has advanced.
  # Asserting on it would red this gate for a reason no change here can fix, on a schedule
  # set by another project — the definition of a gate that gets switched off.
  # Its drift is reported below instead, where it belongs: as news, not as a failure.
  if [[ -z "$_st_skip" ]]; then
    _st_lock="$_st_root/state/nvim/lazy-lock.json"
    if [[ ! -f "$_st_lock" ]]; then
      fail "plugins: the restore wrote no state lockfile at $_st_lock"
    else
      grep -v '"lazy\.nvim"' "$HERE/nvim/lazy-lock.json" >"$_st_root/lock.committed"
      grep -v '"lazy\.nvim"' "$_st_lock" >"$_st_root/lock.restored"
      if core_files_identical "$_st_root/lock.committed" "$_st_root/lock.restored"; then
        pass "plugins: every committed pin was honoured (the lockfile is unchanged by the restore)"
      else
        fail "plugins: the restore could not honour the committed lockfile — a pinned revision is gone or moved"
        fail_detail "$(git diff --no-index -- "$_st_root/lock.committed" "$_st_root/lock.restored" 2>&1 | grep '^[-+] ' | head -n 20)"
      fi
      # The bootstrap's own copy of lazy.nvim, reported and never red. A move here is what
      # scripts/update-nvim-plugins.sh would fold into the lock on its next run.
      _st_lazy_have="$(sed -n 's/.*"lazy\.nvim": *{ *"branch": *"[^"]*", *"commit": *"\([0-9a-f]*\)".*/\1/p' "$_st_lock")"
      _st_lazy_want="$(sed -n 's/.*"lazy\.nvim": *{ *"branch": *"[^"]*", *"commit": *"\([0-9a-f]*\)".*/\1/p' "$HERE/nvim/lazy-lock.json")"
      if [[ "$_st_lazy_have" == "$_st_lazy_want" ]]; then
        pass "plugins: the bootstrapped lazy.nvim matches the recorded revision (${_st_lazy_want:0:12})"
      else
        skip_note "plugins: lazy.nvim's stable branch has moved (recorded ${_st_lazy_want:0:12}, fetched ${_st_lazy_have:0:12}) — it bootstraps itself, so this is news, not a finding; make update-nvim-plugins folds it in"
      fi
      unset _st_lazy_have _st_lazy_want
    fi
    unset _st_lock
  fi

  # 4c. start the editor for real.
  # The whole config, every plugin, no -u NONE and no faked runtimepath: this is what a
  # host gets. Errors during startup land on stderr, so stderr IS the assertion — nvim
  # exits 0 from `+qa` even when a plugin threw on the way in.
  if [[ -z "$_st_skip" ]]; then
    HOME="$_st_root" XDG_CONFIG_HOME="$_st_root/config" XDG_DATA_HOME="$_st_root/data" \
      XDG_STATE_HOME="$_st_root/state" XDG_CACHE_HOME="$_st_root/cache" DOTFILES_OFFLINE=1 \
      nvim --headless -i NONE +qa </dev/null >"$_st_root/start.out" 2>"$_st_root/start.err"
    _st_rc=$?
    if ((_st_rc == 0)) && [[ ! -s "$_st_root/start.err" ]]; then
      pass "startup: the editor starts clean with the full plugin set (no stderr)"
    else
      fail "startup: the editor did not start clean (exit $_st_rc)"
      fail_detail "$(cat "$_st_root/start.err" 2>/dev/null)"
    fi
    unset _st_rc
  fi

  # 4d. :checkhealth gerrrt.
  # OURS, not the bare `:checkhealth`. The bare one reports on every provider and every
  # plugin that ships a health module, so it reds for node, go, ruby and a Mason toolchain
  # this repo does not claim and a CI runner has no reason to carry — a gate that is red on
  # arrival gets switched off. `gerrrt` is the health module this repo authors, and each of
  # its five helpers calls h.start() before any early return, so a missing header proves
  # that helper threw. scripts/test/15-nvim.sh asserts the same five sections WITHOUT
  # plugins; this asserts them WITH.
  if [[ -z "$_st_skip" ]]; then
    _st_rep="$_st_root/checkhealth.txt"
    : >"$_st_rep"
    # SC2016 is the POINT of the single quotes below: $CORE_CK_REP is expanded by VIM,
    # not by this shell, and fnameescape()ing it there is what keeps a space in $TMPDIR
    # from breaking the Ex `write` parsing. Same idiom as scripts/test/15-nvim.sh.
    # shellcheck disable=SC2016
    HOME="$_st_root" XDG_CONFIG_HOME="$_st_root/config" XDG_DATA_HOME="$_st_root/data" \
      XDG_STATE_HOME="$_st_root/state" XDG_CACHE_HOME="$_st_root/cache" DOTFILES_OFFLINE=1 \
      CORE_CK_REP="$_st_rep" \
      nvim --headless -i NONE \
      -c 'checkhealth gerrrt' \
      -c 'execute "write!" fnameescape($CORE_CK_REP)' \
      -c 'qa!' </dev/null >/dev/null 2>"$_st_root/health.err"
    _st_missing=''
    for _st_sec in clipboard "LSP servers" formatters linters "Claude Code"; do
      grep -q ": $_st_sec" "$_st_rep" 2>/dev/null || _st_missing="${_st_missing:+$_st_missing, }$_st_sec"
    done
    if [[ -z "$_st_missing" ]]; then
      pass "checkhealth gerrrt: all five sections rendered with the plugin set loaded"
    else
      fail "checkhealth gerrrt: section(s) missing — a check() helper threw: $_st_missing"
      [[ -s "$_st_rep" ]] && fail_detail "$(cat "$_st_rep")"
      [[ -s "$_st_root/health.err" ]] && fail_detail "$(cat "$_st_root/health.err")"
    fi
    # A health ERROR is a finding even when every section rendered — the headers prove the
    # helpers ran, not that they were happy.
    _st_errs="$(grep -n '^[[:space:]]*- ERROR' "$_st_rep" 2>/dev/null || true)"
    if [[ -z "$_st_errs" ]]; then
      pass "checkhealth gerrrt: no ERROR lines"
    else
      fail "checkhealth gerrrt: reported ERROR(s)"
      fail_detail "$_st_errs"
    fi
    unset _st_rep _st_missing _st_sec _st_errs
  fi

  unset _st_root _st_n
fi
unset _st_skip
