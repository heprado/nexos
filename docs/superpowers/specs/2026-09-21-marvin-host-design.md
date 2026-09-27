# marvin: new physical host design

## Context

`machines/marvin` already exists in this repo, but as a WSL configuration
(`nixos-wsl`, `home-wsl.nix`, no disko/hardware-configuration). This spec
replaces that entirely: `marvin` becomes a new physical laptop, configured
like `caixa` (same user, same module set), minus `cloudflared`, minus
`wayvnc`/`novnc`, plus NVIDIA hybrid graphics and Steam/Proton for gaming.

## Hardware

- CPU: Intel Core i7-10750H (6c/12t, up to 5.0 GHz)
- RAM: 16 GB DDR4-3200 dual channel
- Storage: SATA SSD 1 TB (new drive) — disk device will be `/dev/sda`
- GPU: NVIDIA GeForce GTX 1650 (TU117M, Turing) + Intel UHD (Comet Lake-H GT2), hybrid/Optimus
- Wi-Fi: Intel Wireless-AC 9560

## Scope

1. Replace `machines/marvin/configuration.nix` (WSL) with a physical-machine
   configuration mirroring `machines/caixa/configuration.nix`.
2. Add `machines/marvin/disko-config.nix` and
   `machines/marvin/hardware-configuration.nix`, mirroring caixa's patterns.
3. Update `flake.nix`'s `nixosConfigurations.marvin` to match caixa's module
   wiring (disko, sops-nix, noctalia-greeter) instead of nixos-wsl.
