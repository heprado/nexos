{ config, pkgs, ... }:
{
  # Replaces Tailscale as the remote-access path (see the removed
  # tailscale.nix). cloudflared makes an outbound-only connection to
  # Cloudflare's edge -- no inbound port ever needs to be opened on the
  # WAN/LAN interface for these services; traffic arrives already
  # de-tunneled and cloudflared forwards it to localhost, which bypasses
  # nixos-fw entirely (loopback is exempt) and is untouched by
  # lan-isolation.nix's peer-traffic blocking.
  #
  # This is a token-based ("remotely-managed") tunnel, not the
  # credentials.json ("locally-managed") kind -- NixOS's own
  # services.cloudflared module only supports the latter, so this is a
  # hand-rolled systemd unit instead. Because it's remotely-managed, the
  # ingress rules (which public hostname maps to which local service)
  # are NOT declared here -- they live in the Cloudflare Zero Trust
  # dashboard, under this tunnel's "Public Hostname" tab. Configure:
  #   ssh.heprado.com.br      -> ssh://localhost:22
  #   kde.heprado.com.br      -> tcp://localhost:3389   (RDP, see desktop-plasma-rdp.nix)
  #   hyprland.heprado.com.br -> http://localhost:6080  (noVNC/websockify in front
  #                                                       of wayvnc, see
  #                                                       novnc-hyprland.nix --
  #                                                       browser-based HTTPS
  #                                                       access, no VNC client
  #                                                       needed; TLS terminates
  #                                                       here at the tunnel)
  #
  # WARNING: none of the three hostnames above have an authentication
  # layer of their own beyond whatever runs on the other end (SSH keys;
  # xrdp/PAM; wayvnc's password). If Cloudflare Access policies aren't
  # configured for these hostnames in the dashboard, anyone who
  # discovers the hostname can attempt to connect straight through --
  # this is especially risky for RDP.
  systemd.services.cloudflared-tunnel = {
    description = "Cloudflare Tunnel (token-based)";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      DynamicUser = true;
      LoadCredential = "token:${config.sops.secrets.cloudflared_tunnel_token.path}";
      ExecStart = "${pkgs.cloudflared}/bin/cloudflared tunnel --no-autoupdate run --token-file %d/token";
      Restart = "on-failure";
      RestartSec = 5;
    };
  };

  # The tunnel token from the Zero Trust dashboard (Networks > Tunnels >
  # this tunnel > Configure > it's the long string after "--token" in
  # the install command shown there) -- add via `sops secrets/caixa.yaml`,
  # see secrets/README.md.
  sops.secrets.cloudflared_tunnel_token = { };
}
