# nexos

Personal NixOS configuration, as a flake. Organized by **machine** first,
then by **user** — each machine gets its own directory under `machines/`,
and each user gets their own directory under `users/`, so adding a new
machine or a new user later doesn't require restructuring anything.

Two machines today: **caixa** (terminal-only, reachable over SSH from the local network) and
**marvin** (laptop, dual-booting Windows with Secure Boot on), which runs
Hyprland with the [Noctalia](https://docs.noctalia.dev) shell for
`henrique`.

## Folder structure

```
nexos/
  flake.nix / flake.lock      # inputs (nixpkgs, home-manager, sops-nix, disko, noctalia,
                              # noctalia-greeter, hyprqt6engine, monitor-settings, helium,
                              # lanzaboote) and outputs; hosts are built by mkHost
  .sops.yaml                  # sops-nix: which age key(s) can decrypt which secrets files
  .gitignore                  # keeps keys/ (private keys) out of git

  machines/
    caixa/
      configuration.nix          # what's specific to this machine (GPU, remote access, ...)
      disko-config.nix           # declarative disk partitioning (see below)
      hardware-configuration.nix # hardware-specific bits (CPU, kernel modules) -- NOT filesystems, disko owns those
    marvin/
      configuration.nix          # + Secure Boot (lanzaboote), rEFInd, NVIDIA PRIME, gaming
      disko-config.nix
      hardware-configuration.nix
      facts.nix                  # disk + PRIME bus IDs, written by install.sh
      install.sh                 # interactive fresh install (see Installing)

  modules/
    nixos/                    # system-level (NixOS) modules, each one feature-scoped
      common.nix                 # what every host shares, terminal only (nix settings, nh, locale, kernel, boot console,
                                 # sops key, home-manager) + imports the modules every host uses
      unfree.nix                 # nexos.unfree: each module lists the unfree packages it needs
      desktop-hyprland.nix       # marvin: Hyprland + Noctalia greeter (greetd), audio, bluetooth, GUI home config
      docker-rootless.nix        # rootless Docker, per-user daemons
      ssh.nix                    # caixa: key-only SSH server, LAN only (no passwords, no root login, fail2ban)
      chrony.nix                 # NTP from NIC.br with NTS
      lan-isolation.nix          # caixa only: LAN interfaces reach just the gateway, no peer-to-peer traffic
      take-monitor.nix (+ .sh)   # switches shared DDC/CI monitors to whichever host boots
      session-stop-timeout.nix   # 10s (not 90s) for stuck login-session processes on shutdown
      cloudflared.nix            # caixa: Cloudflare Tunnel (web apps; SSH is refused through it)
      gaming.nix                 # marvin: Steam, Lutris, MangoHud, PCSX2, Eden, AppImages via binfmt
      refind.nix                 # marvin: rEFInd as the NixOS/Windows picker in front of systemd-boot
    home/                     # home-manager modules (per-user environment, not system config)
      cli.nix                    # git, gh, glow, zoxide
      dev.nix                    # direnv + nix-direnv + devenv, so per-project environments auto-activate
      chat.nix                   # Telegram, Vesktop (Discord), ZapFast (WhatsApp)
      design.nix                 # Inkscape
      ai.nix                     # Claude Code + its policy (CLAUDE.md)
      claude-voice.nix           # Claude Code's /voice skill: reads replies aloud, pt_BR piper voice
      hyprland.nix               # Hyprland session, Noctalia shell + the color palette, foot, GTK/Qt theming
      helium.nix                 # Helium browser
      neovim.nix                 # declarative Neovim: LSP client, treesitter, telescope, etc.
      zed.nix                    # Zed editor (launched as `IDE`)
      zsh.nix                    # zsh, prompt, eza, the nrs/nrt aliases

  users/
    henrique/
      default.nix              # NixOS account: shell, groups, SSH authorized_keys, password hash
      home.nix                 # home-manager config for this user, terminal half (every host)
      home-desktop.nix         # GUI half (Hyprland, apps), imported by desktop-hyprland.nix

  dotfiles/
    noctalia/<host>/settings.toml  # Noctalia control-center settings, synced on every rebuild (see below)

  templates/                  # per-language devenv environments, meant to be dropped into OTHER
                              # project repos (not used here) via `nix flake init -t`
    rust/ python/ c/ sql/ web/   # each: devenv.nix + devenv.yaml + .envrc
    containers/                  # add-on: containers.nix (rootless Podman tied to the shell)

  secrets/
    caixa.yaml / marvin.yaml   # sops-encrypted secrets per host (password hashes, tunnel credentials, ...)
    README.md                  # how the secrets/sops workflow works, in detail

  keys/                       # git-ignored. Private keys live here locally: SSH keys, age keys,
                              # plaintext passwords. Never committed.
```

**The pattern for adding things:**
- New machine → new folder under `machines/` (its `configuration.nix` imports `modules/nixos/common.nix`), add `<name> = mkHost "<name>";` to `nixosConfigurations` in `flake.nix`.
- New user (on an existing machine) → new folder under `users/`, import it from that machine's `configuration.nix`.
- New system-wide feature → new file under `modules/nixos/`, imported by `common.nix` (every host) or by whichever machine(s) need it.
- New personal tool/dotfile → new file under `modules/home/`, imported by whichever user(s) want it.
- Unfree package → add its name to `nexos.unfree` in the module that uses it.

## What's configured

On both machines:

- **Disk** (declared with [disko](https://github.com/nix-community/disko), passphrase asked at boot on the Plymouth splash):
  - **marvin**: LUKS-encrypted btrfs, subvolumes for `/`, `/home`, `/nix`, plus a btrfs-native swapfile.
  - **caixa**: ZFS pool `zroot` with native encryption (aes-256-gcm) on the pool root, datasets for `/`, `/home`, `/nix`, `/var/lib/db` (8K records, for databases; k3s' `db` StorageClass lives there) and a 1G `reserved`, swap on its own partition re-keyed randomly each boot. One disk today; ZFS so more can join as an array later (`zpool attach` for a mirror). See `machines/caixa/zfs.nix`.
- **User**: `henrique` (sudo/wheel).
- **Docker**: rootless, one daemon per user, auto-starts at login (via `linger`).
- **Secrets**: managed with [sops-nix](https://github.com/Mic92/sops-nix) + `age`; see `secrets/README.md` for the full secrets workflow (rotating keys, adding new secrets, etc).

**caixa** additionally:

- **Terminal only**: no graphical session, greeter or auto-login; just getty on the console.
- **SSH**: key-only, no password auth, local network only: just marvin, by MAC (`modules/nixos/ssh.nix`, `lan-isolation.nix`). 3 failed attempts and fail2ban bans the address. Refused over loopback, so it can't be reached through the Cloudflare Tunnel (`cloudflared`, outbound-only, kept for web apps such as the lab console; its token is sops-encrypted, see `modules/nixos/cloudflared.nix`).
- **LAN isolation**: from the local network only the gateway is reachable, in both directions, plus SSH from marvin (`modules/nixos/lan-isolation.nix`).
- `net.ipv4.ip_forward` on, for Mininet.

**marvin** additionally:

- **Desktop**: Hyprland with the Noctalia shell, and the Noctalia greeter (on greetd) as the login screen. No SSH server.
- **Dual boot with Windows**, each on its own disk and ESP. **rEFInd** is the first menu (NixOS or Windows); NixOS goes on to systemd-boot's list of generations.
- **Secure Boot** on, via [lanzaboote](https://github.com/nix-community/lanzaboote). The keys live in `/var/lib/sbctl` (**back that directory up**: without it new generations can't be signed). They were enrolled with `sbctl enroll-keys --append --microsoft` on top of the firmware's existing db/KEK/dbx, so Windows (including its 2023 CA) and the NVIDIA option ROM stay trusted.
- **ESP is only 512M**, and each initrd is ~210M (the NVIDIA driver is in it), so `boot.lanzaboote.configurationLimit = 2`. If a rebuild fails with `No space left on device`, consecutive kernel/driver updates filled it.
- **NVIDIA PRIME** offload (GTX 1650 + Intel iGPU); Hyprland itself renders on the NVIDIA GPU, since the HDMI port is wired to it.
- **Gaming**: Steam, Lutris, MangoHud, PCSX2, Eden. AppImages (e.g. game recomps) run directly, through `appimage-run` via binfmt.

## Day to day

| Command | What it does |
|---|---|
| `nrs` | `nh os switch`: build this host's config and switch to it (shows what changed) |
| `nrt` | `nh os test`: switch now, but don't make it the boot default — a reboot goes back |
| `nix flake update` then `nrs` | update every input (packages); commit `flake.lock` afterwards |
| `nix flake update nixpkgs` | update only nixpkgs |
| `sudo nixos-rebuild switch --rollback` | go back to the previous generation |

`nh` finds this flake via `programs.nh.flake` and the host by hostname, and asks for sudo itself — use `nrs`, not `sudo nrs`. `nh clean` also runs periodically, keeping generations from the last 4 days (at least 3).

## Theming

All colors are set in **one place**: `customPalettes.henrique` in `modules/home/hyprland.nix` (Tama's colors, from Gintama; dark and light variants). Noctalia renders them into every other app through its templates:

- builtin: GTK3/GTK4, Qt (hyprqt6engine for Qt6, a patched qt5ct for Qt5), KDE color schemes, Hyprland (borders, groupbar, the background behind windows) and foot;
- community (fetched from `api.noctalia.dev`): Telegram, Helium (`ungoogled-chromium`) and Vesktop (`discord`).

The greeter runs before login and can't read that palette, so `modules/nixos/desktop-hyprland.nix` converts it into the greeter's own `[appearance.palette]`.

The community templates only write a theme file; each app needs it loaded **once**:

- **Helium**: `chrome://extensions` → Developer mode → Load unpacked → `~/.cache/noctalia/ungoogled-chromium/theme` (restart Helium after palette changes).
- **Telegram**: Settings → Chat Settings → Choose from file → `~/.config/telegram-desktop/themes/noctalia.tdesktop-theme` (again after palette changes).
- **Vesktop**: Settings → Themes → enable one of the `noctalia` themes.

If a theme file is missing or stale, `noctalia msg templates-apply` re-renders every template without restarting anything.

### Noctalia control-center settings

What you change in Noctalia's control center is saved to `~/.local/state/noctalia/settings.toml`, layered over the config generated from Nix. Every rebuild syncs it with `dotfiles/noctalia/<host>/settings.toml` in this repo: the newer side wins, and a missing side (e.g. after a reinstall) is filled from the other. So: change things in the control center, rebuild, **commit** the file. Run `nrs` (and commit) before a `git pull` that touches it, or the pulled copy wins.

## Installing

Either path below ends with the same command (`<host>` is `caixa` or `marvin`):

```sh
sudo nixos-rebuild switch --flake .#<host>
```

The `nrs`/`nrt` aliases only exist once this config has been applied, so use the full command the first time. The difference between the two paths is just how you get to that point.

### Option A — Fresh install from a NixOS ISO (using disko)

> **marvin:** `sudo ./machines/marvin/install.sh` does all of the steps
> below interactively. It picks the disk from an `lsblk` list, detects the
> PRIME bus IDs and records both in `machines/marvin/facts.nix`, so there's
> nothing to edit by hand. `--dry-run` shows what it would write without
> touching any disk. Commit the generated `facts.nix` and
> `hardware-configuration.nix` afterwards. Secure Boot (see
> [What's configured](#whats-configured)) needs its keys created and
> enrolled by hand afterwards, with Secure Boot off until then.

1. **Boot the [NixOS installer ISO](https://nixos.org/download)** on the target machine, get networking up (`ip a`, or `nmtui` if using the graphical ISO).

2. **Confirm the real disk device** with `lsblk`, e.g. `/dev/sda` or `/dev/nvme0n1`. Then edit `machines/caixa/disko-config.nix` and replace the placeholder `device = "/dev/sda";` with the real one. **This step matters — disko wipes whatever device you point it at.**

3. **Get this repo onto the installer environment** — easiest is cloning it if you have network access:
   ```sh
   nix-shell -p git --run "git clone <your-repo-url> /tmp/nexos"
   cd /tmp/nexos
   ```
   (Or copy it via a USB stick if you don't want to push it anywhere yet.)

4. **Place the host's age private key** at `/var/lib/sops-nix/key.txt` on the target disk *before* the config is ever activated — since it doesn't exist until you put it there. You'll do this right after disko formats the disk and mounts it at `/mnt` (next step), so the target path is actually `/mnt/var/lib/sops-nix/key.txt`:
   ```sh
   mkdir -p /mnt/var/lib/sops-nix
   cp /path/to/<host>-key.txt /mnt/var/lib/sops-nix/key.txt   # from your keys/ folder, transferred via USB/scp
   chmod 600 /mnt/var/lib/sops-nix/key.txt
   ```
   (Do this after step 5's `disko` run, since `/mnt` only exists once disko has partitioned and mounted things — the order here is: run disko, then copy the key in, then generate hardware config, then install.)

5. **Run disko** to partition, format, and mount everything declared in `disko-config.nix`:
   ```sh
   nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko -- \
     --mode disko ./machines/caixa/disko-config.nix
   ```
   This prompts for the passphrase you want to set (interactive, no keyfile — see `disko-config.nix`): the ZFS pool's on caixa, LUKS on marvin. On caixa, boot the installer with ZFS support (`boot.supportedFilesystems = [ "zfs" ]`, e.g. the stock NixOS ISO) and set any `networking.hostId` there.

6. **Copy in the age key** now that `/mnt` exists (see step 4's commands).

7. **Generate the real hardware config**, replacing the placeholder:
   ```sh
   nixos-generate-config --no-filesystems --root /mnt
   cp /mnt/etc/nixos/hardware-configuration.nix machines/caixa/hardware-configuration.nix
   ```
   `--no-filesystems` matters — disko already owns `fileSystems`/`swapDevices`; a generated file that redefines them will conflict. Bootloader config (`boot.loader.systemd-boot.enable`, etc.) intentionally lives in `configuration.nix`, not here — this file gets wholesale-replaced by the command above, so anything that mattered would be lost if it lived in this file instead.

8. **Install**:
   ```sh
   nixos-install --root /mnt --flake .#caixa
   ```
   On marvin you'll be prompted for the LUKS passphrase again during install. On caixa the pool is still imported with its key loaded from step 5; run `zpool export zroot` after the install, before rebooting, or the next boot finds it "in use by another system".

9. **Reboot.** From here on, log in as henrique at the physical console (Hyprland on marvin, a plain text console on caixa) or, on caixa, SSH in with the appropriate private key from `keys/`. Clone this repo to `/home/henrique/codigos/nexos` — that's where `nh` (and the Noctalia settings sync) expects it.

10. **Finish the secrets setup** per `secrets/README.md` if you haven't already — real cloudflared tunnel credentials, real password hashes, etc. should already be in `secrets/<host>.yaml` if you're using a clone of this repo as-is; only the age key placement (step 4/6) is the part that has to happen manually per physical machine.

### Moving caixa from LUKS + btrfs to ZFS

There's no in-place conversion: it's Option A on the same disk, and the disk
is wiped. Before booting the installer, copy off caixa:

- `/home` (and anything else you care about under `/var/lib`);
- nothing key-related: `sudo bash machines/caixa/install.sh` generates a new
  SSH host key and re-encrypts the secrets for it with the admin key (see
  its header and `secrets/README.md`). SSH clients see a new host key.

Then run it from the installer (Option A's steps, automated). At the first
boot the Plymouth splash asks for the pool passphrase (`Enter key for zroot`).

### Option B — Adopting this config on an already-running NixOS system

Use this if the machine already has *some* NixOS installation and you're switching it over to this flake, rather than doing a from-scratch install.

1. **Clone this repo** onto the machine, at `/home/henrique/codigos/nexos`.

2. **Decide on the disk layout.** If the existing install's partitioning already roughly matches what `disko-config.nix` describes (LUKS + btrfs + the right subvolumes), you can skip disko entirely and just delete/ignore `disko-config.nix`'s import in `flake.nix`, keeping the system's real `hardware-configuration.nix`/`fileSystems` as normal. If you want to actually adopt disko's exact layout, that means reformatting the disk — treat it like Option A instead (back up data first).

3. **Place the age key** at `/var/lib/sops-nix/key.txt` (root-owned, `chmod 600`) — no `/mnt` prefix needed this time, since the system is already booted:
   ```sh
   sudo mkdir -p /var/lib/sops-nix
   sudo cp /path/to/<host>-key.txt /var/lib/sops-nix/key.txt
   sudo chmod 600 /var/lib/sops-nix/key.txt
   ```

4. **Switch**:
   ```sh
   sudo nixos-rebuild switch --flake .#<host>
   ```

   Since this repo's SSH module disables password auth, make sure you have a working key-based session (or physical/console access) *before* this switch takes effect — otherwise you could lock yourself out of SSH access with no way back in except the physical console.

## Using the devenv templates

`henrique`'s Neovim (`modules/home/neovim.nix`) is deliberately generic:
LSP client, treesitter, completion, telescope, gitsigns — but **no**
per-language LSP servers or compilers/runtimes installed globally. Those
come from a per-project [devenv](https://devenv.sh) environment instead,
so each project only pulls in the toolchain it actually needs. The
`templates/` folder in this repo holds one per language (`rust`,
`python`, `c`, `sql`, `web` for JS/TS) — meant to be dropped into your
*other* project repos, not used inside `nexos` itself.

1. **Drop the template into your project** (once per project):
   ```sh
   cd ~/my-project
   nix flake init -t nexos#rust   # or #python, #c, #sql, #web
   ```
   This adds `devenv.nix`, `devenv.yaml` and `.envrc`. `nexos` here is a
   short alias for this flake, registered via `nix.registry.nexos` in
   `modules/nixos/common.nix` — without that, you'd need the full path
   (`nix flake init -t /home/henrique/codigos/nexos#rust`).

2. **Authorize direnv** (also once per project — it's a safety prompt,
   since a `.envrc` can run arbitrary code):
   ```sh
   direnv allow
   ```

3. **That's it.** From then on, `cd`-ing into the project auto-activates
   the environment (you'll see `direnv: loading ...`), putting that
   language's compiler/LSP/formatter on `PATH` — and Neovim picks up the
   right LSP automatically when opened from inside the project. Leaving
   the directory removes them from `PATH` again.

   Prefer not to use direnv for a given project? Skip the `.envrc` and
   run `devenv shell` manually instead — same effect, but only for that
   shell session, and you have to re-run it every new terminal.

### Adding containers (`#containers`)

`containers` is an add-on, not a language: it drops a single
`containers.nix` next to the `devenv.nix` you already have. Import it
there:

```sh
nix flake init -t nexos#containers
# devenv.nix:  imports = [ ./containers.nix ];
```

It gives the project its **own rootless Podman** (`podman`,
`podman-compose`, and `DOCKER_HOST` pointing at a project-scoped API
socket), with images/containers/networks stored under
`.devenv/state/podman` — not shared with other projects or with the
machine-wide rootless Docker. Its lifetime is the shell's: when the last
shell that activated it goes away (`devenv shell` exited, terminal closed,
or — with direnv — that shell `cd`'d out of the project), a watchdog stops
every container and kills the API service and the rootless pause process.
`containers-guard status` shows what is up; `containers-guard down` tears
it down on demand.

Image pulls go through a deny-by-default Podman signature policy:
`containersGuard.allowedImages` lists the registry repositories a project
may pull (optionally requiring a cosign key), and
`containersGuard.allowArchiveLoad = true` permits `podman load` for base
images verified another way (e.g. a Nix store path signed by
cache.nixos.org) while keeping every registry closed.

## Verifying before you trust it on real hardware

You don't need real hardware to sanity-check this flake — evaluate and build it anywhere with Nix (or via a `nixos/nix` Docker container if you don't have Nix installed locally):

```sh
nix flake check
nix build '.#nixosConfigurations.caixa.config.system.build.toplevel'
nix build '.#nixosConfigurations.marvin.config.system.build.toplevel'
```

These should complete cleanly before you attempt an actual install or switch.
