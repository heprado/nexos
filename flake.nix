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

    helium-flake = {
      url = "github:oxcl/nix-flake-helium-browser";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-wsl = {
      url = "github:nix-community/NixOS-WSL";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, sops-nix, disko, noctalia, noctalia-greeter, helium-flake, nixos-wsl, ... }@inputs: {
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
    };

    nixosConfigurations.caixa = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      # `self` is passed alongside `inputs` (it isn't included in the
      # @inputs capture above, since it's bound explicitly) so
      # configuration.nix can register this flake's own path in the Nix
      # registry -- see nix.registry.nexos there.
      specialArgs = { inherit inputs self; };
      modules = [
        ./machines/caixa/configuration.nix
        ./machines/caixa/disko-config.nix
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

    nixosConfigurations.marvin = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs self; };
      modules = [
        ./machines/marvin/configuration.nix
        nixos-wsl.nixosModules.default
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs; };
        }
      ];
    };
  };
}
