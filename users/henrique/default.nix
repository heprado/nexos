{ pkgs, ... }:
{
  users.users.henrique = {
    isNormalUser = true;
    shell = pkgs.zsh;
    extraGroups = [ "wheel" ];
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINNEELZAtcyd/g3y1gPjgSaxLlN5BZPilFzPTX6UTS2B henrique@caixa"
    ];
  };
}
