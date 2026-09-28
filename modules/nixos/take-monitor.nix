{ config, lib, pkgs, ... }:
let
  cfg = config.nexos.takeMonitor;

  # Switches the shared monitor's input (DDC/CI VCP 0x60) to this host, but
  # only if it isn't already there, since re-selecting the current input can
  # make the monitor blank and resync. Retries because right after boot the
  # GPU's DDC bus may not be up yet, and because the monitor may still be
  # busy auto-scanning its other inputs.
  takeMonitor = pkgs.writeShellScript "take-monitor" ''
    for _ in $(${pkgs.coreutils}/bin/seq 20); do
      current=$(${pkgs.ddcutil}/bin/ddcutil --sn ${cfg.serial} --terse getvcp 60 2>/dev/null)
      if [[ $current == *" x${lib.removePrefix "0x" cfg.input}" ]]; then
        exit 0
      fi
      ${pkgs.ddcutil}/bin/ddcutil --sn ${cfg.serial} setvcp 60 ${cfg.input} && exit 0
      ${pkgs.coreutils}/bin/sleep 1
    done
    exit 1
  '';

  unit = {
    description = "Switch the shared monitor's input to this host";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = takeMonitor;
    };
  };
in
{
  # caixa and marvin share one monitor (caixa on DisplayPort, marvin on
  # HDMI). Whichever one boots takes the monitor over, instead of the
  # monitor's auto input detection sticking with the other one.
  options.nexos.takeMonitor = {
    enable = lib.mkEnableOption "switching the shared monitor to this host on boot";
    serial = lib.mkOption {
      type = lib.types.str;
      default = "M3LMQS291655"; # ASUS VG278
      description = "Monitor serial number, as `ddcutil detect` reports it.";
    };
    input = lib.mkOption {
      type = lib.types.str;
      example = "0x11";
      description = "VCP 0x60 input code this host is plugged into (`ddcutil capabilities`).";
    };
    initrd = lib.mkEnableOption ''
      also doing it from the initrd, as soon as the kernel's DRM/DDC is up,
      so the Plymouth splash is visible on the monitor too. The GPU driver
      driving the monitor must also be in boot.initrd.kernelModules
    '';
  };

  config = lib.mkIf cfg.enable {
    # hardware.i2c (desktop-hyprland.nix) already loads i2c-dev in the
    # booted system.
    systemd.services.take-monitor = unit // {
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-modules-load.service" ];
    };

    boot.initrd = lib.mkIf cfg.initrd {
      kernelModules = [ "i2c-dev" ];
      # The script's own interpreter and coreutils too, not just ddcutil.
      systemd.storePaths = [ takeMonitor pkgs.runtimeShellPackage pkgs.coreutils pkgs.ddcutil ];
      # Only wanted, not ordered before initrd.target, so it never holds up
      # boot; switch-root just stops it if it's still retrying.
      systemd.services.take-monitor = unit // {
        wantedBy = [ "initrd.target" ];
        after = [ "systemd-modules-load.service" ];
      };
    };
  };
}
