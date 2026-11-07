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
