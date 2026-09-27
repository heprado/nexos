# Placeholder. Replace hardware-specific bits (kernel modules, CPU
# microcode, etc.) with the real output of, on marvin itself:
#
#   nixos-generate-config --no-filesystems --show-hardware-config > machines/marvin/hardware-configuration.nix
#
# --no-filesystems is important: disko-config.nix (see disko.devices) is
# the source of truth for fileSystems/swapDevices, so a generated
# hardware-configuration.nix must not redefine them.
{ modulesPath, ... }:
{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];
}
