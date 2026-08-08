{ ... }:
{
  programs.zsh = {
    enable = true;
    shellAliases = {
      nrs = "sudo nixos-rebuild switch --flake /home/henrique/codigos/nexos#caixa";
      # Lets `sudo nrs` also expand the alias above (sudo isn't a shell
      # builtin, so it normally can't see aliases) -- a trailing space on
      # an alias's value tells zsh to alias-expand the *next* word too.
      sudo = "sudo ";
    };
  };
}
