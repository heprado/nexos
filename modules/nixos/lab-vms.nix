{ inputs, ... }:
# Two lab servers, lab-a and lab-b, as KVM microVMs on caixa -- each with
# its own k3s, joined by the Linux bridge br-lab (10.78.0.0/24, the host at
# .1), so the lab can be split between them and its cables cross from one
# to the other. The VMs themselves and this host half live in
# ~/codigos/container_studies (vms/flake.nix, docs/proposta-sincronizacao.md);
# here is only the import.
#
# What the host half brings: kvm-intel + vhost_net, KSM, br-lab and the
# vm-* taps through systemd-networkd (NetworkManager is told to leave them;
# eno1 is untouched), multicast snooping, ARP suppression and proxy ARP
# off on the bridge, and the VMs as microvm@lab-a / microvm@lab-b.
# They reach the internet through QEMU's user networking, not br-lab, so
# no NAT here. SSH into them from caixa: ssh root@10.78.0.11 / .12.
{
  imports = [ inputs.lab-vms.nixosModules.host ];
}
