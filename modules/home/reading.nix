{ pkgs, ... }:
let
  foliate = "com.github.johnfactotum.Foliate.desktop";
in
{
  home.packages = [
    # GTK4 ebook reader, Wayland-native.
    pkgs.foliate
  ];

  # home-manager now owns ~/.config/mimeapps.list (read-only symlink), so
  # apps can no longer write their own associations there -- every default
  # has to be declared here or next to its app (chat.nix, helium.nix,
  # ai.nix). The attrsets merge across modules.
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "application/epub+zip" = foliate;
    "application/x-mobipocket-ebook" = foliate;
    "application/vnd.amazon.mobi8-ebook" = foliate;
    "application/x-fictionbook+xml" = foliate;
    "application/x-zip-compressed-fb2" = foliate;
    "application/vnd.comicbook+zip" = foliate;
    "x-scheme-handler/opds" = foliate;
  };
}
