{ pkgs, ... }:
{
  home.packages = [
    pkgs.git
    pkgs.gh
    # Renders Markdown in the terminal.
    pkgs.glow
  ];

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
