{ inputs, pkgs, ... }:
{
  imports = [ inputs.helium-flake.homeModules.default ];

  programs.helium = {
    enable = true;
    package = pkgs.helium;

    # WebGPU on Linux runs over Vulkan (Dawn); caixa's Skylake HD 530 iGPU
    # is old enough that Chromium's GPU blocklist disables some
    # accelerated features on it by default, so force them on explicitly.
    # VAAPI video decode also needs its own opt-in feature flag.
    flags = [
      "--enable-features=Vulkan,AcceleratedVideoDecodeLinuxGL"
      "--enable-unsafe-webgpu"
      "--ignore-gpu-blocklist"
    ];
  };
}
