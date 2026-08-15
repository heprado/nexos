{ ... }:
{
  home.packages = [
    rtk.packages
  ];

  # Managed policy for Claude Code: read by any user running `claude` on
  # this machine, with the highest precedence of all CLAUDE.md locations
  # (loads before ~/.claude/CLAUDE.md and any project CLAUDE.md). This is
  # the only way to apply agent instructions machine-wide without touching
  # every user's $HOME individually.
  # See <https://code.claude.com/docs/en/memory>.
  environment.etc."claude-code/CLAUDE.md".text = ''
    # Machine-wide Claude Code policy

    - Never decrypt or decode secret files (sops-nix secrets, age-encrypted
      files, or similar) unless explicitly asked to in that turn. Don't
      offer to do it as a convenience either -- ask first.
    - Never add a Co-Authored-By or Claude-Session trailer to git commits.
  '';
}
