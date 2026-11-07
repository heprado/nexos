{ pkgs, osConfig, ... }:
let
  # nh finds the flake via programs.nh.flake (modules/nixos/common.nix) and
  # the output via this machine's hostname, so the same commands are right
  # on caixa and marvin. It shows what changed (added/removed/updated
  # packages) after building, and asks for sudo itself only to activate --
  # use `nrs`, not `sudo nrs`. Commands rather than zsh aliases so they
  # also work from bash, scripts and coding agents; extra arguments pass
  # through to nh (e.g. `nrs --update`, `nrb --show-trace`).
  nhOs = name: action: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ osConfig.programs.nh.package ];
    text = ''exec nh os ${action} "$@"'';
  };
in
{
  home.packages = [
    # Renders Markdown in the terminal.
    pkgs.glow
    # Build and activate, and make it the boot default.
    (nhOs "nrs" "switch")
    # Activate now without making it the boot default, so a reboot falls
    # back to the previous generation.
    (nhOs "nrt" "test")
    # Only build and show the diff against the running system: no sudo, no
    # activation -- the safe check after editing the config. switch/test
    # keep their link in a temporary directory, but `nh os build` writes
    # ./result, so it goes to the runtime dir instead (nh refuses a second
    # -o, so for another path run `nh os build -o <path>` directly).
    (nhOs "nrb" ''build --out-link "''${XDG_RUNTIME_DIR:-/tmp}/nrb-result"'')
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
