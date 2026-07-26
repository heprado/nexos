{ config, ... }:
{
  services.tailscale = {
    enable = true;
    authKeyFile = config.sops.secrets.tailscale_authkey.path;
  };

  sops.secrets.tailscale_authkey = { };
}
