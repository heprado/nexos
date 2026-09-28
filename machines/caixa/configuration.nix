{ lib, pkgs, inputs, self, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/docker-rootless.nix
    ../../modules/nixos/cloudflared.nix
    ../../modules/nixos/ssh.nix
    ../../modules/nixos/desktop-hyprland.nix
    ../../modules/nixos/chrony.nix
    ../../modules/nixos/session-stop-timeout.nix
    ../../modules/nixos/take-monitor.nix
    ../../modules/nixos/wayvnc-hyprland.nix
    ../../modules/nixos/novnc-hyprland.nix
    ../../modules/nixos/lan-isolation.nix
    ../../users/henrique
  ];

  # Noctalia isn't in the official nixpkgs cache; without this, its
  # Quickshell/Qt dependencies get compiled from source on every rebuild.
  nix.settings = {
    extra-substituters = [ "https://noctalia.cachix.org" ];
    extra-trusted-public-keys = [ "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4=" ];
    # So `nix flake ...`/`nix build ...` etc. work without having to pass
    # --extra-experimental-features "nix-command flakes" every time.
    experimental-features = [ "nix-command" "flakes" ];
  };

  # Short alias for this flake itself, so the per-language devShell
  # templates (see flake.nix's `templates` output) can be pulled with
  # `nix flake init -t nexos#rust` instead of the full repo path.
  nix.registry.nexos.flake = self;

  networking.hostName = "caixa";
  programs.zsh.enable = true;

  # adb/fastboot for Android device debugging. Used to also need
  # programs.adb.enable + the adbusers group for udev permissions, but
  # systemd 258 grants uaccess to the device node automatically now, so
  # just the package is enough.
  environment.systemPackages = [ pkgs.android-tools pkgs.unzip];

  # `nh clean` runs as a periodic systemd service, and `nh os switch`/etc.
  # (see the `nrs`-style aliases in modules/home/zsh.nix) know which flake
  # to build via NH_OS_FLAKE, set from `flake` below.
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/henrique/codigos/nexos";
  };

  # caixa's iGPU is a Skylake HD Graphics 530 (i915). intel-media-driver
  # (iHD) is the modern VAAPI driver for Gen9+ Intel iGPUs -- the legacy
  # i965 driver mesa falls back to otherwise doesn't support this
  # generation well. Vulkan (needed for WebGPU in Helium, see
  # modules/home/helium.nix) comes for free from hardware.graphics.enable
  # via mesa's ANV driver, no extra package required.
  hardware.graphics = {
    enable = true;
    extraPackages = [ pkgs.intel-media-driver ];
  };
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  # Monitors shared with marvin: take them over on boot.
  nexos.takeMonitor.enable = true;

  i18n.defaultLocale = "pt_BR.UTF-8";
  time.timeZone = "America/Sao_Paulo";

  # Mininet (used by ~/codigos/p4-tutorials' devenv, studying P4) needs
  # this to let the virtual hosts it creates route/forward packets between
  # each other.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # Backend dconf needs to actually apply GTK theme settings (see
  # modules/home/hyprland.nix's dconf.settings for henrique's GTK theme).
  programs.dconf.enable = true;

  nixpkgs.overlays = [ inputs.helium-flake.overlays.default ];

  # Lives here (not hardware-configuration.nix) since that file gets
  # wholesale-replaced by `nixos-generate-config` output during install,
  # which would silently drop bootloader config if it lived there.
  boot.loader.systemd-boot.enable = true;
  # Asks the firmware for a console mode instead of reusing whatever it
  # left set up ("keep", the default), so the boot menu is set up on every
  # connected monitor rather than only the one the firmware picked. Same
  # as marvin.
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.efi.canTouchEfiVariables = true;

  # Unset, this falls back to nixpkgs' own default kernel package set,
  # which tracks an older/more conservative version (6.18) even on
  # nixpkgs-unstable -- linuxPackages_latest is what actually follows the
  # newest kernel release packaged for this channel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # AHCI defaults the root SSD's SATA link to the aggressive
  # "mobile"/med_power_with_dipm power policy, which this Silicon
  # Motion-based drive can't reliably wake from -- the link freezes
  # (dmesg: "ata1.00: exception ... SErr { CommWake DevExch }") and
  # gets hard-reset, sometimes mid-write, which can force btrfs to
  # remount read-only. max_performance (1) disables that LPM state.
  boot.kernelParams = [ "ahci.mobile_lpm_policy=1" ];

  # claude-code's license is marked "unfree" in nixpkgs; allow just that
  # package rather than unfree packages in general.
  #
  # citrix-workspace additionally requires the actual install tarball to be
  # downloaded by hand and registered in the store first (Citrix's EULA
  # forbids nixpkgs from fetching it directly) -- see the comment next to
  # pkgs.citrix-workspace in modules/home/hyprland.nix. "linuxx64" (not
  # "citrix-workspace") is the requireFile src derivation's own name --
  # lib.getName strips its version off "linuxx64-<ver>.tar.gz" -- so both
  # names need to be allowed.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" "discord" "discord-unwrapped" "citrix-workspace" "linuxx64" ];

  home-manager.users.henrique = import ../../users/henrique/home.nix;

  sops.defaultSopsFile = ../../secrets/caixa.yaml;
  # Generate on caixa with `age-keygen`, then record the public key in
  # .sops.yaml at the repo root as caixa's recipient. See secrets/README.md.
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  # Bump to whatever release you actually install; do not change on upgrades.
  system.stateVersion = "24.05";
}
