{ pkgs, ... }:
{
  home.packages = [
    # Renders Markdown in the terminal.
    pkgs.glow
  ];

  # git and gh through home-manager: gh's credential helper is written into
  # ~/.config/git/config with the current gh's path on every switch, where
  # `gh auth setup-git` pins a store path that a garbage collection removes.
  programs.git.enable = true;
  programs.gh = {
    enable = true;
    gitCredentialHelper.enable = true;
    settings.git_protocol = "https";
  };

  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
    # --cmd cd makes zoxide define `cd`/`cdi` itself instead of `z`/`zi` --
    # `cd <exact-or-partial-path>` still behaves like the real builtin, it
    # only adds frecency-based jumping on top (e.g. `cd nexos` from
    # anywhere), so muscle memory doesn't need to change.
    options = [ "--cmd" "cd" ];
  };
}
