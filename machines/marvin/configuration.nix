{ config, lib, pkgs, inputs, ... }:
let
  facts = import ./facts.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/refind.nix
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  networking.hostName = "marvin";

  # unar: free RAR (incl. RAR5) extractor, unlike unfree unrar.
  # sbctl: manages marvin's Secure Boot keys (see boot.lanzaboote below).
  environment.systemPackages = [ pkgs.unzip pkgs.unar pkgs.sbctl ];

  # Lives here (not hardware-configuration.nix) since that file gets
  # wholesale-replaced by `nixos-generate-config` output during install,
  # which would silently drop bootloader config if it lived there.
  #
  # Secure Boot via lanzaboote: it still installs systemd-boot, but signs it
  # and each generation's UKI with the keys in pkiBundle, so the NixOS
  # module's own systemd-boot installer has to be off. The other
  # systemd-boot options (common.nix's consoleMode) are still read by
  # lanzaboote, into its loader.conf. Keys are created and enrolled by hand
  # (`sbctl create-keys`, then `sbctl enroll-keys --append --microsoft`
  # with the firmware in Setup Mode): appending keeps the db/KEK/dbx
  # Windows Update had installed, Microsoft's keys keep Windows' boot
  # manager and the NVIDIA GOP option ROM trusted.
  boot.loader.systemd-boot.enable = false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    # The ESP is only 512M and each initrd is ~210M (the NVIDIA module and
    # its GSP firmware are in it, see boot.initrd.kernelModules below), so
    # only two distinct kernel+initrd pairs fit.
    configurationLimit = 2;
  };

  # First boot menu: NixOS (-> systemd-boot's generation list) or Windows,
  # whose boot manager lives on the NVMe's own ESP.
  nexos.refind = {
    enable = true;
    windowsEsp = "ee46a2aa-aa95-4890-be73-2e631ebe70fa";
  };

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
    initrd = true;
  };

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

  # The proprietary driver above (see modules/nixos/unfree.nix).
  nexos.unfree = [ "nvidia-x11" "nvidia-kernel-modules" "nvidia-settings" "nvidia-persistenced" ];

  # Quickshell's own CLI (`qs`), for running shell configs by hand.
  # Noctalia bundles Quickshell but doesn't put it on PATH.
  home-manager.users.henrique.home.packages = [ pkgs.quickshell ];

  sops.defaultSopsFile = ../../secrets/marvin.yaml;

  # Bump to whatever release you actually install; do not change on upgrades.
  system.stateVersion = "24.05";
}
