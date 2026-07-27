{ config, pkgs, ... }:
{
  sops.secrets.henrique_password_hash = {
    neededForUsers = true;
  };

  users.users.henrique = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    linger = true;
    # Local SDDM/console login password (separate from SSH, which stays
    # key-only). Hash lives in secrets/caixa.yaml under henrique_password_hash.
    hashedPasswordFile = config.sops.secrets.henrique_password_hash.path;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNEELZAtcyd/g3y1gPjgSaxLlN5BZPilFzPTX6UTS2B henrique@caixa"
    ];
  };
}
