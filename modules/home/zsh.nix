{ ... }:
{
  # enableZshIntegration wires up ls/ll/la/lt aliases to eza itself (with
  # icons/git status columns) -- no need to hand-roll them in
  # shellAliases below.
  programs.eza = {
    enable = true;
    enableZshIntegration = true;
    icons = "auto";
    git = true;
  };

  programs.zsh = {
    enable = true;
    shellAliases = {
      # No "#host": nixos-rebuild picks the flake output matching this
      # machine's hostname, so the same alias is right on caixa and marvin.
      # It already runs sudo itself -- use `nrs`, not `sudo nrs`.
      nrs = "sudo nixos-rebuild switch --flake /home/henrique/codigos/nexos";
      # Lets `sudo nrs` also expand the alias above (sudo isn't a shell
      # builtin, so it normally can't see aliases) -- a trailing space on
      # an alias's value tells zsh to alias-expand the *next* word too.
      sudo = "sudo ";
    };

    # PROMPT_SUBST makes zsh re-evaluate `$(...)` inside PROMPT on every
    # render, so _git_prompt_info reflects the repo/worktree/branch you're
    # currently in instead of the one from when the shell started.
    initContent = ''
      setopt PROMPT_SUBST

      _git_prompt_info() {
        local branch sha worktree remote remote_url info

        branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null)
        if [ -z "$branch" ]; then
          # detached HEAD
          branch=$(git rev-parse --short HEAD 2>/dev/null) || return
          branch="detached:$branch"
        fi

        sha=$(git rev-parse --short HEAD 2>/dev/null)
        worktree=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
        remote=$(git config --get "branch.''${branch}.remote" 2>/dev/null)
        [ -n "$remote" ] && remote_url=$(git remote get-url "$remote" 2>/dev/null)

        info="%F{magenta}''${worktree}%f %F{green}''${branch}%f@%F{yellow}''${sha}%f"
        [ -n "$remote_url" ] && info="''${info} %F{blue}-> ''${remote_url}%f"
        print -n " ($info)"
      }

      PROMPT='%~$(_git_prompt_info)
%# '
    '';
  };
}
