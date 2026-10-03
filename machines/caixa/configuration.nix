{ pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    ../../modules/nixos/cloudflared.nix
    ../../modules/nixos/lan-isolation.nix
    ../../modules/nixos/wayvnc-hyprland.nix
    ../../modules/nixos/novnc-hyprland.nix
  ];

  networking.hostName = "caixa";

  # adb/fastboot for Android device debugging. Used to also need
  # programs.adb.enable + the adbusers group for udev permissions, but
  # systemd 258 grants uaccess to the device node automatically now, so
  # just the package is enough.
  environment.systemPackages = [ pkgs.android-tools pkgs.unzip];

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

  # Mininet (used by ~/codigos/p4-tutorials' devenv, studying P4) needs
  # this to let the virtual hosts it creates route/forward packets between
  # each other.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  # Lives here (not hardware-configuration.nix) since that file gets
  # wholesale-replaced by `nixos-generate-config` output during install,
  # which would silently drop bootloader config if it lived there.
  boot.loader.systemd-boot.enable = true;

  # AHCI defaults the root SSD's SATA link to the aggressive
  # "mobile"/med_power_with_dipm power policy, which this Silicon
  # Motion-based drive can't reliably wake from -- the link freezes
  # (dmesg: "ata1.00: exception ... SErr { CommWake DevExch }") and
  # gets hard-reset, sometimes mid-write, which can force btrfs to
  # remount read-only. max_performance (1) disables that LPM state.
  boot.kernelParams = [ "ahci.mobile_lpm_policy=1" ];

  sops.defaultSopsFile = ../../secrets/caixa.yaml;

  # Bump to whatever release you actually install; do not change on upgrades.
  system.stateVersion = "24.05";
}
