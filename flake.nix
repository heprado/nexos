{
  description = "NixOS configurations, split by machine and by user";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia = {
      # Track the latest commit already published to Noctalia's binary cache.
      # Do not follow the root nixpkgs input: that changes package hashes and
      # prevents Cachix hits (see Noctalia's NixOS installation docs).
      url = "github:noctalia-dev/noctalia/cachix";
    };

    noctalia-greeter = {
      url = "github:noctalia-dev/noctalia-greeter";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    hyprqt6engine = {
      url = "github:hyprwm/hyprqt6engine";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Display arrangement + DDC/CI monitor controls (Quickshell app), with
    # a home-manager module that reapplies the saved layout at login.
    monitor-settings = {
      url = "github:heprado/noctalia-monitor-settings";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    helium-flake = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure Boot for marvin (signed UKIs + systemd-boot). Pinned to a
    # release tag, as upstream recommends, instead of tracking master.
    lanzaboote = {
      url = "github:nix-community/lanzaboote/v1.2.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Two lab servers as microVMs on caixa, on a Linux bridge of their own
    # (container_studies' vms/ flake; see modules/nixos/lab-vms.nix).
    lab-vms = {
      url = "git+https://github.com/heprado/container_studies.git?dir=vms";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # League of Legends' macOS client on Darling (~/codigos/darling-lol-iso):
    # marvin imports just its darling-lol module. No nixpkgs follows: its
    # Darling is built against its own pin, and following would rebuild it.
    darling-lol-iso.url = "git+file:///home/henrique/codigos/darling-lol-iso";
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, disko, noctalia-greeter, ... }@inputs: {
    # Per-language devShells for henrique's actual project repos (not
    # this one) -- `nix flake init -t .#<name>` drops in a devenv.nix +
    # devenv.yaml + .envrc so direnv auto-activates the right
    # compiler/LSP/formatter (and services like postgres, when needed)
    # per project, instead of installing every language globally via
    # home-manager. See modules/home/neovim.nix, which expects these
    # LSP binaries on PATH rather than at a fixed store path.
    templates = {
      rust = {
        path = ./templates/rust;
        description = "Rust devShell: rustc, cargo, rust-analyzer, clippy, rustfmt";
      };
      python = {
        path = ./templates/python;
        description = "Python devShell: python3, basedpyright, ruff";
      };
      c = {
        path = ./templates/c;
        description = "C devShell: gcc, clang-tools (clangd), gnumake, gdb";
      };
      sql = {
        path = ./templates/sql;
        description = "SQL devShell: sqls language server";
      };
      web = {
        path = ./templates/web;
        description = "JavaScript/TypeScript devShell: node, typescript, typescript-language-server, eslint, prettier";
      };
      # Add-on, not a standalone env: drops containers.nix next to an
      # existing devenv.nix, which then needs `imports = [ ./containers.nix ];`.
      containers = {
        path = ./templates/containers;
        description = "Add-on: rootless Podman scoped to the project, killed when the devenv shell is left";
      };
    };

    nixosConfigurations =
      let
        # Each host is machines/<name>/{configuration,disko-config}.nix
        # plus the modules every host shares. Host-only flake modules (e.g.
        # marvin's lanzaboote) are imported from that host's
        # configuration.nix via `inputs`.
        mkHost = name: nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          # `self` is passed alongside `inputs` (it isn't included in the
          # @inputs capture above, since it's bound explicitly) so
          # modules/nixos/common.nix can register this flake's own path in
          # the Nix registry -- see nix.registry.nexos there.
          specialArgs = { inherit inputs self; };
          modules = [
            ./machines/${name}/configuration.nix
            ./machines/${name}/disko-config.nix
            home-manager.nixosModules.home-manager
            sops-nix.nixosModules.sops
            disko.nixosModules.disko
            noctalia-greeter.nixosModules.default
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };
            }
          ];
        };
      in
      {
        caixa = mkHost "caixa";
        marvin = mkHost "marvin";
      };

    # `nix run .#update-machines`: switches every host in
    # nixosConfigurations to this checkout (uncommitted changes included),
    # all built here so the others don't need their own up-to-date clone.
    # Other hosts are reached over SSH by their hostname, so they need to
    # resolve (/etc/hosts or ~/.ssh/config). Building and copying -- the
    # slow part -- runs for every host at once, each logging to
    # $XDG_RUNTIME_DIR/update-machines/<host>.log; activating runs one host
    # after another afterwards, since it's quick and sudo may ask for a
    # password on each. A host that fails doesn't stop the rest.
    apps.x86_64-linux.update-machines =
      let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        hosts = builtins.attrNames self.nixosConfigurations;
        script = pkgs.writeShellApplication {
          name = "update-machines";
          runtimeInputs = [ pkgs.openssh pkgs.hostname pkgs.coreutils ];
          text = ''
            flake=${self}
            here=$(hostname)
            logs=''${XDG_RUNTIME_DIR:-/tmp}/update-machines
            mkdir -p "$logs"
            failed=()

            # Every remote host takes several SSH connections (reachability,
            # copy, activate); load the key into an agent once so its
            # passphrase is asked here, not on every connection. Uses the
            # running agent if there is one, else a temporary one.
            # ssh-add -l: 0 = keys loaded, 1 = agent but no keys, 2 = no agent.
            agent=0
            ssh-add -l >/dev/null 2>&1 || agent=$?
            if [ "$agent" = 2 ]; then
              eval "$(ssh-agent -s)" >/dev/null
              trap 'ssh-agent -k >/dev/null' EXIT
            fi
            if [ "$agent" != 0 ]; then
              ssh-add
            fi

            hosts=()
            for host in ${builtins.concatStringsSep " " hosts}; do
              if [ "$host" = "$here" ] || ssh -o ConnectTimeout=5 -o BatchMode=yes "$host" true; then
                hosts+=("$host")
              else
                echo "$host: unreachable over SSH, skipped" >&2
                failed+=("$host")
              fi
            done

            # Build (and, for other hosts, copy) in parallel. Each job
            # leaves the built system's store path in $logs/<host>.out.
            declare -A jobs
            for host in "''${hosts[@]}"; do
              rm -f "$logs/$host.out"
              (
                out=$(nix build --no-link --print-out-paths -L \
                  "$flake#nixosConfigurations.$host.config.system.build.toplevel")
                if [ "$host" != "$here" ]; then
                  nix copy --to "ssh-ng://$host" "$out"
                fi
                echo "$out" > "$logs/$host.out"
              ) > "$logs/$host.log" 2>&1 &
              jobs[$host]=$!
              echo "$host: building (log: $logs/$host.log)"
            done

            ready=()
            for host in "''${hosts[@]}"; do
              if wait "''${jobs[$host]}"; then
                echo "$host: built"
                ready+=("$host")
              else
                echo "$host: build/copy failed, last lines of $logs/$host.log:" >&2
                tail -n 15 "$logs/$host.log" >&2
                failed+=("$host")
              fi
            done

            # Activate one by one: point the system profile at the new
            # generation (so it's the boot default) and switch to it.
            for host in "''${ready[@]}"; do
              out=$(cat "$logs/$host.out")
              activate="nix-env -p /nix/var/nix/profiles/system --set $out && $out/bin/switch-to-configuration switch"
              echo "==> $host: activating $out"
              if [ "$host" = "$here" ]; then
                sudo sh -c "$activate" || failed+=("$host")
              else
                ssh -t "$host" sudo sh -c "'$activate'" || failed+=("$host")
              fi
            done

            if [ ''${#failed[@]} -gt 0 ]; then
              echo "failed: ''${failed[*]}" >&2
              exit 1
            fi
          '';
        };
      in
      {
        type = "app";
        program = "${script}/bin/update-machines";
      };
  };
}
