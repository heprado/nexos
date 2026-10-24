{ ... }:
{
  # Root on ZFS (pool `zroot`, see disko-config.nix), natively encrypted.
  imports = [ ../../modules/nixos/plymouth-tama ];

  boot.supportedFilesystems = [ "zfs" ];
  # Required by ZFS: pools remember the host that imported them. Any fixed
  # 8-hex-digit value; just don't change it once the pool exists.
  networking.hostId = "16ac98b4";
  boot.zfs.forceImportRoot = false;

  # The passphrase prompt goes through systemd-ask-password, which Plymouth
  # draws. That needs systemd in the initrd, now the only initrd nixpkgs
  # has (the scripted one, which prompted on the console hidden behind the
  # splash, was removed).
  boot.zfs.requestEncryptionCredentials = true;

  # Plymouth needs the iGPU's DRM driver up in the initrd (Skylake HD 530,
  # i915), or it falls back to text mode.
  boot.initrd.kernelModules = [ "i915" ];

  # ARC would otherwise take up to half of the <=8 GB, competing with k3s.
  boot.kernelParams = [ "zfs.zfs_arc_max=2147483648" ];

  services.zfs = {
    autoScrub.enable = true;
    # autotrim is on in the pool already; this is the periodic full pass.
    trim.enable = true;
  };
}
