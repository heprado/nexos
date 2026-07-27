# nexos

Personal NixOS configuration, as a flake. Organized by **machine** first,
then by **user** — each machine gets its own directory under `machines/`,
and each user gets their own directory under `users/`, so adding a new
machine or a new user later doesn't require restructuring anything.

## Folder structure

```
nexos/
  flake.nix / flake.lock      # inputs (nixpkgs, home-manager, sops-nix, disko) and outputs
  .sops.yaml                  # sops-nix: which age key(s) can decrypt which secrets files
  .gitignore                  # keeps keys/ (private keys) out of git

  machines/
    caixa/
      configuration.nix          # this machine's top-level config: imports modules + users, hostname, etc.
      disko-config.nix           # declarative disk partitioning (see below)
      hardware-configuration.nix # hardware-specific bits (CPU, kernel modules) -- NOT filesystems, disko owns those

  modules/
    nixos/                    # system-level (NixOS) modules, each one feature-scoped
      docker-rootless.nix        # rootless Docker, per-user daemons
      ssh.nix                    # key-only SSH (no passwords, no root login)
      tailscale.nix               # Tailscale client, authkey via sops
      desktop-hyprland.nix        # Hyprland + SDDM, local physical console
      desktop-plasma-rdp.nix      # KDE Plasma over RDP (xrdp), Tailscale-only, henrique excluded
      wayvnc-hyprland.nix         # wayvnc: remote access to henrique's actual Hyprland session
    home/                     # home-manager modules (per-user environment, not system config)
      claude-code.nix            # installs Claude Code
      zoxide.nix                 # zoxide + zsh integration
      hyprland.nix               # Hyprland session config + Noctalia shell

  users/
    <name>/
      default.nix              # NixOS account: shell, groups, SSH authorized_keys, password hash
      home.nix                 # home-manager config for this user: which modules/home/*.nix apply

  secrets/
    caixa.yaml                 # sops-encrypted secrets for caixa (Tailscale authkey, password hashes, etc.)
    README.md                  # how the secrets/sops workflow works, in detail

  keys/                       # git-ignored. Private keys live here locally: SSH keys, caixa's
                               # age key, plaintext passwords. Never committed.
```

**The pattern for adding things:**
- New machine → new folder under `machines/`, add a `nixosConfigurations.<name>` entry in `flake.nix`.
- New user (on an existing machine) → new folder under `users/`, import it from that machine's `configuration.nix`.
- New system-wide feature → new file under `modules/nixos/`, imported by whichever machine(s) need it.
- New personal tool/dotfile → new file under `modules/home/`, imported by whichever user(s) want it.

## What's configured on `caixa`

