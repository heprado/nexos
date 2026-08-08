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

  # Second wayvnc instance, dedicated to novnc-hyprland.nix's
  # websockify->browser path. Skips private_key_file/certificate_file (see
  # the main instance above) since the browser's transport encryption
  # already comes from the outer WSS/HTTPS connection, terminated at the
  # Cloudflare edge -- not from wayvnc itself. Binds to 127.0.0.1 only,
  # never reachable over the LAN/WAN, just from websockify running locally.
  #
  # Without TLS/RSA-AES configured, neatvnc (wayvnc's RFB library) does NOT
  # fall back to classic password-only VNCAuth (security type 2, which
  # noVNC supports) -- it treats that as "broken crypto" (DES-based) and
  # skips it unless explicitly allowed, offering only RA2(5)/UnixLogon(129)
  # instead, neither of which noVNC implements (verified: connecting
  # straight to 127.0.0.1:5901, bypassing the tunnel/WSS entirely, offered
  # exactly those two and nothing else). relax_encryption+allow_broken_crypto
  # opts back into VNCAuth -- same mechanism as the "DES Authentication
  # (Legacy)" case in wayvnc's own README, there for the same reason
  # (clients, like noVNC or macOS Screen Sharing, that only speak the
  # classic scheme). username is dropped since VNCAuth is password-only.
  sops.templates."wayvnc-novnc-config" = {
    owner = "henrique";
    content = ''
      address=127.0.0.1
      port=5901
      enable_auth=true
      password=${config.sops.placeholder.henrique_vnc_password}
      relax_encryption=true
      allow_broken_crypto=true
    '';
  };

  systemd.user.services.wayvnc-novnc = {
    description = "wayvnc (no TLS, localhost-only) for the noVNC/websockify browser path";
    unitConfig.ConditionUser = "henrique";
    partOf = [ "hyprland-session.target" ];
    wantedBy = [ "hyprland-session.target" ];
    serviceConfig = {
      # -S: wayvnc's control socket defaults to a fixed path under
      # XDG_RUNTIME_DIR -- without an explicit alternate here, this
      # instance refuses to start ("Another wayvnc process is already
      # running") because the main wayvnc instance above already owns it.
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc --config=${config.sops.templates."wayvnc-novnc-config".path} --socket=%t/wayvncctl-novnc";
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Primary remote path is now the Cloudflare Tunnel
  # (remote.heprado.com.br -- see cloudflared.nix), which reaches this
  # over loopback and needs no firewall rule. This LAN-wide opening is
  # kept as-is for direct local access (assumes caixa isn't directly
  # WAN-exposed) -- unrelated to the Tailscale->cloudflared swap.
  networking.firewall.allowedTCPPorts = [ 5900 ];
}
