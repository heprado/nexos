{ config, lib, pkgs, ... }:
let
  sshMacs = config.nexos.lanIsolation.sshFromMacs;
  sshPorts = config.services.openssh.ports;
in
{
  options.nexos.lanIsolation.sshFromMacs = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "80:38:fb:e0:7e:3c" ];
    description = ''
      MAC addresses of LAN peers allowed to reach this host's SSH directly,
      the one exception to the isolation below. Matched by MAC rather than
      IP since peers get theirs from DHCP (and IPv6 privacy addresses
      rotate); it only works on the same L2 segment, which is the point.
      A MAC can be spoofed by anyone on the LAN, so SSH keys stay the
      actual gate.
    '';
  };

  config = {
    # Restricts every physical/LAN interface to "vertical" traffic only: the
    # default gateway (and, through it, the internet) is reachable, but
    # nothing else on the same local subnet is -- no lateral/peer traffic,
    # in either direction, not even to ports opened in allowedTCPPorts (SSH
    # included: from the LAN it's only reachable through the Cloudflare
    # Tunnel, like from anywhere else, except from the peers listed in
    # nexos.lanIsolation.sshFromMacs). Loopback is excluded since it's
    # needed for things like cloudflared forwarding to local services (see
    # cloudflared.nix) -- no interface-specific exception is needed for
    # that: cloudflared is outbound-only (egresses through the gateway,
    # already allowed below) and inbound traffic arrives already de-tunneled
    # over loopback, never as a new inbound connection on a physical/LAN
    # interface.
    #
    # Interfaces and their gateway/subnet are discovered at firewall
    # (re)start time via `ip route`/`ip addr`, not hardcoded, since they're
    # DHCP-assigned and can change.
    #
    # The rules live in their own chains, jumped to from the very top of
    # nixos-fw (INPUT) and OUTPUT. nixos-fw runs extraCommands only after its
    # own allowedTCPPorts/established accepts, so rules merely appended there
    # never saw traffic to an open port -- the LAN could still reach every
    # one of them. Own chains also make teardown independent of whatever the
    # gateway/subnet are by then.
    networking.firewall.extraCommands = ''
      for ipt in iptables ip6tables; do
        for chain in nexos-lan-in nexos-lan-out; do
          "$ipt" -N "$chain" 2>/dev/null || true
          "$ipt" -F "$chain"
        done
        # nixos-fw was just recreated from scratch, so this is its only jump
        # here; OUTPUT isn't, hence the delete first.
        "$ipt" -I nixos-fw 1 -j nexos-lan-in
        "$ipt" -D OUTPUT -j nexos-lan-out 2>/dev/null || true
        "$ipt" -I OUTPUT 1 -j nexos-lan-out
      done

      # IPv6 neighbor discovery (router/neighbor solicitation and
      # advertisement) stays allowed: without it the gateway can't resolve
      # this host's addresses at all. It never leaves the link.
      for ndp in 133 134 135 136; do
        ip6tables -A nexos-lan-in -p icmpv6 --icmpv6-type "$ndp" -j RETURN
        ip6tables -A nexos-lan-out -p icmpv6 --icmpv6-type "$ndp" -j RETURN
      done
      ${lib.optionalString (sshMacs != [ ]) ''

      # SSH from the listed peers. Ahead of the per-interface rules below,
      # which would refuse them as subnet peers; caixa's replies to them go
      # out as ESTABLISHED. Nothing else on the subnet ever gets a
      # connection established (it's refused or dropped first), so that
      # can't open anything more.
      for ipt in iptables ip6tables; do
        "$ipt" -A nexos-lan-out -m conntrack --ctstate ESTABLISHED -j RETURN
        ${lib.concatMapStrings (mac: lib.concatMapStrings (port: ''
          "$ipt" -A nexos-lan-in -p tcp --dport ${toString port} -m mac --mac-source ${lib.escapeShellArg mac} -j RETURN
        '') sshPorts) sshMacs}
      done
      ''}

      for ifpath in /sys/class/net/*; do
        iface="$(basename "$ifpath")"
        case "$iface" in
          lo|docker*|veth*|br-*|virbr*|wg*) continue ;;
        esac

        for spec in "4 iptables" "6 ip6tables"; do
          fam="''${spec%% *}"
          ipt="''${spec#* }"

          gw="$(${pkgs.iproute2}/bin/ip -''${fam} route show dev "$iface" default 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $3; exit}')"
          [ -z "$gw" ] && continue
          cidr="$(${pkgs.iproute2}/bin/ip -''${fam} -o addr show dev "$iface" scope global 2>/dev/null | ${pkgs.gawk}/bin/awk '{print $4; exit}')"
          [ -z "$cidr" ] && continue

          # The gateway passes on to the rest of nixos-fw (still subject to
          # its port rules); everyone else on the subnet is dropped. For IPv6
          # that includes link-local (fe80::/10) peers, not just the global
          # prefix -- the gateway itself is usually link-local there, which
          # the RETURN above already let through.
          "$ipt" -A nexos-lan-in -i "$iface" -s "$gw" -j RETURN
          "$ipt" -A nexos-lan-in -i "$iface" -s "$cidr" -j nixos-fw-log-refuse
          "$ipt" -A nexos-lan-out -o "$iface" -d "$gw" -j RETURN
          "$ipt" -A nexos-lan-out -o "$iface" -d "$cidr" -j DROP
          if [ "$fam" = 6 ]; then
            ip6tables -A nexos-lan-in -i "$iface" -s fe80::/10 -j nixos-fw-log-refuse
            ip6tables -A nexos-lan-out -o "$iface" -d fe80::/10 -j DROP
          fi
        done
      done
    '';

    # Runs on stop and before every reload's start. nexos-lan-in is still
    # referenced from nixos-fw here (start deletes that chain itself), so the
    # chains are only emptied, not deleted.
    networking.firewall.extraStopCommands = ''
      for ipt in iptables ip6tables; do
        "$ipt" -D OUTPUT -j nexos-lan-out 2>/dev/null || true
        "$ipt" -F nexos-lan-in 2>/dev/null || true
        "$ipt" -F nexos-lan-out 2>/dev/null || true
      done
    '';

    # The firewall starts before any interface has an address or a default
    # route, so at boot the loop above found nothing and the LAN went
    # unrestricted until something happened to reload the firewall. Redo
    # the rules whenever NetworkManager brings an interface up or down or
    # DHCP hands out a new lease.
    networking.networkmanager.dispatcherScripts = lib.mkIf config.networking.networkmanager.enable [
      {
        type = "basic";
        source = pkgs.writeShellScript "nexos-lan-isolation-refresh" ''
          case "$2" in
            up | down | dhcp4-change | dhcp6-change)
              ${config.systemd.package}/bin/systemctl --no-block reload firewall.service ;;
          esac
        '';
      }
    ];
  };
}
