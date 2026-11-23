{ ... }:
{
  programs.eza = {
    enable = true;
    enableBashIntegration = false;
    icons = "auto";
    git = true;
  };

  programs.bash = {
    enable = true;
    shellAliases = {
      eza = "eza --icons auto --git";
      l = "ls -alh";
      la = "eza -a";
      ll = "eza -l";
      lla = "eza -la";
      ls = "eza";
      lt = "eza --tree";
      # nrs/nrt/nrb are commands, not aliases (modules/home/cli.nix).
    };

    # Same prompt as the old zsh one: cwd, then the repo/worktree, branch
    # and commit (and the upstream URL), then `$ ` on the next line. Bash
    # re-runs the $(...) in PS1 on every prompt, so it follows the repo
    # you're in. The colors come out of a function, so they're wrapped in
    # \001...\002 (the runtime form of \[...\]) to keep line editing right.
    initExtra = ''
      _git_prompt_info() {
        local branch sha worktree remote remote_url info
        local c_mag=$'\001\e[35m\002' c_grn=$'\001\e[32m\002' \
              c_yel=$'\001\e[33m\002' c_blu=$'\001\e[34m\002' \
              c_off=$'\001\e[0m\002'

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

        info="''${c_mag}''${worktree}''${c_off} ''${c_grn}''${branch}''${c_off}@''${c_yel}''${sha}''${c_off}"
        [ -n "$remote_url" ] && info="''${info} ''${c_blu}-> ''${remote_url}''${c_off}"
        printf ' (%s)' "$info"
      }

      PS1='\w$(_git_prompt_info)\n\$ '
    '';
  };
}
