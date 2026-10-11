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
  # dashboard, under this tunnel's "Public Hostname" tab.
  #
  # SSH is no longer one of them: it's local-network only, and ssh.nix
  # refuses it over loopback, which is where the tunnel would deliver it.
  # Remove the ssh.heprado.com.br mapping from the dashboard by hand.
  #
  # kde.heprado.com.br (RDP, leonardo/martin's Plasma sessions) and
  # remote.heprado.com.br (noVNC/wayvnc into the Hyprland session, gone
  # since caixa became terminal-only) were removed from this flake -- also
  # remove their "Public Hostname" mappings from the Zero Trust dashboard by
  # hand, that part isn't declared here.
  #
  # WARNING: a public hostname has no authentication layer of its own beyond
  # whatever runs on the other end. If a Cloudflare Access policy isn't
  # configured for it in the dashboard, anyone who discovers the hostname
  # can attempt to connect straight through.
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
