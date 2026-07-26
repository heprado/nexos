{ pkgs, ... }:
{
  users.users.martin = {
    isNormalUser = true;
    shell = pkgs.zsh;
    linger = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBgV+MYpW2vmYUE0COrwbHlNQTuni0RyEd84vR+DPRab martin@caixa"
    ];
  };
}