4. Add NVIDIA PRIME offload config (new — caixa doesn't need this, Intel-only).
5. Add a new `modules/nixos/gaming.nix` (Steam + gamemode), imported only by
   marvin.
6. Bootstrap sops/age for marvin: new age keypair, `.sops.yaml` entry, and
   documented (not executed) steps for `secrets/marvin.yaml`.
7. Add a placeholder SSH key entry for marvin in the shared
   `users/henrique/default.nix`.

## Out of scope

- `cloudflared` (explicitly excluded — no remote-access tunnel on this host).
- `wayvnc-hyprland.nix` / `novnc-hyprland.nix` (explicitly excluded).
- Migrating sops-nix to agenix (discussed, rejected — not worth the rewrite
  for the benefit; sticking with sops-nix repo-wide).
- Generating a real `henrique_password_hash` or actually creating
  `secrets/marvin.yaml` content — needs the real password, done by hand at
  install time (see Secrets Bootstrap below).
- Confirming actual PCI bus IDs for PRIME offload, actual SATA device path,
  and generating the real `hardware-configuration.nix` — all require running
  commands (`lspci`, `lsblk`, `nixos-generate-config`) on marvin itself, so
  they're left as clearly marked placeholders, same pattern caixa already
  uses for its disk device.

## `flake.nix`

Replace the current `nixosConfigurations.marvin` block. Drop
`nixos-wsl.nixosModules.default`. Mirror caixa's module list:

```nix
nixosConfigurations.marvin = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = { inherit inputs self; };
  modules = [
    ./machines/marvin/configuration.nix
    ./machines/marvin/disko-config.nix
    home-manager.nixosModules.home-manager
    sops-nix.nixosModules.sops
    disko.nixosModules.disko
    noctalia-greeter.nixosModules.default
    {
      home-manager.useGlobalPkgs = true;
      home-manager.useUserPackages = true;
      home-manager.extraSpecialArgs = { inherit inputs; };
    }
  ];
};
```

The `nixos-wsl` input itself stays in `inputs` (still used by nothing else,
but removing an input is out of scope here — not asked for, and harmless to
leave).

## `machines/marvin/configuration.nix`

Full rewrite. Imports:

```nix
imports = [
  ./hardware-configuration.nix
  ../../modules/nixos/docker-rootless.nix
  ../../modules/nixos/ssh.nix
  ../../modules/nixos/desktop-hyprland.nix
  ../../modules/nixos/chrony.nix
  ../../modules/nixos/lan-isolation.nix
  ../../modules/nixos/gaming.nix
  ../../users/henrique
];
```

(No `cloudflared.nix`, no `wayvnc-hyprland.nix`, no `novnc-hyprland.nix`.)

Same as caixa:
- Noctalia cachix substituter + `nix.settings.experimental-features`
- `nix.registry.nexos.flake = self;`
- `networking.hostName = "marvin";`
- `programs.zsh.enable = true;`
- `programs.nh` (same flake path, same clean policy)
- `i18n.defaultLocale = "pt_BR.UTF-8";` / `time.timeZone = "America/Sao_Paulo";`
- `programs.dconf.enable = true;`
- `nixpkgs.overlays = [ inputs.helium-flake.overlays.default ];`
- `boot.loader.systemd-boot.enable = true;` / `boot.loader.efi.canTouchEfiVariables = true;`
- `boot.kernelPackages = pkgs.linuxPackages_latest;`
- `home-manager.users.henrique = import ../../users/henrique/home.nix;` (the
  physical-desktop home, same file caixa uses — not `home-wsl.nix`)
- `sops.defaultSopsFile = ../../secrets/marvin.yaml;`
- `sops.age.keyFile = "/var/lib/sops-nix/key.txt";`
- `system.stateVersion = "24.05";`

Differences from caixa (beyond the import list):
- No `boot.kernel.sysctl."net.ipv4.ip_forward"` (that's for caixa's Mininet
  use case, not requested here).
- No `boot.kernelParams = [ "ahci.mobile_lpm_policy=1" ]` (that's a fix for
  caixa's specific SSD/controller; not applicable, and not something to
  cargo-cult onto new hardware).
- No `environment.systemPackages = [ pkgs.android-tools ]` (caixa-specific
  ESP32/Android debugging use case; not requested for marvin).
- No `hardware.graphics.extraPackages = [ pkgs.intel-media-driver ]` /
  `LIBVA_DRIVER_NAME` block — replaced by the NVIDIA hybrid config below,
  which supersedes caixa's Intel-only VAAPI setup.
- `allowUnfreePredicate` list: same as caixa's, plus whatever the NVIDIA
  driver package needs (`nvidia-x11`, if it isn't already implicitly
  allowed by `hardware.nvidia`).

## GPU: NVIDIA hybrid graphics (new)

```nix
hardware.graphics = {
  enable = true;
  enable32Bit = true; # required for Steam/Proton
};

hardware.nvidia = {
  modesetting.enable = true;
  open = false; # TU117 (Turing) predates the open kernel module's support window
  package = config.boot.kernelPackages.nvidiaPackages.stable;
  prime = {
    offload.enable = true;
    # PLACEHOLDER — confirm with `lspci | grep -E "VGA|3D"` on marvin itself.
    intelBusId = "PCI:0:2:0";
    nvidiaBusId = "PCI:1:0:0";
  };
};

services.xserver.videoDrivers = [ "nvidia" ];
```

PRIME offload keeps the Intel iGPU as the default renderer (battery-friendly)
and lets specific processes (games, via `nvidia-offload` or Steam's launch
options) run on the GTX 1650 on demand.

## `modules/nixos/gaming.nix` (new)

```nix
{ pkgs, ... }:
{
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true;
    gamescopeSession.enable = true;
  };
  programs.gamemode.enable = true;
}
```

Imported only by `machines/marvin/configuration.nix` — this is
gaming-machine-specific, not a caixa capability being ported.

## `machines/marvin/disko-config.nix` (new)

Same shape as caixa's: GPT, 512M ESP, one LUKS partition over btrfs with
`@` / `@home` / `@nix` / `@swap` subvolumes (8G swapfile), same mount
options. `device = "/dev/sda";` (placeholder, same pattern as caixa's own
`/dev/sda` placeholder — confirm with `lsblk` before running disko; on this
SATA drive it's very likely correct, but marvin may still enumerate it
differently depending on what else is attached at install time).

## `machines/marvin/hardware-configuration.nix` (new)

Same placeholder pattern as caixa's: imports
`(modulesPath + "/installer/scan/not-detected.nix")`, with a comment
instructing to replace it with the real output of
`nixos-generate-config --no-filesystems --show-hardware-config` run on
marvin itself.

## Secrets bootstrap (sops/age)

1. Generate a new age keypair for marvin (can be done anywhere, not
   necessarily on marvin) — save the private half to `keys/marvin-key.txt`
   (already gitignored).
2. Add the public half to `.sops.yaml`:
   ```yaml
   keys:
     - &caixa age1...
     - &marvin age1...   # new

   creation_rules:
     - path_regex: secrets/caixa\.yaml$
       key_groups:
         - age:
             - *caixa
     - path_regex: secrets/marvin\.yaml$
       key_groups:
         - age:
             - *marvin
   ```
3. `secrets/marvin.yaml` is **not created by this work** — it needs a real
   `henrique_password_hash` (from `mkpasswd -m sha-512`, run by hand), added
   via `sops secrets/marvin.yaml`. Document this in `secrets/README.md`
   alongside the existing caixa bootstrap section.
4. At install time: copy `keys/marvin-key.txt` to
   `/var/lib/sops-nix/key.txt` on marvin (root-only, `chmod 600`) before the
   first `nixos-rebuild switch`.

No `cloudflared_tunnel_token` needed — marvin has no cloudflared.

## SSH key

`users/henrique/default.nix` is shared across hosts and currently hardcodes
one `openssh.authorizedKeys.keys` entry labeled `henrique@caixa`. Add a
second placeholder entry:

```nix
openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNEELZAtcyd/g3y1gPjgSaxLlN5BZPilFzPTX6UTS2B henrique@caixa"
  "ssh-ed25519 PLACEHOLDER_REPLACE_WITH_REAL_KEY henrique@marvin"
];
```

To be replaced with the real public key once it's generated for/on marvin.

## Testing

This is declarative host config with no build machine available yet (marvin
doesn't physically exist as a NixOS install). Verification is limited to:

- `nix flake check` (or at minimum evaluating `nixosConfigurations.marvin.config.system.build.toplevel` with `nix eval`/`nix build --dry-run`) to confirm the configuration evaluates without errors, given the placeholders.
- Manual review diffing marvin's final `configuration.nix` against caixa's to confirm the only intentional deltas are the ones listed above.

Real hardware verification (disko run, NVIDIA driver load, Steam launch)
happens during actual install, outside this repo work.
