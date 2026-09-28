{ config, lib, pkgs, inputs, self, ... }:
let
  facts = import ./facts.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/docker-rootless.nix
    ../../modules/nixos/ssh.nix
    ../../modules/nixos/desktop-hyprland.nix
    ../../modules/nixos/chrony.nix
    ../../modules/nixos/session-stop-timeout.nix
    ../../modules/nixos/take-monitor.nix
    ../../modules/nixos/lan-isolation.nix
    ../../modules/nixos/gaming.nix
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

  networking.hostName = "marvin";
  programs.zsh.enable = true;

  # `nh clean` runs as a periodic systemd service, and `nh os switch`/etc.
  # (see the `nrs`-style aliases in modules/home/zsh.nix) know which flake
  # to build via NH_OS_FLAKE, set from `flake` below.
  programs.nh = {
    enable = true;
    clean.enable = true;
    clean.extraArgs = "--keep-since 4d --keep 3";
    flake = "/home/henrique/codigos/nexos";
  };

  i18n.defaultLocale = "pt_BR.UTF-8";
  time.timeZone = "America/Sao_Paulo";

  # Backend dconf needs to actually apply GTK theme settings (see
  # modules/home/hyprland.nix's dconf.settings for henrique's GTK theme).
  programs.dconf.enable = true;

  nixpkgs.overlays = [ inputs.helium-flake.overlays.default ];

  # Lives here (not hardware-configuration.nix) since that file gets
  # wholesale-replaced by `nixos-generate-config` output during install,
  # which would silently drop bootloader config if it lived there.
  boot.loader.systemd-boot.enable = true;
  # The default ("keep") reuses whatever console mode the firmware left
  # set up, which on marvin is the laptop panel only. Windows' boot manager
  # did show up on the HDMI monitor (NVIDIA-wired) too, so asking for a mode
  # explicitly is an attempt to get the firmware to set it on every console
  # it knows about. Unverified; revert to the default if it doesn't help.
  boot.loader.systemd-boot.consoleMode = "auto";
  boot.loader.efi.canTouchEfiVariables = true;

  # Boot splash: the firmware's own logo (BGRT, Lenovo's) with a spinning
  # NixOS snowflake under it. The firmware only ever lights up the laptop
  # panel, so the menu above can't reach the HDMI monitor; Plymouth runs
  # after the kernel's DRM drivers are up, so it can. The HDMI port is
  # wired to NVIDIA, so its driver (not just i915) is loaded early in the
  # initrd for Plymouth to see that output too.
  boot.plymouth = {
    enable = true;
    theme = "nixos-bgrt";
    themePackages = [ pkgs.nixos-bgrt-plymouth ];
  };
  boot.initrd.kernelModules = [ "i915" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

  # The shared monitor sees no HDMI signal until nvidia-drm is up (~4s in),
  # so its auto input detection wanders off to caixa's DisplayPort. Pull it
  # back from the initrd, where nvidia-drm is already loaded (see above), so
  # the Plymouth splash shows up there as well.
  nexos.takeMonitor = {
    enable = true;
    input = "0x11"; # HDMI-1
    initrd = true;
  };

  # Unset, this falls back to nixpkgs' own default kernel package set,
  # which tracks an older/more conservative version (6.18) even on
  # nixpkgs-unstable -- linuxPackages_latest is what actually follows the
  # newest kernel release packaged for this channel.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # GPU: NVIDIA GTX 1650 (Turing/TU117) + Intel UHD (Comet Lake-H) hybrid
  # graphics, PRIME offload -- Intel iGPU stays the default renderer
  # (battery-friendly), NVIDIA is available on demand for games.
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
      # Detected by install.sh and recorded in facts.nix.
      inherit (facts) intelBusId nvidiaBusId;
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  # Hyprland itself renders on the NVIDIA GPU, even though apps still
  # default to Intel (PRIME offload above). The HDMI port is wired to the
  # NVIDIA card, so with Intel as the compositor's renderer every HDMI frame
  # (1080p@120Hz) had to be copied across GPUs, which made animations crawl
  # there. Aquamarine uses the first device in AQ_DRM_DEVICES as its
  # renderer. The cardN numbers aren't stable across boots, and by-path
  # names contain ':' (AQ_DRM_DEVICES' separator), so udev gives each GPU a
  # fixed symlink keyed on its PCI address from facts.nix. ID_PATH is
  # matched exactly so the early-boot simple-framebuffer card (which also
  # sits under the Intel PCI device) doesn't claim the Intel name.
  services.udev.extraRules =
    let
      # "PCI:1:0:0" (decimal, NixOS format) -> "pci-0000:01:00.0" (hex, udev ID_PATH).
      idPath = busId:
        let
          hex2 = n: lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString (lib.toInt n)));
          parts = lib.splitString ":" busId;
        in
        "pci-0000:${hex2 (lib.elemAt parts 1)}:${hex2 (lib.elemAt parts 2)}.${lib.elemAt parts 3}";
    in
    ''
      SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ENV{ID_PATH}=="${idPath facts.nvidiaBusId}", SYMLINK+="dri/nvidia-dgpu"
      SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ENV{ID_PATH}=="${idPath facts.intelBusId}", SYMLINK+="dri/intel-igpu"
    '';
  environment.sessionVariables.AQ_DRM_DEVICES = "/dev/dri/nvidia-dgpu:/dev/dri/intel-igpu";

  # claude-code's license is marked "unfree" in nixpkgs; allow just that
  # package rather than unfree packages in general. nvidia-* are needed
  # for the proprietary driver above, steam* and the libretro-* cores
  # (non-commercial licenses, pulled in by retroarch-full) for
  # modules/nixos/gaming.nix.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "claude-code" "discord" "discord-unwrapped" "citrix-workspace" "linuxx64"
      "nvidia-x11" "nvidia-kernel-modules" "nvidia-settings" "nvidia-persistenced"
      "steam" "steam-unwrapped" "steam-original" "steam-run"
      "libretro-fbalpha2012" "libretro-fbneo" "libretro-fmsx"
      "libretro-genesis-plus-gx" "libretro-mame2000" "libretro-mame2003"
      "libretro-mame2003-plus" "libretro-mame2010" "libretro-mame2015"
      "libretro-opera" "libretro-picodrive" "libretro-snes9x"
      "libretro-snes9x2002" "libretro-snes9x2005" "libretro-snes9x2005-plus"
      "libretro-snes9x2010"
    ];

  home-manager.users.henrique = import ../../users/henrique/home.nix;

  sops.defaultSopsFile = ../../secrets/marvin.yaml;
  # Generate on marvin with `age-keygen`, then record the public key in
  # .sops.yaml at the repo root as marvin's recipient. See secrets/README.md.
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  # Bump to whatever release you actually install; do not change on upgrades.
  system.stateVersion = "24.05";
}
