{ pkgs, ... }:
{
  users.users.leonardo = {
    isNormalUser = true;
    shell = pkgs.zsh;
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMsz3olRnQIgKIfqFBpao5w0NWAcqjawpkfuJq1SdeuT leonardo@caixa"
    ];
  };
}
