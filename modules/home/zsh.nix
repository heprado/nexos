{ ... }:
{
  programs.eza = {
    enable = true;
    enableZshIntegration = false;
    icons = "auto";
    git = true;
  };

  programs.zsh = {
    enable = true;
    shellAliases = {
      eza = "eza --icons auto --git";
      l = "ls -alh";
      la = "eza -a";
      ll = "eza -l";
      lla = "eza -la";
      ls = "eza";
      lt = "eza --tree";
      # nh finds the flake via programs.nh.flake (modules/nixos/common.nix)
      # and the output via this machine's hostname, so the same aliases are
      # right on caixa and marvin. It shows what changed (added/removed/
      # updated packages) after building, and asks for sudo itself only to
      # activate -- use `nrs`, not `sudo nrs`.
      nrs = "nh os switch";
      # `test`: activates the new config now without making it the boot
      # default, so a reboot falls back to the previous one.
      nrt = "nh os test";
      run-help = "man";
      which-command = "whence";
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
