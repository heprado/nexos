{ config, lib, pkgs, ... }:
let
  cfg = config.nexos.refind;
  esp = config.boot.loader.efi.efiSysMountPoint;

  # Only the two entries below are shown (scanfor manual). The icon lines
  # come before volume on purpose: rEFInd loads an icon from whatever
  # volume the stanza points at so far, which is its own ESP until then.
  refindConf = pkgs.writeText "refind.conf" ''
    timeout ${toString cfg.timeout}
    scanfor manual
    default_selection "NixOS"
    # No editing the loaders' options from the menu at boot.
    hideui hints,editor
    showtools reboot,shutdown,firmware

    menuentry "NixOS" {
      icon /EFI/refind/icons/os_linux.png
      loader /EFI/systemd/systemd-bootx64.efi
    }

    menuentry "Windows" {
      icon /EFI/refind/icons/os_win.png
      volume ${cfg.windowsEsp}
      loader /EFI/Microsoft/Boot/bootmgfw.efi
    }
  '';

  installRefind = pkgs.writeShellScript "install-refind" ''
    set -euo pipefail
    export PATH=${lib.makeBinPath (with pkgs; [ coreutils gnugrep util-linux efibootmgr sbctl ])}

    dir=${esp}/EFI/refind
    stamp=$dir/.installed-from
    want="${pkgs.refind} ${refindConf}"

    # Only touch the ESP when rEFInd or its config actually changed.
    if [[ "$(cat "$stamp" 2>/dev/null)" != "$want" ]]; then
      mkdir -p "$dir"
      rm -rf "$dir/icons"
      cp -r --no-preserve=mode ${pkgs.refind}/share/refind/icons "$dir/icons"
      cp --no-preserve=mode ${refindConf} "$dir/refind.conf"
      # Signed with the same db key lanzaboote uses, so the firmware runs
      # it with Secure Boot on.
      sbctl sign -o "$dir/refind_x64.efi" ${pkgs.refind}/share/refind/refind_x64.efi
      echo "$want" > "$stamp"
    fi

    # Created once; efibootmgr puts a new entry first in BootOrder. Not
    # forced back to first afterwards, so reordering it in the firmware
    # setup sticks. lanzaboote never touches the boot entries.
    if ! efibootmgr | grep -qi 'refind_x64\.efi'; then
      src=$(findmnt -no SOURCE ${esp})
      efibootmgr --quiet --create \
        --disk "/dev/$(lsblk -no PKNAME "$src")" \
        --part "$(cat "/sys/class/block/$(basename "$src")/partition")" \
        --loader '\EFI\refind\refind_x64.efi' --label rEFInd
    fi
  '';
in
{
  # A first menu that only picks the OS: "NixOS" chainloads lanzaboote's
  # systemd-boot (which then lists the generations) and "Windows" its boot
  # manager on another disk's ESP, which systemd-boot can't reach.
  options.nexos.refind = {
    enable = lib.mkEnableOption "rEFInd as an OS picker in front of systemd-boot";
    windowsEsp = lib.mkOption {
      type = lib.types.str;
      example = "ee46a2aa-aa95-4890-be73-2e631ebe70fa";
      description = "PARTUUID of the ESP holding Windows' boot manager (`lsblk -o NAME,PARTUUID`).";
    };
    timeout = lib.mkOption {
      type = lib.types.int;
      default = 5;
      description = "Seconds before rEFInd boots NixOS on its own.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [{
      assertion = config.boot.lanzaboote.enable;
      message = "nexos.refind signs rEFInd with lanzaboote's sbctl keys, so it needs boot.lanzaboote.enable.";
    }];

    # A service rather than an activation script: those also run early in
    # stage 2, before the ESP is mounted. RemainAfterExit makes a rebuild
    # rerun it whenever the script (i.e. rEFInd or its config) changes.
    systemd.services.install-refind = {
      description = "Install and sign rEFInd on the ESP";
      wantedBy = [ "multi-user.target" ];
      unitConfig.RequiresMountsFor = esp;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = installRefind;
      };
    };
  };
}
