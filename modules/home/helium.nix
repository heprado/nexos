{ inputs, pkgs, ... }:
{
  imports = [ inputs.helium-flake.homeModules.default ];

  programs.helium = {
    enable = true;
    package = pkgs.helium;

    # WebGPU on Linux runs over Vulkan (Dawn), and VAAPI video decode needs
    # its own opt-in feature flag.
    #
    # --enable-unsafe-webgpu is disabled for now (see git log for why it
    # was added -- a specific WebGPU site). Chrome only auto-enables
    # WebGPU without this flag for Intel Gen12+ iGPUs; this Skylake HD 530
    # is Gen9, so it still needs the flag if that (or another) WebGPU site
    # comes up again -- just re-add "--enable-unsafe-webgpu" to the list
    # below.
    flags = [
      "--enable-features=Vulkan,AcceleratedVideoDecodeLinuxGL"
    ];
  };

  # mimeapps.list is managed, see modules/home/reading.nix.
  xdg.mimeApps.defaultApplications."x-scheme-handler/mailto" = "helium.desktop";
}
