{ pkgs, lib, config, ... }:
# Rootless Podman scoped to ONE devenv project, whose lifetime is tied to
# the shell(s) that activated it. Entering the env (devenv shell or direnv)
# starts a `podman system service` (Docker-compatible API socket) plus a
# watchdog; when the last activating shell goes away -- `devenv shell`
# exited, the terminal closed, or (direnv) that shell cd'd out of the
# project -- the watchdog stops every container, kills the API service and
# the rootless pause process. Nothing survives deactivation.
#
# Why Podman and not Docker: the machine-wide rootless Docker
# (modules/nixos/docker-rootless.nix) is a systemd user service that is
# always up and shared by every project; Podman is daemonless, so it can be
# confined to the project and killed with it.
#
# Everything Podman stores lives under .devenv/state/podman (images,
# containers, networks, config) and $XDG_RUNTIME_DIR/devenv-podman-<hash>
# (runtime state), so it never touches ~/.config/containers or
# ~/.local/share/containers and can't see/kill other projects' containers.
#
# Host requirements (NixOS, already true here): subuid/subgid ranges for
# the user and the setuid newuidmap/newgidmap wrappers in /run/wrappers.
let
  podman = pkgs.podman;

  # Podman reads its user config (containers.conf, storage.conf,
  # registries.conf, policy.json) from $HOME/.config/containers and stores
  # images under $HOME/.local/share/containers, so pointing HOME at a
  # project-local dir confines both. Only the podman processes see this
  # HOME; the rest of the shell keeps the real one.
  podmanEnv = ''
    root="''${DEVENV_ROOT:?not inside a devenv shell}"
    state="''${DEVENV_STATE:-$root/.devenv/state}/podman"
    hash="$(printf %s "$root" | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -c1-12)"
    run="''${DEVENV_PODMAN_RUN:-''${XDG_RUNTIME_DIR:-/run/user/$(${pkgs.coreutils}/bin/id -u)}/devenv-podman-$hash}"
    export DEVENV_PODMAN_RUN="$run"
  '';

  podmanWrapper = pkgs.writeShellScriptBin "podman" ''
    ${podmanEnv}
    export HOME="$state/home" XDG_RUNTIME_DIR="$run"
    mkdir -p -m 700 "$run"
    unset XDG_CONFIG_HOME XDG_DATA_HOME
    exec ${podman}/bin/podman "$@"
  '';

  composeWrapper = pkgs.writeShellScriptBin "podman-compose" ''
    export PATH="${podmanWrapper}/bin:$PATH"
    exec ${pkgs.podman-compose}/bin/podman-compose "$@"
  '';

  cfg = config.containersGuard;

  # Deny by default. Registry pulls are allowed only for the repositories
  # the project lists in containersGuard.allowedImages; with a public key
  # the image must also carry a valid sigstore signature, otherwise it is
  # accepted unsigned (some upstreams, e.g. docker.io/nixos/nix, publish no
  # signatures at all). Local storage stays open: it only holds what this
  # project pulled through the rules above, loaded, or built itself.
  #
  # containersGuard.allowArchiveLoad opens `podman load` (docker-archive):
  # for projects that obtain base images through a channel verified
  # outside Podman (e.g. a Nix store path signed by cache.nixos.org) and
  # keep every registry closed.
  policyJson = builtins.toJSON (lib.recursiveUpdate {
    default = [ { type = "reject"; } ];
    transports.docker = lib.mapAttrs (_: key:
      if key == null then [ { type = "insecureAcceptAnything"; } ]
      else [ { type = "sigstoreSigned"; keyPath = toString key; signedIdentity.type = "matchRepository"; } ]
    ) cfg.allowedImages;
    transports.containers-storage."" = [ { type = "insecureAcceptAnything"; } ];
  } (lib.optionalAttrs cfg.allowArchiveLoad {
    transports.docker-archive."" = [ { type = "insecureAcceptAnything"; } ];
  }));

  guard = pkgs.writeShellApplication {
    name = "containers-guard";
    runtimeInputs = [ podmanWrapper pkgs.coreutils pkgs.gawk pkgs.util-linux pkgs.procps ];
    text = ''
      ${podmanEnv}
      owners="$run/owners"

      write_config() {
        local cfg="$state/home/.config/containers"
        mkdir -p "$cfg" "$state/home/.local/share" "$run"
        chmod 700 "$run"
        cat >"$cfg/storage.conf" <<EOF
      [storage]
      driver = "overlay"
      graphroot = "$state/storage"
      runroot = "$run/storage"
      EOF
        cat >"$cfg/containers.conf" <<EOF
      [containers]
      # journald (the default) can't be followed with the file events
      # backend: "podman logs -f" would fail outright.
      log_driver = "k8s-file"
      [engine]
      cgroup_manager = "cgroupfs"
      events_logger = "file"
      [network]
      default_rootless_network_cmd = "pasta"
      EOF
        cat >"$cfg/registries.conf" <<EOF
      unqualified-search-registries = ["docker.io"]
      short-name-mode = "enforcing"
      EOF
        printf '%s\n' ${lib.escapeShellArg policyJson} >"$cfg/policy.json"
      }

      # The shell whose lifetime owns this activation. Under direnv the
      # enterShell code runs in a throwaway bash spawned by `direnv export`,
      # so the owner is direnv's parent (the interactive shell) and the
      # activation lasts while that shell stays inside the project. Under
      # `devenv shell` enterShell runs in the interactive shell itself.
      find_owner() {
        local p=$$ comm
        while [ "$p" -gt 1 ]; do
          comm="$(cat "/proc/$p/comm" 2>/dev/null || true)"
          if [ "$comm" = direnv ]; then
            echo "$(awk '{print $4}' "/proc/$p/stat") dir"
            return
          fi
          p="$(awk '{print $4}' "/proc/$p/stat" 2>/dev/null || echo 1)"
        done
        echo "''${CONTAINERS_GUARD_OWNER:-$PPID} shell"
      }

      owner_active() { # <pid> <mode>
        kill -0 "$1" 2>/dev/null || return 1
        [ "$2" = dir ] || return 0
        case "$(readlink "/proc/$1/cwd" 2>/dev/null)/" in
          "$root"/*) return 0 ;;
          *) return 1 ;;
        esac
      }

      alive() { [ -f "$1" ] && kill -0 "$(cat "$1")" 2>/dev/null; }

      # Detach fully: new session, and close every inherited fd above 2 --
      # direnv waits for its output pipe to close, so a daemon still holding
      # it would hang `direnv export` forever.
      daemonize() { # <log> <cmd...>
        local log="$1"; shift
        (
          for fd in "/proc/$BASHPID/fd"/*; do
            fd="''${fd##*/}"
            [ "$fd" -gt 2 ] && eval "exec $fd>&-"
          done
          exec setsid "$@" >>"$log" 2>&1 </dev/null
        ) &
      }

      start_service() {
        alive "$run/service.pid" && return 0
        daemonize "$state/service.log" podman system service --time=0 "unix://$run/podman.sock"
        echo $! >"$run/service.pid"
      }

      teardown() {
        echo "[$(date -Is)] teardown" >>"$state/guard.log"
        podman stop --all --time 5 >>"$state/guard.log" 2>&1 || true
        podman pod stop --all >>"$state/guard.log" 2>&1 || true
        if alive "$run/service.pid"; then
          kill "$(cat "$run/service.pid")" 2>/dev/null || true
        fi
        # The rootless pause process holds the user namespace open between
        # podman invocations; with a project-local XDG_RUNTIME_DIR it is ours
        # alone.
        if alive "$run/libpod/tmp/pause.pid"; then
          kill "$(cat "$run/libpod/tmp/pause.pid")" 2>/dev/null || true
        fi
        # Anything podman left behind (conmon, pasta, rootlessport,
        # aardvark-dns, a stray pause process) is a leftover: no mercy.
        # Matched by the DEVENV_PODMAN_RUN every podman process inherits from
        # the wrappers -- NOT by `pkill -f "$run"`, which would also kill any
        # unrelated process that merely mentions the path (a `tail -f` of a
        # log in there, the shell that ran `ls` on it, ...).
        sleep 1
        local p
        for p in $(pgrep -u "$(id -u)"); do
          [ "$p" = $$ ] && continue
          if { tr '\0' '\n' <"/proc/$p/environ"; } 2>/dev/null | grep -qxF "DEVENV_PODMAN_RUN=$run"; then
            kill "$p" 2>/dev/null || true
          fi
        done
        rm -rf "$owners" "$run/service.pid" "$run/watchdog.pid" "$run/podman.sock"
      }

      watchdog() {
        exec 9>"$run/watchdog.lock"
        flock -n 9 || exit 0
        echo $$ >"$run/watchdog.pid"
        while :; do
          sleep 2
          local any=0 f pid mode
          for f in "$owners"/*; do
            [ -e "$f" ] || continue
            pid="''${f##*/}"; pid="''${pid%.*}"; mode="''${f##*.}"
            if owner_active "$pid" "$mode"; then any=1; else rm -f "$f"; fi
          done
          if [ "$any" = 0 ]; then
            teardown
            exit 0
          fi
        done
      }

      case "''${1:-}" in
        attach)
          write_config
          exec 8>"$run/attach.lock"
          flock 8
          mkdir -p "$owners"
          read -r pid mode < <(find_owner)
          touch "$owners/$pid.$mode"
          start_service
          if ! alive "$run/watchdog.pid"; then
            daemonize "$state/guard.log" "$0" watchdog
          fi
          ;;
        watchdog) watchdog ;;
        down)
          if alive "$run/watchdog.pid"; then kill "$(cat "$run/watchdog.pid")" 2>/dev/null || true; fi
          teardown
          ;;
        status)
          echo "runtime: $run"
          printf 'service:  '; alive "$run/service.pid" && echo "up (pid $(cat "$run/service.pid"))" || echo down
          printf 'watchdog: '; alive "$run/watchdog.pid" && echo "up (pid $(cat "$run/watchdog.pid"))" || echo down
          printf 'owners:  '
          for f in "$owners"/*; do [ -e "$f" ] && printf ' %s' "''${f##*/}"; done
          echo
          podman ps --format '{{.Names}}\t{{.Status}}' 2>/dev/null || true
          ;;
        *) echo "usage: containers-guard attach|down|status" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  options.containersGuard.allowArchiveLoad = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Accept `podman load` of local image archives. Only for images whose
      integrity was already verified some other way (see policyJson).
    '';
  };

  options.containersGuard.allowedImages = lib.mkOption {
    type = lib.types.attrsOf (lib.types.nullOr lib.types.path);
    default = { };
    example = lib.literalExpression ''
      {
        "docker.io/nixos/nix" = null;                  # unsigned upstream
        "ghcr.io/example/app" = ./keys/cosign.pub;     # must be sigstore-signed
      }
    '';
    description = ''
      Registry repositories this project may pull, mapped to a cosign public
      key (signature required) or null (accepted unsigned). Everything else
      is rejected by Podman's signature policy.
    '';
  };

  config = {
    packages = [ podmanWrapper composeWrapper guard ];

    # Docker-compatible clients (docker CLI, testcontainers, ...) talk to
    # this project's Podman instead of the machine-wide rootless Docker.
    enterShell = ''
      containers-guard attach
      export DOCKER_HOST="unix://''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/devenv-podman-$(printf %s "$DEVENV_ROOT" | sha256sum | cut -c1-12)/podman.sock"
    '';
  };
}
