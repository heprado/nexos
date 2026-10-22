{ config, pkgs, ... }:
# Single-node k3s for the network/SAN lab in ~/codigos/container_studies
# (clabernetes topologies + an iSCSI "SAN" reached through the lab fabric).
# Only the host-side half lives here -- the cluster workloads, manifests
# and client tooling (kubectl, helm, k9s, ...) are in that repo's devenv.
#
# Trimmed for a <=8 GB box: traefik and servicelb (klipper-lb) are off,
# local-path-provisioner and metrics-server stay (PVs and `kubectl top` are
# part of what the lab is meant to show). StorageClasses: `local-path`
# (default) and `db`, the latter on caixa's zroot/db dataset (8K records).
#
# Heads-up: the kubeconfig is cluster-admin, and clabernetes device Pods are
# privileged -- being in the `kube` group is effectively root on caixa.
let
  # Host end of the lab's `host:san0` link (see container_studies'
  # topologies/san-lab.yaml): a veth that only exists while the leaf1 Pod
  # is up. The rest of the lab's address plan (10.77.0.0/16) is routed
  # through leaf1 on the other end.
  sanIface = "san0";
  sanAddr = "10.77.0.1/30";
  sanGateway = "10.77.0.2";
  sanNet = "10.77.0.0/16";
in
{
  services.k3s = {
    enable = true;
    role = "server";
    # local-storage comes back as our own copy (manifests below), with a
    # second StorageClass for databases.
    disable = [ "traefik" "servicelb" "local-storage" ];
    manifests.lab-local-storage.source = ./k3s-local-storage.yaml;
    extraFlags = [
      "--write-kubeconfig-mode=0640"
      "--write-kubeconfig-group=kube"
      # NodePorts (lab console 30880, registry 30500) on loopback only:
      # from outside, the lab is the console's WebSocket behind nginx on
      # 443 (lab-console-https.nix). lan-isolation.nix drops LAN traffic
      # to the NodePort range as well.
      "--kube-proxy-arg=nodeport-addresses=127.0.0.1/32"
    ];
  };

  # The lab's own images (lab-console) are pushed by the repo's devenv to a
  # registry running inside the cluster, published as NodePort 30500 --
  # plain HTTP on loopback, so containerd needs to be told not to use TLS.
  environment.etc."rancher/k3s/registries.yaml".text = ''
    mirrors:
      "127.0.0.1:30500":
        endpoint:
          - "http://127.0.0.1:30500"
  '';
  systemd.services.k3s.restartTriggers = [
    config.environment.etc."rancher/k3s/registries.yaml".source
  ];

  users.groups.kube = { };
  users.users.henrique.extraGroups = [ "kube" ];

  # kubelet's in-tree `iscsi` volume plugin shells out to iscsiadm, mkfs
  # and blkid by name; k3s.service's PATH has none of them on NixOS.
  systemd.services.k3s.path = [ pkgs.openiscsi pkgs.e2fsprogs pkgs.util-linux ];

  services.openiscsi = {
    enable = true;
    name = "iqn.2026-10.lab.caixa:initiator";
  };

  # Pods reach the API server (and the kubelet reaches them) through cni0;
  # without this the host firewall drops them. Lab-only traffic, so the
  # bridge is trusted as a whole. lan-isolation.nix skips these interfaces
  # already (no default route on them).
  networking.firewall.trustedInterfaces = [ "cni0" "flannel.1" ];

  # Keep NetworkManager off everything k3s/clabernetes creates, it would
  # otherwise try DHCP on them.
  networking.networkmanager.unmanaged = [
    "interface-name:cni0"
    "interface-name:flannel*"
    "interface-name:veth*"
    "interface-name:${sanIface}"
  ];

  # Address + route for the SAN link, applied whenever the veth shows up
  # (lab deployed / leaf1 Pod recreated) and gone with it.
  systemd.services."lab-${sanIface}" = {
    description = "Configure the k3s lab SAN link (${sanIface})";
    bindsTo = [ "sys-subsystem-net-devices-${sanIface}.device" ];
    after = [ "sys-subsystem-net-devices-${sanIface}.device" ];
    wantedBy = [ "sys-subsystem-net-devices-${sanIface}.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [ pkgs.iproute2 ];
    script = ''
      ip link set ${sanIface} up
      ip addr replace ${sanAddr} dev ${sanIface}
      ip route replace ${sanNet} via ${sanGateway} dev ${sanIface}
    '';
  };

  environment.systemPackages = [ pkgs.openiscsi ];
}
