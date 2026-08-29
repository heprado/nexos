{ pkgs, ... }:
{
  # Zed, wrapped so the launch command is `IDE` instead of `zeditor`.
  home.packages = [
    (pkgs.symlinkJoin {
      name = "zed-editor-ide";
      paths = [ pkgs.zed-editor ];
      postBuild = ''
        ln -s ${pkgs.zed-editor}/bin/zeditor $out/bin/IDE
      '';
    })
  ];

  # The package itself is installed above via the IDE-renamed wrapper --
  # this only manages settings.json. It's merged into the existing file
  # (not overwritten; see mutableUserSettings, default true), so hand
  # edits survive, but the merge round-trips through JSON and drops any
  # comments in settings.json.
  programs.zed-editor = {
    enable = true;
    package = null;
    userSettings = {
      # Load the active project's direnv environment (e.g. a devenv
      # shell's QML_IMPORT_PATH) before spawning language servers --
      # otherwise LSPs miss project-local env vars devenv/direnv set.
      load_direnv = "direct";
    };
  };
}