- **Disk**: LUKS-encrypted (interactive passphrase) btrfs via [disko](https://github.com/nix-community/disko), subvolumes for `/`, `/home`, `/nix`, plus a btrfs-native swapfile.
- **Users**: `henrique` (sudo/wheel), `leonardo`, `martin` — none have SSH password auth, only key-based.
- **Docker**: rootless, one daemon per user, auto-starts at login (via `linger`).
- **Tailscale**: joins declaratively via a sops-encrypted authkey.
- **Desktops**: `henrique` gets Hyprland (with the [Noctalia](https://docs.noctalia.dev) shell) at the physical console, plus remote access to that *same* session over VNC (`wayvnc`, since RDP doesn't support Wayland). `leonardo` and `martin` get KDE Plasma over RDP, reachable via Tailscale.
- **Secrets**: managed with [sops-nix](https://github.com/Mic92/sops-nix) + `age`; see `secrets/README.md` for the full secrets workflow (rotating keys, adding new secrets, etc).

## Installing

Either path below ends with the same command:

```sh
sudo nixos-rebuild switch --flake .#caixa
```

The difference is just how you get to that point.

### Option A — Fresh install from a NixOS ISO (using disko)

1. **Boot the [NixOS installer ISO](https://nixos.org/download)** on the target machine, get networking up (`ip a`, or `nmtui` if using the graphical ISO).

2. **Confirm the real disk device** with `lsblk`, e.g. `/dev/sda` or `/dev/nvme0n1`. Then edit `machines/caixa/disko-config.nix` and replace the placeholder `device = "/dev/sda";` with the real one. **This step matters — disko wipes whatever device you point it at.**

3. **Get this repo onto the installer environment** — easiest is cloning it if you have network access:
   ```sh
   nix-shell -p git --run "git clone <your-repo-url> /tmp/nexos"
   cd /tmp/nexos
   ```
   (Or copy it via a USB stick if you don't want to push it anywhere yet.)

4. **Place caixa's age private key** at `/var/lib/sops-nix/key.txt` on the target disk *before* the config is ever activated — since it doesn't exist until you put it there. You'll do this right after disko formats the disk and mounts it at `/mnt` (next step), so the target path is actually `/mnt/var/lib/sops-nix/key.txt`:
   ```sh
   mkdir -p /mnt/var/lib/sops-nix
   cp /path/to/caixa-key.txt /mnt/var/lib/sops-nix/key.txt   # from your keys/ folder, transferred via USB/scp
   chmod 600 /mnt/var/lib/sops-nix/key.txt
   ```
   (Do this after step 5's `disko` run, since `/mnt` only exists once disko has partitioned and mounted things — the order here is: run disko, then copy the key in, then generate hardware config, then install.)

5. **Run disko** to partition, format, and mount everything declared in `disko-config.nix`:
   ```sh
   nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko -- \
     --mode disko ./machines/caixa/disko-config.nix
   ```
   This prompts for the LUKS passphrase you want to set (interactive, no keyfile — see `disko-config.nix`).

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
   You'll be prompted for the LUKS passphrase again during install (it needs to unlock/interact with the encrypted volume).

9. **Reboot into caixa.** From here on, log in as henrique (Hyprland, physical console) or SSH in with the appropriate private key from `keys/`.

10. **Finish the secrets setup** per `secrets/README.md` if you haven't already — real Tailscale authkey, real password hashes, etc. should already be in `secrets/caixa.yaml` if you're using a clone of this repo as-is; only the age key placement (step 4/6) is the part that has to happen manually per physical machine.

### Option B — Adopting this config on an already-running NixOS system

Use this if caixa (or a machine that will become caixa) already has *some* NixOS installation and you're switching it over to this flake, rather than doing a from-scratch install.

1. **Clone this repo** onto the machine.

2. **Decide on the disk layout.** If the existing install's partitioning already roughly matches what `disko-config.nix` describes (LUKS + btrfs + the right subvolumes), you can skip disko entirely and just delete/ignore `disko-config.nix`'s import in `flake.nix` and `machines/caixa/configuration.nix`, keeping the system's real `hardware-configuration.nix`/`fileSystems` as normal. If you want to actually adopt disko's exact layout, that means reformatting the disk — treat it like Option A instead (back up data first).

3. **Place the age key** at `/var/lib/sops-nix/key.txt` (root-owned, `chmod 600`) — no `/mnt` prefix needed this time, since the system is already booted:
   ```sh
   sudo mkdir -p /var/lib/sops-nix
   sudo cp /path/to/caixa-key.txt /var/lib/sops-nix/key.txt
   sudo chmod 600 /var/lib/sops-nix/key.txt
   ```

4. **Switch**:
   ```sh
   sudo nixos-rebuild switch --flake .#caixa
   ```

   Since this repo's SSH module disables password auth, make sure you have a working key-based session (or physical/console access) *before* this switch takes effect — otherwise you could lock yourself out of SSH access with no way back in except the physical console.

## Verifying before you trust it on real hardware

You don't need real hardware to sanity-check this flake — evaluate and build it anywhere with Nix (or via a `nixos/nix` Docker container if you don't have Nix installed locally):

```sh
nix flake check
nix build '.#nixosConfigurations.caixa.config.system.build.toplevel'
```

Both should complete cleanly before you attempt an actual install or switch.
