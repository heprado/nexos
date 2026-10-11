{ config, lib, pkgs, ... }:
let
  dir = "/var/lib/lab-console-tls";
in
{
  # The lab console (container_studies' lab-console, a NodePort on
  # 127.0.0.1:30880) on https://<this host>/, so it opens from the LAN
  # without an SSH tunnel. Which LAN peers may reach 443 at all is
  # lan-isolation.nix's trustedMacs. The console has no login of its own:
  # whoever reaches this page gets the routers' consoles.
  #
  # Self-signed certificate, generated here on first start: the browser
  # warns once (accept it, or pin the fingerprint, printed by
  # `openssl x509 -noout -fingerprint -sha256 -in ${dir}/cert.pem`). Names:
  # the hostname, <hostname>.local and the IPs it had when generated -- the
  # LAN IP comes from DHCP, so delete ${dir} and restart nginx to reissue
  # after it changes.
  systemd.services.lab-console-cert = {
    description = "Self-signed certificate for the lab console";
    before = [ "nginx.service" ];
    requiredBy = [ "nginx.service" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.openssl pkgs.iproute2 pkgs.gawk ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      UMask = "0027";
    };
    script = ''
      [ -s ${dir}/cert.pem ] && exit 0
      install -d -m 0750 -o root -g nginx ${dir}
      host=${config.networking.hostName}
      san="DNS:$host,DNS:$host.local,DNS:localhost,IP:127.0.0.1"
      for ip in $(ip -o addr show scope global | awk '{ split($4, a, "/"); print a[1] }'); do
        san="$san,IP:$ip"
      done
      openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes \
        -days 3650 -subj "/CN=$host" -addext "subjectAltName=$san" \
        -keyout ${dir}/key.pem -out ${dir}/cert.pem
      # openssl writes the key 0600 whatever the umask; nginx reads it as its
      # own group.
      chgrp nginx ${dir}/key.pem ${dir}/cert.pem
      chmod 0640 ${dir}/key.pem ${dir}/cert.pem
    '';
  };

  services.nginx = {
    enable = true;
    recommendedTlsSettings = true;
    recommendedProxySettings = true;
    virtualHosts.lab-console = {
      default = true;
      onlySSL = true;
      sslCertificate = "${dir}/cert.pem";
      sslCertificateKey = "${dir}/key.pem";
      locations."/" = {
        proxyPass = "http://127.0.0.1:30880";
        # The serial consoles are WebSockets.
        proxyWebsockets = true;
        extraConfig = ''
          proxy_read_timeout 1h;
        '';
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 443 ];
  nexos.lanIsolation.trustedTcpPorts = [ 443 ];
}
