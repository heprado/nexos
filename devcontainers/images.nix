{ pkgs }:
# Devcontainer images built from this flake's nixpkgs -- no Debian, no
# registry: one image per language, streamed into rootless Podman by
# modules/home/devcontainers.nix and used by templates/<lang>/.devcontainer
# (Zed opens them with `use_podman`).
#
# Every image has:
#   - user dev (uid 1000, gid 100), home /home/dev. The templates run with
#     --userns=keep-id, so dev *is* henrique's uid on the bind-mounted
#     repo: files stay his, nothing else of his home is visible;
#   - Zed's remote server, from the same nixpkgs as the host's Zed (so the
#     versions always match), where Zed looks for it: ~/.zed_server/;
#   - nix-ld as /lib64/ld-linux-x86-64.so.2, so the generic Linux binaries
#     Zed downloads inside (language servers, its own Node, extensions)
#     run against NIX_LD_LIBRARY_PATH like on a regular distro.
let
  inherit (pkgs) lib dockerTools;

  zed = pkgs.zed-editor;
  zedServer = zed.remoteServerExecutableName;

  # What foreign (non-Nix) binaries usually link against.
  nixLdLibs = with pkgs; [
    stdenv.cc.cc.lib
    zlib
    openssl
    icu
    curl
    libxml2
    expat
  ];

  common = with pkgs; [
    bashInteractive
    coreutils
    findutils
    diffutils
    gnugrep
    gnused
    gawk
    gnutar
    gzip
    xz
    bzip2
    zstd
    unzip
    which
    less
    procps
    file
    gitMinimal
    curl
    iana-etc
    tzdata
    zed.remote_server
    nix-ld
    dockerTools.binSh
    dockerTools.usrBinEnv
    dockerTools.caCertificates
    (dockerTools.fakeNss.override {
      extraPasswdLines = [ "dev:x:1000:100:dev:/home/dev:/bin/bash" ];
      extraGroupLines = [ "users:x:100:" ];
    })
  ] ++ nixLdLibs;

  mkImage = name: { packages ? [ ], env ? { }, extraCommands ? "" }:
    dockerTools.streamLayeredImage {
      name = "nexos/devcontainer-${name}";
      tag = "latest";
      contents = common ++ packages;
      fakeRootCommands = ''
        mkdir -p tmp var/tmp home/dev/.zed_server lib64 workspaces
        chmod 1777 tmp var/tmp
        ln -s ${zed.remote_server}/bin/${lib.escapeShellArg zedServer} \
          home/dev/.zed_server/${lib.escapeShellArg zedServer}
        ln -sf ${pkgs.nix-ld}/libexec/nix-ld lib64/ld-linux-x86-64.so.2
        ${extraCommands}
        chown -R -h 1000:100 home/dev workspaces
      '';
      enableFakechroot = false;
      config = {
        User = "dev";
        WorkingDir = "/home/dev";
        Cmd = [ "/bin/bash" ];
        Env = lib.mapAttrsToList (k: v: "${k}=${v}") ({
          HOME = "/home/dev";
          USER = "dev";
          SHELL = "/bin/bash";
          PATH = "/bin:/usr/bin";
          LANG = "C.UTF-8";
          TZ = "America/Sao_Paulo";
          SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
          NIX_SSL_CERT_FILE = "/etc/ssl/certs/ca-bundle.crt";
          NIX_LD = pkgs.stdenv.cc.bintools.dynamicLinker;
          NIX_LD_LIBRARY_PATH = lib.makeLibraryPath nixLdLibs;
        } // env);
      };
    };

  # Started by the sql template's postStartCommand: a Postgres in the
  # container itself, data in a named volume, socket in /tmp.
  pgStart = pkgs.writeShellScriptBin "pg-start" ''
    set -eu
    export PGDATA="''${PGDATA:-$HOME/pgdata}"
    fresh=
    if [ ! -s "$PGDATA/PG_VERSION" ]; then
      initdb -D "$PGDATA" -U dev --auth=trust --encoding=UTF8 >/dev/null
      fresh=1
    fi
    pg_ctl -D "$PGDATA" status >/dev/null 2>&1 \
      || pg_ctl -D "$PGDATA" -w -l "$PGDATA/server.log" \
           -o "-k /tmp -c listen_addresses=localhost" start
    if [ -n "$fresh" ]; then createdb -h /tmp app; fi
  '';
in
{
  base = mkImage "base" { };

  rust = mkImage "rust" {
    packages = with pkgs; [ rustc cargo clippy rustfmt rust-analyzer gcc pkg-config gnumake ];
    env.RUST_SRC_PATH = "${pkgs.rustPlatform.rustLibSrc}";
  };

  python = mkImage "python" {
    packages = with pkgs; [ python3 uv basedpyright ruff ];
  };

  # No clangd here: it brings all of libclang + libllvm (~1.5 GiB of the
  # image's ~2.1). Zed downloads the latest official clangd into the
  # container by itself, and it runs through nix-ld.
  c = mkImage "c" {
    packages = with pkgs; [ gcc gnumake cmake pkg-config gdb ];
  };

  sql = mkImage "sql" {
    packages = with pkgs; [ postgresql sqls pgStart ];
    env = {
      PGDATA = "/home/dev/pgdata";
      PGHOST = "/tmp";
      PGUSER = "dev";
      PGDATABASE = "app";
    };
    # Pre-made with the right owner/mode: a new named volume mounted here
    # is populated from it, so Postgres accepts the directory.
    extraCommands = ''
      mkdir -p home/dev/pgdata
      chmod 700 home/dev/pgdata
    '';
  };

  web = mkImage "web" {
    packages = with pkgs; [ nodejs typescript typescript-language-server eslint prettier ];
  };
}
