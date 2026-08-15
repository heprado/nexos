{ pkgs, ... }:
{
  home.packages = [
    pkgs.rtk
  ];

  # henrique-only Claude Code policy (not machine-wide -- see
  # <https://code.claude.com/docs/en/memory> for the full precedence
  # order; ~/.claude/CLAUDE.md is the per-user location).
  home.file.".claude/CLAUDE.md".text = ''
    # henrique's Claude Code policy

    - Never decrypt or decode secret files (sops-nix secrets, age-encrypted
      files, or similar) unless explicitly asked to in that turn. Don't
      offer to do it as a convenience either -- ask first.
    - Never add a Co-Authored-By or Claude-Session trailer to git commits.
  '';
}
