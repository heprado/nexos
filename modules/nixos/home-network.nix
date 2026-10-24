{ config, lib, pkgs, ... }:
let
  cfg = config.nexos.homeNetwork;
  nmcli = "${config.networking.networkmanager.package}/bin/nmcli";
  rules = proto: ports: ranges:
    lib.concatMapStrings (port: ''
      ip46tables -A nexos-home-in -i "$dev" -p ${proto} --dport ${toString port} -j nixos-fw-accept
    '') ports
    + lib.concatMapStrings (r: ''
      ip46tables -A nexos-home-in -i "$dev" -p ${proto} --dport ${toString r.from}:${toString r.to} -j nixos-fw-accept
    '') ranges;
in
{
  options.nexos.homeNetwork = {
    connections = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "b0efb593-69d3-47e9-915d-a293249fad3d" ];
      description = ''
        NetworkManager connection UUIDs that count as home. Matched by UUID,
        not SSID or subnet: another network with the same SSID is a
        different connection unless it also has the saved WPA key, and
        192.168.15.0/24 is just Vivo's default, on half the networks around.
      '';
    };
    allowedTCPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "TCP ports open only on an interface connected to a home connection.";
    };
    allowedUDPPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      description = "UDP ports open only on an interface connected to a home connection.";
    };
    allowedUDPPortRanges = lib.mkOption {
      type = lib.types.listOf (lib.types.attrsOf lib.types.port);
      default = [ ];
      description = "UDP port ranges ({ from, to }) open only at home.";
    };
  };

  config = lib.mkIf (cfg.connections != [ ]) {
    # Own chain, jumped to from the top of nixos-fw. Filled from whatever
    # NetworkManager has up when the firewall (re)starts; at boot that's
    # nothing yet, the dispatcher below reloads it once a connection is up.
    networking.firewall.extraCommands = ''
      ip46tables -N nexos-home-in 2>/dev/null || true
      ip46tables -F nexos-home-in
      ip46tables -I nixos-fw 1 -j nexos-home-in
      ${nmcli} -t -f UUID,DEVICE connection show --active 2>/dev/null |
        while IFS=: read -r uuid dev; do
          case "$uuid" in
            ${lib.concatStringsSep " | " cfg.connections}) ;;
            *) continue ;;
          esac
          [ -n "$dev" ] || continue
          ${rules "tcp" cfg.allowedTCPPorts [ ]}
          ${rules "udp" cfg.allowedUDPPorts cfg.allowedUDPPortRanges}
        done
    '';

    networking.firewall.extraStopCommands = ''
      ip46tables -F nexos-home-in 2>/dev/null || true
    '';

    networking.networkmanager.dispatcherScripts = [
      {
        type = "basic";
        source = pkgs.writeShellScript "nexos-home-network-refresh" ''
          case "$2" in
            up | down)
              ${config.systemd.package}/bin/systemctl --no-block reload firewall.service ;;
          esac
        '';
      }
    ];
  };
}
