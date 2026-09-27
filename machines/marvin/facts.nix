# Hardware facts only knowable on marvin itself. Written by
# machines/marvin/install.sh on 2026-09-27 -- rerun it rather than editing.
{
  # Disk disko formats (everything on it is wiped).
  disk = "/dev/disk/by-id/ata-WD_Green_SATA_SSD_2.5_1TB_25272LD01445";

  # PRIME offload bus IDs, NixOS format (decimal "PCI:bus:device:function").
  intelBusId = "PCI:0:2:0";
  nvidiaBusId = "PCI:1:0:0";
}
