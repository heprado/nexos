{ pkgs, ... }:
{
  # Restricts every physical/LAN interface to "vertical" traffic only: the
  # default gateway (and, through it, the internet) is reachable, but
  # nothing else on the same local subnet is -- no lateral/peer traffic,
  # in either direction. Tailscale (tailscale0) and loopback are
  # deliberately excluded: Tailscale is peer-to-peer by design, and this
  # is how remote access to this host actually works.
  #
  # Interfaces and their gateway/subnet are discovered at firewall
  # (re)start time via `ip route`/`ip addr`, not hardcoded, since they're
  # DHCP-assigned and can change.
  networking.firewall.extraCommands = ''
    for ifpath in /sys/class/net/*; do
      iface="$(basename "$ifpath")"
      case "$iface" in
        lo|tailscale*|docker*|veth*|br-*|virbr*|wg*) continue ;;
      esac

      for spec in "4 iptables" "6 ip6tables"; do
        fam="''${spec%% *}"
        ipt="''${spec#* }"

        gw="$(${pkgs.iproute2}/bin/ip -''${fam} route show dev "$iface" default 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $3; exit}')"
        [ -z "$gw" ] && continue
        cidr="$(${pkgs.iproute2}/bin/ip -''${fam} -o addr show dev "$iface" scope global 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $4; exit}')"
        [ -z "$cidr" ] && continue

        # Inbound: allow the gateway, then drop the rest of the local subnet.
        # Appended into nixos-fw (not raw INPUT) so this runs before the
        # chain's own terminal reject, per the standard extraCommands pattern.
        "$ipt" -A nixos-fw -i "$iface" -s "$gw" -j nixos-fw-accept
        "$ipt" -A nixos-fw -i "$iface" -s "$cidr" -j nixos-fw-log-refuse

        # Outbound: nixos-fw only filters INPUT, so OUTPUT is untouched by
        # the rest of this module -- safe to manage entirely ourselves here.
        "$ipt" -A OUTPUT -o "$iface" -d "$gw" -j ACCEPT
        "$ipt" -A OUTPUT -o "$iface" -d "$cidr" -j DROP
      done
    done
  '';

  networking.firewall.extraStopCommands = ''
    for ifpath in /sys/class/net/*; do
      iface="$(basename "$ifpath")"
      case "$iface" in
        lo|tailscale*|docker*|veth*|br-*|virbr*|wg*) continue ;;
      esac

      for spec in "4 iptables" "6 ip6tables"; do
        fam="''${spec%% *}"
        ipt="''${spec#* }"

        gw="$(${pkgs.iproute2}/bin/ip -''${fam} route show dev "$iface" default 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $3; exit}')"
        [ -n "$gw" ] && "$ipt" -D OUTPUT -o "$iface" -d "$gw" -j ACCEPT 2>/dev/null || true
        cidr="$(${pkgs.iproute2}/bin/ip -''${fam} -o addr show dev "$iface" scope global 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $4; exit}')"
        [ -n "$cidr" ] && "$ipt" -D OUTPUT -o "$iface" -d "$cidr" -j DROP 2>/dev/null || true
      done
    done
  '';
}
