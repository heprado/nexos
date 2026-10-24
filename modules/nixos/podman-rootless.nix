{ lib, ... }:
{
  # Podman is daemonless and rootless by default: each user's containers
  # live under ~/.local/share/containers, with no service running until
  # something is started. `docker` is an alias for `podman`.
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
    # Containers on the same compose network resolve each other by name.
    defaultNetwork.settings.dns_enabled = true;
  };

  # Docker-compatible API for clients that want a socket (docker compose,
  # testcontainers, ...): the user's podman.socket, socket-activated, so
  # `podman system service` only runs while something talks to it. Only
  # for regular users: the greeter (greetd's systemd --user) has no
  # subuid ranges and would fail.
  systemd.user.sockets.podman = {
    wantedBy = [ "sockets.target" ];
    unitConfig.ConditionUser = lib.mkForce "!@system";
  };
  environment.extraInit = ''
    if [ -z "$DOCKER_HOST" -a -n "$XDG_RUNTIME_DIR" ]; then
      export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
    fi
  '';
}
