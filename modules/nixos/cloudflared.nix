{ config, ... }:
{
  # Replaces Tailscale as the remote-access path (see the removed
  # tailscale.nix). cloudflared makes an outbound-only connection to
  # Cloudflare's edge -- no inbound port ever needs to be opened on the
  # WAN/LAN interface for these services; traffic arrives already
  # de-tunneled and cloudflared forwards it to localhost, which bypasses
  # nixos-fw entirely (loopback is exempt) and is untouched by
  # lan-isolation.nix's peer-traffic blocking.
  #
  # WARNING: none of the three hostnames below have an authentication
  # layer of their own beyond whatever runs on the other end (SSH keys;
  # xrdp/PAM; wayvnc's password). If Cloudflare Access policies aren't
  # configured for these hostnames in the Zero Trust dashboard, anyone
  # who discovers the hostname can attempt to connect straight through --
  # this is especially risky for RDP. Set up Access policies (or WARP-only
  # enrollment) for ssh.heprado.com.br / kde.heprado.com.br /
  # hyprland.heprado.com.br before relying on this as the only path in.
  services.cloudflared = {
    enable = true;
    tunnels."b47dfcda-a469-457b-88f4-ef3326c8c506" = {
      credentialsFile = config.sops.secrets.cloudflared_tunnel_credentials.path;
      default = "http_status:404";
      ingress = {
        "ssh.heprado.com.br" = "ssh://localhost:22";
        # KDE Plasma over RDP (leonardo/martin) -- see desktop-plasma-rdp.nix.
        "kde.heprado.com.br" = "tcp://localhost:3389";
        # wayvnc, henrique's actual Hyprland session -- see wayvnc-hyprland.nix.
        "hyprland.heprado.com.br" = "tcp://localhost:5900";
      };
    };
  };

  # Full credentials.json content from the tunnel (`cloudflared tunnel
  # create` writes it to ~/.cloudflared/<tunnel-id>.json) -- add via
  # `sops secrets/caixa.yaml`, see secrets/README.md.
  sops.secrets.cloudflared_tunnel_credentials = { };
}
