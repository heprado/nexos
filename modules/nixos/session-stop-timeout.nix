{ ... }:
{
  # Claude Code's background daemon (and its pty/spare helpers) catch
  # SIGTERM but don't exit, so every reboot sat on "A stop job is running
  # for Session N of User henrique" for the full default 90s before systemd
  # SIGKILLed them. "session-.scope" is a prefix drop-in: it applies to
  # every logind session-*.scope, so anything stuck in a login session gets
  # 10s instead. System services (docker, nix-daemon, ...) keep the default.
  systemd.units."session-.scope" = {
    overrideStrategy = "asDropin";
    text = ''
      [Scope]
      TimeoutStopSec=10s
    '';
  };
}
