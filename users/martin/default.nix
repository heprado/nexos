{ config, pkgs, ... }:
{
  sops.secrets.martin_password_hash = {
    neededForUsers = true;
  };

  users.users.martin = {
    isNormalUser = true;
    shell = pkgs.zsh;
    linger = true;
    # RDP login password (separate from SSH, which stays key-only). Hash
    # lives in secrets/caixa.yaml under martin_password_hash.
    hashedPasswordFile = config.sops.secrets.martin_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgV+MYpW2vmYUE0COrwbHlNQTuni0RyEd84vR+DPRab martin@caixa"
    ];
  };
}
