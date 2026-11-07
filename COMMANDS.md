# Commands

The rebuild commands this config installs (`modules/home/cli.nix`). They are
commands, not zsh aliases, so they work from any shell, script or coding
agent. `nh` finds this flake via `programs.nh.flake` and the host by
hostname, so they're the same on caixa and marvin. Extra arguments pass
through to `nh` (e.g. `nrs --update`, `nrb --show-trace`).

| Command | Runs | Use it to |
|---|---|---|
| `nrb` | `nh os build` | check that a change builds and see what it changes |
| `nrt` | `nh os test` | try the change on the running system, without committing to it |
| `nrs` | `nh os switch` | keep the change, including after a reboot |

## What each one does

| | `nrb` | `nrt` | `nrs` |
|---|---|---|---|
| Builds the new system | yes | yes | yes |
| Shows the package diff | yes | yes | yes |
| Asks for sudo | no | yes | yes |
| **Activates it now** (services restart, `/etc` changes, home-manager applies) | **no** | **yes** | **yes** |
| Becomes the boot default | no | no — a reboot goes back to the previous generation | yes |
| Adds a boot menu entry | no | no | yes |
| Risk | none, the running system doesn't change | low, a reboot undoes it | the new generation sticks; roll back with `sudo nixos-rebuild switch --rollback` or pick an older entry at boot |

The safe flow is `nrb` → `nrt` → try it → `nrs`.

## Updating inputs: `nfu`

`nfu` (nix flake update) checks an update before it lands: it writes the
updated lock to `~/.cache/nexos/flake.lock.candidate`, without touching the
repo, and asks Nix what this host would build with it (a dry run, nothing is
compiled). It shows which inputs move, the packages to compile with how long
each took the last time it was compiled here (from nix-output-monitor's
history, `~/.local/state/nix-output-monitor/build-reports.csv`), and says
**Ready** when none is heavy: 15 minutes or more here, or, never compiled
here, one that takes an hour or more (electron, chromium, nodejs, the kernel,
llvm, rustc, gcc, webkitgtk, qtwebengine, firefox, openjdk, ...). Otherwise
**Not ready**, with the ones still missing from the binary cache.

| Command | Does |
|---|---|
| `nfu` | a menu of the inputs; the ones with new commits upstream can be picked: ↑↓ (or j/k) move, Enter or Space marks one (or, on **All**, every one), Enter on **Continue** goes on, q quits |
| `nfu nixpkgs` | check an update of just those inputs, without asking |
| `nfu apply` | copy the checked lock into the flake; then `nrb` → `nrt` → `nrs` |

Before the menu, `nfu` asks every input's remote for its latest commit with
`git ls-remote` (the git protocol, outside GitHub's API limit, all at once)
and only those with a newer one than the lock's can be picked; the rest are
shown greyed out as up to date, the cursor skips them, and they stay out of
the update. Inputs given by name are checked the
same way, and the up-to-date ones skipped.

Next to each input, the menu shows when it was locked, the date of the new
commit upstream (only that commit object is fetched, ~100 KB, still no API
request), how many days apart the two are, and how long its
packages took to compile here the last time: the packages the input provides
(its `packages.<system>`) found in this host's system, with their times from
nix-output-monitor's history. nixpkgs gets everything else ever compiled here,
an upper bound, since most of it comes from the binary cache. The sums take
~20 s and are kept in `~/.cache/nexos` until the lock or the history changes.

Each GitHub input costs one API request. Before starting, `nfu` asks GitHub
how many are left (a free request) and stops if there aren't enough, with the
time the limit resets. It uses `gh`'s login when there is one, which raises the
limit from 60 to 5000 requests an hour, passed to Nix through the environment.

Noctalia comes from its own cache (noctalia.cachix.org, `desktop.nix`), so it
doesn't count; noctalia-greeter isn't there and builds here.

`nh` asks for sudo itself, only to activate — use `nrs`, not `sudo nrs`.

## No `result` links

`nh os switch` and `nh os test` keep their result link in a temporary
directory, but `nh os build` writes `./result` into the current directory.
`nrb` points it at `$XDG_RUNTIME_DIR/nrb-result` instead, so nothing is left
in the repo. `nh` refuses a second `-o`, so for another path run
`nh os build -o <path>` directly.

For other outputs, `nix build` also writes `./result` by default; use
`--no-link --print-out-paths` (`--no-out-link` for the legacy `nix-build`),
or `-o` into a scratch directory.

## Coding agents

The agent policy (`modules/home/ai.nix`) has agents check config changes with
`nrb`, activate only when asked, and prefer `nrt` over `nrs`.
