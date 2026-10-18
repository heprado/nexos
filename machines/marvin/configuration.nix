{ config, lib, pkgs, inputs, ... }:
let
  facts = import ./facts.nix;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    # No ssh.nix: marvin is a laptop roaming arbitrary Wi-Fi networks and
    # never needs to accept SSH (it's only a client, to caixa).
    ../../modules/nixos/desktop-hyprland.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/refind.nix
    ../../modules/nixos/plymouth-tama
    inputs.lanzaboote.nixosModules.lanzaboote
    ./darling-lol.nix
  ];

  networking.hostName = "marvin";

  # unar: free RAR (incl. RAR5) extractor, unlike unfree unrar.
  # sbctl: manages marvin's Secure Boot keys (see boot.lanzaboote below).
  # nvtop: live GPU temperature/usage monitor, NVIDIA-only build.
  environment.systemPackages = [ pkgs.unzip pkgs.unar pkgs.sbctl pkgs.nvtopPackages.nvidia ];

  # Lives here (not hardware-configuration.nix) since that file gets
  # wholesale-replaced by `nixos-generate-config` output during install,
  # which would silently drop bootloader config if it lived there.
  #
  # Secure Boot via lanzaboote: it still installs systemd-boot, but signs it
  # and each generation's UKI with the keys in pkiBundle, so the NixOS
  # module's own systemd-boot installer has to be off. The other
  # systemd-boot options (common.nix's consoleMode) are still read by
  # lanzaboote, into its loader.conf. Keys are created and enrolled by hand
  # (`sbctl create-keys`, then `sbctl enroll-keys --append --microsoft`
  # with the firmware in Setup Mode): appending keeps the db/KEK/dbx
  # Windows Update had installed, Microsoft's keys keep Windows' boot
  # manager and the NVIDIA GOP option ROM trusted.
  boot.loader.systemd-boot.enable = false;
  boot.lanzaboote = {
    enable = true;
    pkiBundle = "/var/lib/sbctl";
    # The ESP is only 512M and each initrd is ~210M (the NVIDIA module and
    # its GSP firmware are in it, see boot.initrd.kernelModules below), so
    # only two distinct kernel+initrd pairs fit.
    configurationLimit = 2;
  };

  # First boot menu: NixOS (-> systemd-boot's generation list) or
  # darling-lol (~/codigos/darling-lol-iso, League of Legends on Darling),
  # installed on the NVMe in place of Windows, with its own ESP and
  # lanzaboote's systemd-boot, signed with marvin's keys.
  nexos.refind = {
    enable = true;
    otherOs = {
      name = "League of Legends";
      esp = "101973e6-f331-42bf-9522-66f629de36dd";
      loader = "/EFI/systemd/systemd-bootx64.efi";
      # League of Legends' "L" emblem: the SVG from the official LoL wiki
      # (wiki.leagueoflegends.com, File:League_of_Legends_icon.svg;
      # copyrighted to Riot Games), already rendered at 128x128.
      icon = ../../users/henrique/league-of-legends.png;
    };
    timeout = 10;
    # The laptop panel's native mode -- the firmware only lights that one up.
    resolution = "1920x1080";
    # users/henrique/tama, the original, at 1920x1080 and opaque.
    background = ../../users/henrique/tama-wallpaper.png;
    # Tool icons and label font from refind-theme-regular
    # (github.com/bobafetthotmail/refind-theme-regular, icons/128-48 and
    # fonts/source-code-pro-extralight-14.png); the selection highlights
    # are plain rounded squares in the palette's hover color (#2B3240),
    # since the theme's own light/dark ones washed out the white snowflake
    # or vanished on the black background.
    theme = ./refind-theme;
  };

  # Boot splash: the firmware's own logo (BGRT, Lenovo's) with a spinning
  # NixOS snowflake under it. The firmware only ever lights up the laptop
  # panel, so the menu above can't reach the HDMI monitor; Plymouth runs
  # after the kernel's DRM drivers are up, so it can. The HDMI port is
  # wired to NVIDIA, so its driver (not just i915) is loaded early in the
  # initrd for Plymouth to see that output too. The Tama theme itself is
  # modules/nixos/plymouth-tama (imported above).
  boot.initrd.kernelModules = [ "i915" "nvidia" "nvidia_modeset" "nvidia_uvm" "nvidia_drm" ];

  # The shared monitor sees no HDMI signal until nvidia-drm is up (~4s in),
  # so its auto input detection wanders off to caixa's DisplayPort. Pull it
  # back from the initrd, where nvidia-drm is already loaded (see above), so
  # the Plymouth splash shows up there as well.
  nexos.takeMonitor = {
    enable = true;
    initrd = true;
  };

  # GPU: NVIDIA GTX 1650 (Turing/TU117) + Intel UHD (Comet Lake-H) hybrid
  # graphics, PRIME offload -- Intel iGPU stays the default renderer
  # (battery-friendly), NVIDIA is available on demand for games.
  hardware.graphics = {
    enable = true;
    enable32Bit = true; # required for Steam/Proton
  };

  hardware.nvidia = {
    modesetting.enable = true;
    open = false; # TU117 (Turing) predates the open kernel module's support window
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    prime = {
      offload.enable = true;
      # Installs `nvidia-offload`, for running a program on the NVIDIA GPU
      # (e.g. Steam launch options: `nvidia-offload %command%`).
      offload.enableOffloadCmd = true;
      # Detected by install.sh and recorded in facts.nix.
      inherit (facts) intelBusId nvidiaBusId;
    };
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  # Steam and everything it launches run on the NVIDIA GPU, so games don't
  # need `nvidia-offload %command%` each. Same variables nvidia-offload
  # sets; __VK_LAYER_NV_optimus is the one that matters for Proton (DXVK
  # and VKD3D are Vulkan).
  programs.steam.package = pkgs.steam.override {
    extraEnv = {
      __NV_PRIME_RENDER_OFFLOAD = "1";
      __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      __VK_LAYER_NV_optimus = "NVIDIA_only";
      # Proton (10+) draws games through Wine's native Wayland driver
      # instead of Xwayland. A game that misbehaves can opt out with
      # `PROTON_ENABLE_WAYLAND=0 %command%` in its launch options.
      PROTON_ENABLE_WAYLAND = "1";
    };
  };

  # Steam's Vulkan shader pre-caching (fossilize_replay) uses only a few
  # threads by default, so e.g. Deadlock's recompile after every NVIDIA
  # driver update took ages. Give it all 12 of the i7-10750H's threads.
  home-manager.users.henrique.xdg.dataFile."Steam/steam_dev.cfg".text = ''
    unShaderBackgroundProcessingThreads 12
  '';

  # Hyprland itself renders on the NVIDIA GPU, even though apps still
  # default to Intel (PRIME offload above). The HDMI port is wired to the
  # NVIDIA card, so with Intel as the compositor's renderer every HDMI frame
  # (1080p@120Hz) had to be copied across GPUs, which made animations crawl
  # there. Aquamarine uses the first device in AQ_DRM_DEVICES as its
  # renderer. The cardN numbers aren't stable across boots, and by-path
  # names contain ':' (AQ_DRM_DEVICES' separator), so udev gives each GPU a
  # fixed symlink keyed on its PCI address from facts.nix. ID_PATH is
  # matched exactly so the early-boot simple-framebuffer card (which also
  # sits under the Intel PCI device) doesn't claim the Intel name.
  services.udev.extraRules =
    let
      # "PCI:1:0:0" (decimal, NixOS format) -> "pci-0000:01:00.0" (hex, udev ID_PATH).
      idPath = busId:
        let
          hex2 = n: lib.toLower (lib.fixedWidthString 2 "0" (lib.toHexString (lib.toInt n)));
          parts = lib.splitString ":" busId;
        in
        "pci-0000:${hex2 (lib.elemAt parts 1)}:${hex2 (lib.elemAt parts 2)}.${lib.elemAt parts 3}";
    in
    ''
      SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ENV{ID_PATH}=="${idPath facts.nvidiaBusId}", SYMLINK+="dri/nvidia-dgpu"
      SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ENV{ID_PATH}=="${idPath facts.intelBusId}", SYMLINK+="dri/intel-igpu"
      # NVIDIA's render node, for Sunshine's encoder (see below).
      SUBSYSTEM=="drm", KERNEL=="renderD[0-9]*", ENV{ID_PATH}=="${idPath facts.nvidiaBusId}", SYMLINK+="dri/nvidia-render"
    '';
  environment.sessionVariables.AQ_DRM_DEVICES = "/dev/dri/nvidia-dgpu:/dev/dri/intel-igpu";

  # Game streaming to the living-room TV (Samsung, Moonlight for Tizen).
  # Pair once from the web UI at https://localhost:47990 (it asks for a
  # login on first use), typing the PIN the TV shows.
  services.sunshine = {
    enable = true;
    # Started only when wanted, from the launcher (below) or with
    # `systemctl --user start sunshine`.
    autoStart = false;
    # For KMS capture (settings.capture below).
    capSysAdmin = true;
    # Not openFirewall: it'd also open the web UI (47990) to the LAN. The
    # streaming ports are opened below instead.
    settings = {
      sunshine_name = "marvin";
      # Captured and encoded on the GTX 1650, which draws every output
      # (AQ_DRM_DEVICES above). Wayland capture plus Intel Quick Sync gave a
      # black screen: Intel can't import NVIDIA's buffers ("Unsupported
      # modifier"). Vulkan Video rather than NVENC, which needs a CUDA
      # build; Vulkan only works with KMS capture.
      capture = "kms";
      encoder = "vulkan";
      adapter_name = "/dev/dri/nvidia-render";
    };
  };
  # Sunshine's ports (base 47989): HTTPS/HTTP pairing and RTSP over TCP,
  # video/control/audio/mic over UDP. mDNS (so Moonlight finds marvin on
  # its own) is opened by Avahi's module.
  networking.firewall = {
    allowedTCPPorts = [ 47984 47989 48010 ];
    allowedUDPPorts = [ 47998 47999 48000 48002 48010 ];
  };
  # ~/codigos/compartilhamento-de-video-legal publishes its nginx on
  # 192.168.15.141:443 from rootless Podman, which can only bind ports at or
  # above this. 443 is deliberately NOT in allowedTCP/UDPPorts above: only
  # marvin itself (loopback path to its own IP) reaches it, never the LAN.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 443;
  # Replaces the package's own launcher (same desktop-file ID), which runs
  # a bare `sunshine` outside the service, without the settings above.
  home-manager.users.henrique.xdg.desktopEntries."dev.lizardbyte.app.Sunshine" = {
    name = "Sunshine";
    comment = "Start game streaming (Moonlight)";
    icon = "dev.lizardbyte.app.Sunshine";
    exec = "systemctl --user start sunshine";
    actions.stop = {
      name = "Stop";
      exec = "systemctl --user stop sunshine";
    };
  };

  # The proprietary driver above (see modules/nixos/unfree.nix).
  nexos.unfree = [ "nvidia-x11" "nvidia-kernel-modules" "nvidia-settings" "nvidia-persistenced" ];

  home-manager.users.henrique.home.packages = [
    # Quickshell's own CLI (`qs`), for running shell configs by hand.
    # Noctalia bundles Quickshell but doesn't put it on PATH.
    pkgs.quickshell
    # To put Moonlight on the TV (see apps2samsung.nix).
    (pkgs.callPackage ./apps2samsung.nix { })
  ];

  sops.defaultSopsFile = ../../secrets/marvin.yaml;

  # Bump to whatever release you actually install; do not change on upgrades.
  system.stateVersion = "24.05";
}
