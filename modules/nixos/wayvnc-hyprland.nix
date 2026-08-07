{ config, pkgs, ... }:
let
  # Self-signed TLS cert for encrypting the VNC channel. Not an identity
  # guarantee (self-signed), just transport encryption -- clients will need
  # to trust-on-first-use. Regenerates (new random key) only if this
  # derivation's inputs change, e.g. an openssl bump in nixpkgs.
  wayvncTls = pkgs.runCommand "wayvnc-tls-cert"
    { nativeBuildInputs = [ pkgs.openssl ]; }
    ''
      mkdir -p $out
      openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes \
        -keyout $out/key.pem -out $out/cert.pem -subj /CN=caixa \
        -addext subjectAltName=DNS:caixa,DNS:localhost,IP:127.0.0.1
    '';
in
{
  # henrique auto-logs into Hyprland at the physical console so a session
  # always exists for wayvnc to share, even when he's away from caixa.
  services.displayManager.autoLogin = {
    enable = true;
    user = "henrique";
  };
  services.displayManager.defaultSession = "hyprland";

  sops.secrets.henrique_vnc_password = {
    owner = "henrique";
  };

  sops.templates."wayvnc-config" = {
    owner = "henrique";
    content = ''
      address=0.0.0.0
      port=5900
      enable_auth=true
      username=henrique
      password=${config.sops.placeholder.henrique_vnc_password}
      private_key_file=${wayvncTls}/key.pem
      certificate_file=${wayvncTls}/cert.pem
    '';
  };

  systemd.user.services.wayvnc = {
    description = "wayvnc remote access to henrique's Hyprland session";
    unitConfig.ConditionUser = "henrique";
    partOf = [ "hyprland-session.target" ];
    wantedBy = [ "hyprland-session.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc --config=${config.sops.templates."wayvnc-config".path}";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Primary remote path is now the Cloudflare Tunnel
  # (hyprland.heprado.com.br -- see cloudflared.nix), which reaches this
  # over loopback and needs no firewall rule. This LAN-wide opening is
  # kept as-is for direct local access (assumes caixa isn't directly
  # WAN-exposed) -- unrelated to the Tailscale->cloudflared swap.
  networking.firewall.allowedTCPPorts = [ 5900 ];
}
