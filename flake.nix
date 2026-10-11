{
  description = "NixOS configurations, split by machine and by user";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

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
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs";
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
  };
}
