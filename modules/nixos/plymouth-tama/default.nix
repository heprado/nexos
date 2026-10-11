{ pkgs, ... }:
{
  # nixos-bgrt's spinning snowflake with Tama instead of the firmware logo,
  # see theme.nix. Its password dialog is what shows the disk passphrase
  # prompt (LUKS on marvin, ZFS native encryption on caixa).
  boot.plymouth = {
    enable = true;
    theme = "tama";
    themePackages = [ (pkgs.callPackage ./theme.nix { }) ];
  };
}
