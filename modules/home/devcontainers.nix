{ pkgs, ... }:
# `devc-load <lang>...` builds a dev container image from the nexos flake
# (devcontainers/images.nix, exposed as packages.devcontainer-<lang>) and
# loads it into henrique's rootless Podman. The templates call it as their
# initializeCommand, so opening a project in Zed loads its image when
# needed; `devc-load` alone refreshes every nexos image Podman already has
# (after a rebuild that updated Zed, say).
#
# Nothing here references the images, so they stay out of the system
# closure: they're built on demand (from cache.nixos.org, mostly), live in
# Podman's storage, and their store paths are left for `nix gc`.
#
# `nexos` is the registry entry for the active system's own flake
# (nix.registry.nexos in modules/nixos/common.nix), so an image's Zed
# remote server always matches the Zed that's running. Each image is also
# tagged with its store hash: one already loaded is skipped, and older tags
# of the same image are removed (podman keeps one a container still uses).
let
  devcLoad = pkgs.writeShellApplication {
    name = "devc-load";
    runtimeInputs = [ pkgs.coreutils pkgs.gnugrep pkgs.gnused ];
    text = ''
      # The system's podman, with its helpers and the setuid uidmap wrappers.
      export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$PATH"

      langs=("$@")
      if [ ''${#langs[@]} -eq 0 ]; then
        mapfile -t langs < <(podman images --format '{{.Repository}}' \
          | grep -o '^localhost/nexos/devcontainer-.*' | sed 's|.*/devcontainer-||' | sort -u)
        [ ''${#langs[@]} -gt 0 ] || { echo "devc-load: nenhuma imagem do nexos no podman" >&2; exit 0; }
      fi

      rc=0
      for lang in "''${langs[@]}"; do
        repo="localhost/nexos/devcontainer-$lang"
        # flake-registry "": `nexos` is in the system registry; skip the
        # global one, which is fetched over the network on every call.
        if ! out=$(nix build --no-link --print-out-paths --option flake-registry "" \
                     "nexos#devcontainer-$lang"); then
          echo "devc-load: não consegui montar $repo" >&2; rc=1; continue
        fi
        id=$(basename "$out" | cut -c1-32)
        if ! podman image exists "$repo:$id"; then
          echo "devc-load: carregando $repo"
          if "$out" | podman load -q >/dev/null; then
            podman tag "$repo:latest" "$repo:$id"
          else
            echo "devc-load: falhou ao carregar $repo" >&2; rc=1; continue
          fi
        fi
        # `|| true`: no old tag is the usual case, and grep exits 1 on it.
        podman images --format '{{.Repository}}:{{.Tag}}' "$repo" \
          | { grep -vxF -e "$repo:$id" -e "$repo:latest" || true; } \
          | while read -r old; do podman rmi "$old" >/dev/null 2>&1 || true; done
      done
      exit "$rc"
    '';
  };
in
{
  home.packages = [ devcLoad ];

  # Zed talks to Podman directly for dev containers.
  programs.zed-editor.userSettings.use_podman = true;
}
