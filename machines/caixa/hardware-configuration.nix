# Placeholder. Replace with the real file generated on caixa itself:
#
#   nixos-generate-config --root /mnt   (during install)
#   # or, on an already-installed system:
#   nixos-generate-config --show-hardware-config > machines/caixa/hardware-configuration.nix
#
# This stub only exists so the flake evaluates before that step is done.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
