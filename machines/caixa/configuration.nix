{ lib, pkgs, ... }:
{
  imports = [
    ./hardware-configuration.nix
    ./zfs.nix
    ../../modules/nixos/common.nix
    ../../modules/nixos/ssh.nix
    ../../modules/nixos/cloudflared.nix
    ../../modules/nixos/lan-isolation.nix
    ../../modules/nixos/k3s-lab.nix
    ../../modules/nixos/lab-console-https.nix
  ];

  networking.hostName = "caixa";

  # Terminal only: no desktop-hyprland.nix (no greeter, no graphical
  # session, no auto-login), just getty on the console and SSH from marvin
  # on the local network.

  # adb/fastboot for Android device debugging. Used to also need
  # programs.adb.enable + the adbusers group for udev permissions, but
  # systemd 258 grants uaccess to the device node automatically now, so
  # just the package is enough.
  environment.systemPackages = [ pkgs.android-tools pkgs.unzip];

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

  # Only marvin may reach caixa from the LAN (its Wi-Fi and Ethernet cards'
  # permanent MACs): SSH, which is local-network only (ssh.nix refuses it
  # through the tunnel), and the lab console on 443 (lab-console-https.nix).
  nexos.lanIsolation.trustedMacs = [ "80:38:fb:e0:7e:3c" "64:1c:67:e3:8d:38" ];

  sops.defaultSopsFile = ../../secrets/caixa.yaml;
  # caixa decrypts with its SSH host key (converted to age), generated on
  # the installer by install.sh, so no age key file is carried around.
  sops.age.keyFile = lib.mkForce null;

  # Bump to whatever release you actually install; do not change on upgrades.
  system.stateVersion = "24.05";
}
