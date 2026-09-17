# Security Policy

`dotfiles-nvim` ships **editor configuration only** — Lua, a plugin lockfile, and the shell
tooling that gates them. It is not a running service and stores no credentials or machine
state. Even so, this repo is vendored into
[`dotfiles-core`](https://github.com/dotgibson/dotfiles-core) and from there into every OS
repo in the fleet, plus `dotfiles-Windows` directly — so a defect here **fans out N-way**.

Three classes of issue are worth a security report rather than an ordinary issue:

- a tracked file that leaks a secret, token, or other sensitive value;
- a script under `scripts/` that can be coerced into running untrusted input on a
  contributor's or CI runner's machine;
- **a plugin pin in `nvim/lazy-lock.json` that points at a compromised or hijacked
  revision.** This is the one that is specific to this repo. The pins exist so nothing
  floats silently onto a host, and that same property means a bad pin stays put until
  someone moves it. Do not open a public issue naming it.

## Reporting

Use GitHub's **private vulnerability reporting** on this repository (Security → Report a
vulnerability). If that is unavailable, open an issue asking for a private channel and say
nothing else.

Please include the file and revision, what an attacker gets, and whether it is reachable
from a default `bootstrap` rather than only from a deliberate command.

## What is already checked

`scripts/audit-nvim.sh` installs the committed pins and starts the editor on every PR, so a
pin that no longer resolves fails before it can reach a lock. `.github/workflows/lint.yml`
calls `dotfiles-core`'s reusable gate, which runs gitleaks against the fleet's single
secret-scanning policy. Neither is a substitute for a report: both check shape, not intent.

## Scope

Vulnerabilities in the upstream plugins themselves belong to their own projects — report
them there. What belongs here is the **pin**: that this repo points at a given revision, and
what that revision does on a machine that vendors it.
