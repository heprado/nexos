{ lib, ... }:
let
  # Cloudflare's 1.1.1.2 ("for Families", malware blocking): their resolver,
  # which also refuses the malware/phishing domains they know of. The name
  # after # is what the TLS certificate is checked against.
  # resolved sticks to the first server that answers. 1.1.1.2 goes last:
  # from this network (2026-11) it doesn't answer at all, on any port --
  # 1.0.0.2 and the IPv6 ones do.
  cloudflare = map (ip: "${ip}#security.cloudflare-dns.com") [
    "1.0.0.2"
    "2606:4700:4700::1112"
    "2606:4700:4700::1002"
    "1.1.1.2"
  ];
in
{
  # Every DNS lookup goes to Cloudflare over TLS (DNS-over-TLS, port 853),
  # so neither the router nor the ISP sees the names looked up. /etc/hosts
  # (ad-block.nix) is still read first.
  #
  # Strict: if TLS to Cloudflare fails, lookups fail -- no plain-text
  # fallback. A captive portal (hotel/airport Wi-Fi login page) won't come
  # up like this; LAN names the router hands out (*.lan) don't resolve
  # either, though .local via mDNS (avahi) still does.
  networking.nameservers = cloudflare;

  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSOverTLS = true;
      # Without this resolved falls back to its built-in servers (Google,
      # Cloudflare, Quad9) in plain text when ours don't answer.
      FallbackDNS = [ ];
      # Ours answer for every domain.
      Domains = [ "~." ];
    };
  };

  # NetworkManager doesn't pass the DNS servers from DHCP (the router's)
  # on to anyone: resolved only knows the ones above. Forced, because the
  # resolved module sets "systemd-resolved", in which NetworkManager hands
  # resolved the router's servers as per-link DNS -- plain text, and used
  # alongside ours.
  networking.networkmanager.dns = lib.mkForce "none";
  # ...and this too: dns= only covers resolv.conf. NetworkManager.conf's
  # own `systemd-resolved` (on by default) hands each connection's DNS to
  # resolved regardless, which left the router as the Wi-Fi link's DNS
  # with DefaultRoute -- queried in plain text next to Cloudflare.
  networking.networkmanager.settings.main.systemd-resolved = false;
}
