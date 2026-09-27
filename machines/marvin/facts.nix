# Hardware facts only knowable on marvin itself. Rewritten by
# machines/marvin/install.sh at install time -- no need to edit by hand;
# the values below are just the expected defaults.
{
  # Disk disko formats (everything on it is wiped). install.sh writes a
  # stable /dev/disk/by-id/... path here, not /dev/sdX.
  disk = "/dev/sda";

  # PRIME offload bus IDs, NixOS format (decimal "PCI:bus:device:function").
  intelBusId = "PCI:0:2:0";
  nvidiaBusId = "PCI:1:0:0";
}
