{ config, lib, pkgs, ... }:
let
  cfg = config.nexos.takeMonitor;

  runtimeInputs = with pkgs; [ ddcutil coreutils gnugrep gawk ];

  takeMonitor = pkgs.writeShellScript "take-monitor" ''
    export PATH=${lib.makeBinPath runtimeInputs}
    declare -A overrides=(${lib.concatStrings (lib.mapAttrsToList (serial: code:
      " [${lib.escapeShellArg serial}]=${lib.escapeShellArg code}") cfg.overrides)} )
    ${builtins.readFile ./take-monitor.sh}
  '';

  unit = {
    description = "Switch every DDC/CI monitor's input to this host";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = takeMonitor;
    };
  };
in
{
  # caixa and marvin share monitors (e.g. the ASUS VG278: caixa on
  # DisplayPort, marvin on HDMI). Whichever one boots takes every monitor
  # it's plugged into over, instead of the monitors' auto input detection
  # sticking with the other host. See take-monitor.sh for how the input is
  # picked.
  options.nexos.takeMonitor = {
    enable = lib.mkEnableOption "switching every DDC/CI monitor to this host on boot";
    overrides = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { "M3LMQS291655" = "0x12"; };
      description = ''
        Monitor serial (as `ddcutil detect` reports it) -> VCP 0x60 input code,
        for monitors with more than one input of the connector type this host
        uses (e.g. HDMI-1 and HDMI-2), where it can't be worked out.
      '';
    };
    initrd = lib.mkEnableOption ''
      also doing it from the initrd, as soon as the kernel's DRM/DDC is up,
      so the Plymouth splash is visible on the monitors too. The GPU drivers
      driving them must also be in boot.initrd.kernelModules
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
      # The script's own interpreter and tools too, not just the script.
      systemd.storePaths = [ takeMonitor pkgs.runtimeShellPackage ] ++ runtimeInputs;
      # Only wanted, not ordered before initrd.target, so it never holds up
      # boot; switch-root just stops it if it's still retrying.
      systemd.services.take-monitor = unit // {
        wantedBy = [ "initrd.target" ];
        after = [ "systemd-modules-load.service" ];
      };
    };
  };
}
