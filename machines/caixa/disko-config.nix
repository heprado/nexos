{ ... }:
let
  facts = import ./facts.nix;
in
{
  # Same disk and layout as before (ESP + everything else), with the
  # "everything else" now a ZFS pool instead of LUKS + btrfs, so more disks
  # can join it later as an array: `zpool attach zroot <this> <new>` turns
  # the single disk into a mirror, `zpool add` stripes a new vdev in.
  # (Prefer /dev/disk/by-id paths for any disk added later.)
  #
  # Encryption is ZFS's own (aes-256-gcm, passphrase) on the pool's root
  # dataset, so every dataset -- and every disk added to the pool -- is
  # covered. The passphrase is asked once at boot, through Plymouth (see
  # zfs.nix next to this file).
  disko.devices = {
    disk.main = {
      type = "disk";
      # Picked by install.sh and recorded in facts.nix. Everything on this
      # disk will be wiped.
      device = facts.disk;
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          # Swap outside ZFS: a zvol can deadlock under the very memory
          # pressure swap is for. Re-keyed randomly on every boot, so
          # nothing written there outlives a reboot (no hibernation).
          swap = {
            size = "8G";
            content = {
              type = "swap";
              randomEncryption = true;
            };
          };
          zfs = {
            size = "100%";
            content = {
              type = "zfs";
              pool = "zroot";
            };
          };
        };
      };
    };

    zpool.zroot = {
      type = "zpool";
      options = {
        ashift = "12";
        autotrim = "on";
      };
      rootFsOptions = {
        mountpoint = "none";
        compression = "zstd";
        atime = "off";
        acltype = "posixacl";
        xattr = "sa";
        dnodesize = "auto";
        normalization = "formD";
        encryption = "aes-256-gcm";
        keyformat = "passphrase";
        # disko asks for the passphrase when it creates the pool; at boot
        # the initrd asks again.
        keylocation = "prompt";
        "com.sun:auto-snapshot" = "false";
      };
      datasets = {
        root = {
          type = "zfs_fs";
          mountpoint = "/";
        };
        nix = {
          type = "zfs_fs";
          mountpoint = "/nix";
        };
        home = {
          type = "zfs_fs";
          mountpoint = "/home";
          options."com.sun:auto-snapshot" = "true";
        };
        # Databases: 8K records matched to their 8 KB pages. With the
        # pool's 128K, each random page read/write moves a whole 128K
        # record -- measured at about -68% IOPS against 8K records here
        # (and 8K records cost ~-74% on large sequential reads, which is
        # why it's only this dataset). k3s' `db` StorageClass provisions
        # under /var/lib/db/k3s (modules/nixos/k3s-local-storage.yaml).
        db = {
          type = "zfs_fs";
          mountpoint = "/var/lib/db";
          options = {
            recordsize = "8K";
            "com.sun:auto-snapshot" = "true";
          };
        };
        # k3s' own datastore (SQLite through kine on a single server; it'd
        # be etcd only with --cluster-init). Its own dataset so the cluster
        # state can be snapshotted/rolled back on its own. recordsize stays
        # the pool's 128K, measured against 8K and 4K under its load (4 KB
        # writes, fdatasync each): sync writes land in the ZIL first, so the
        # median latency was identical (1.35 ms) and throughput within 6%,
        # but p99 grew as records shrank (3.7 / 4.4 / 4.7 ms). btrfs+LUKS2
        # on the same load: 3.7 ms median, 7.8 ms p99.
        k3s-db = {
          type = "zfs_fs";
          mountpoint = "/var/lib/rancher/k3s/server/db";
          options."com.sun:auto-snapshot" = "true";
        };
        # Never mounted: 1G held back so a full pool can still delete
        # files (ZFS is copy-on-write, deleting needs free space too).
        # `zfs set refreservation=none zroot/reserved` to get it back.
        reserved = {
          type = "zfs_fs";
          options = {
            mountpoint = "none";
            refreservation = "1G";
          };
        };
      };
    };
  };
}
