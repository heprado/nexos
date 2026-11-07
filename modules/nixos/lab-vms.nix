{ inputs, ... }:
# Two lab servers, lab-a and lab-b, as KVM microVMs on caixa -- each with
# its own k3s, joined by the Linux bridge br-lab (10.78.0.0/24, the host at
# .1), so the lab can be split between them and its cables cross from one
# to the other. The VMs themselves and this host half live in
# ~/codigos/container_studies (vms/flake.nix, docs/dois-servidores.md).
#
# What the host half brings: kvm-intel + vhost_net, KSM, br-lab and the
# vm-* taps through systemd-networkd (NetworkManager is told to leave them),
# multicast snooping, ARP suppression and proxy ARP off on the bridge, and
# the VMs as microvm@lab-a / microvm@lab-b. They reach the internet through
# QEMU's user networking, not br-lab, so no NAT here. SSH into them from
# caixa: ssh root@10.78.0.11 / .12.
#
# And the LAN: the players' broadcast domain. caixa's address moves from
# eno1 to the bridge "lan" (eno1 its port), and each VM's lan0 tap (ln-*)
# goes on it too, so the VMs get addresses from the router's DHCP. The VMs
# drop the LAN themselves except marvin's MACs (vms/flake.nix), as
# lan-isolation.nix does here.
{
  imports = [ inputs.lab-vms.nixosModules.host ];

  labVms.lanBridge = "lan";

  # NetworkManager keeps owning the LAN, now through the bridge: its
  # dispatcher is what reloads lan-isolation.nix's rules when DHCP hands
  # out the address, and it keeps /etc/resolv.conf. The bridge wears eno1's
  # MAC and asks DHCP with it (client id 01:<MAC>, what eno1's automatic
  # connection sent), so the router sees the same client and caixa keeps
  # 192.168.15.171. Named "lan", not br-*: lan-isolation.nix skips br-*.
  # Declared, these two take eno1 over from the automatic connection.
  networking.networkmanager.ensureProfiles.profiles = {
    lan = {
      connection = {
        id = "lan";
        type = "bridge";
        interface-name = "lan";
        autoconnect = "true";
      };
      ethernet.cloned-mac-address = "50:b3:63:00:56:3d";
      # A port forwards at once (no STP listening delay: nothing loops
      # here), and multicast floods to the VMs like broadcast does.
      bridge = {
        stp = "false";
        multicast-snooping = "false";
      };
      ipv4 = {
        method = "auto";
        dhcp-client-id = "mac";
      };
      ipv6.method = "auto";
    };
    lan-eno1 = {
      connection = {
        id = "lan-eno1";
        type = "ethernet";
        interface-name = "eno1";
        controller = "lan";
        port-type = "bridge";
        autoconnect = "true";
      };
    };
  };
}
