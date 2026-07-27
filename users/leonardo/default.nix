{ config, pkgs, ... }:
{
  sops.secrets.leonardo_password_hash = {
    neededForUsers = true;
  };

  users.users.leonardo = {
    isNormalUser = true;
    shell = pkgs.zsh;
    linger = true;
    # RDP login password (separate from SSH, which stays key-only). Hash
    # lives in secrets/caixa.yaml under leonardo_password_hash.
    hashedPasswordFile = config.sops.secrets.leonardo_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMsz3olRnQIgKIfqFBpao5w0NWAcqjawpkfuJq1SdeuT leonardo@caixa"
    ];
  };
}
