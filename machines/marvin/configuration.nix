{ config, lib, pkgs, inputs, ... }:
let
  facts = import ./facts.nix;
  # nixpkgs' nvidia-offload (prime.offload.enableOffloadCmd), plus
  # VK_ICD_FILENAMES. __VK_LAYER_NV_optimus only puts the NVIDIA GPU first
  # in the Vulkan device list; Darling (darling-lol) still got the Intel GPU
  # under it while presenting through NVIDIA's EGL, a black screen. Listing
  # only NVIDIA's ICD hides the Intel GPU. A value already set wins.
  nvidiaOffload = pkgs.writeShellScriptBin "nvidia-offload" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    export VK_ICD_FILENAMES="''${VK_ICD_FILENAMES:-/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.json}"
    exec "$@"
  '';
in
{
  imports = [
    ./hardware-configuration.nix
    ../../modules/nixos/common.nix
    # No ssh.nix: marvin is a laptop roaming arbitrary Wi-Fi networks and
    # never needs to accept SSH (it's only a client, to caixa).
    ../../modules/nixos/desktop.nix
    ../../modules/nixos/gaming.nix
    ../../modules/nixos/home-network.nix
    ../../modules/nixos/refind.nix
    ../../modules/nixos/plymouth-tama
    inputs.lanzaboote.nixosModules.lanzaboote
    inputs.noctalia-ideapad-fan.nixosModules.default
  ];

  networking.hostName = "marvin";

  # Quiet / normal / game presets in a Noctalia bar widget, each setting the
  # firmware fan mode together with the power profile. The firmware's
  # default fan mode barely spins the fan up under load, and CPU and GPU
  # share one heatpipe, so games throttled; max cooling (fan_mode 4, the
  # game preset) fixed it. The module makes fan_mode writable by henrique
  # (after a re-login); the widget saves and restores the preset. Even
  # fan_mode 4 kept switching the fan on and off every few seconds, so the
  # game preset also pins both fans at full speed (~6000/5000 RPM) through
  # the GameZone WMI method SetFanCooling.
  hardware.ideapad-fan = {
    enable = true;
    users = [ "henrique" ];
    fullSpeed.enable = true;
  };
  home-manager.users.henrique.imports = [ inputs.noctalia-ideapad-fan.homeManagerModules.default ];
  home-manager.users.henrique.programs.noctalia-ideapad-fan.enable = true;

  # unar: free RAR (incl. RAR5) extractor, unlike unfree unrar.
  # sbctl: manages marvin's Secure Boot keys (see boot.lanzaboote below).
  # nvtop: live GPU temperature/usage monitor, NVIDIA-only build.
  # nvidiaOffload: see the let block above.
  environment.systemPackages = [ pkgs.unzip pkgs.unar pkgs.sbctl pkgs.nvtopPackages.nvidia pkgs.bubblewrap pkgs.socat nvidiaOffload ];

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
      # `nvidia-offload`, for running a program on the NVIDIA GPU (e.g.
      # Steam launch options: `nvidia-offload %command%`), comes from
      # nvidiaOffload in the let block instead, which also sets
      # VK_ICD_FILENAMES.
      offload.enableOffloadCmd = false;
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
      # Use Xwayland for Proton games; some games do not capture keyboard
      # input correctly with Wine's native Wayland driver.
      PROTON_ENABLE_WAYLAND = "0";
    };
  };

  # Steam's Vulkan shader pre-caching (fossilize_replay) uses only a few
  # threads by default, so e.g. Deadlock's recompile after every NVIDIA
  # driver update took ages. Give it all 12 of the i7-10750H's threads.
  home-manager.users.henrique.xdg.dataFile."Steam/steam_dev.cfg".text = ''
    unShaderBackgroundProcessingThreads 12
  '';

  # Umbriel renders on the Intel GPU, which is listed first in WLR_DRM_DEVICES:
  # with NVIDIA first, wlroots found no buffer format for the Intel-wired eDP-1
  # ("Failed to pick primary buffer format"), which stayed dark while it retried
  # nonstop. HDMI is wired to NVIDIA, so its frames get copied across GPUs, except
  # for fullscreen games, which reach it through direct scanout. The cardN numbers
  # aren't stable across boots, and by-path names contain ':' (the variable's
  # separator), so udev gives each GPU a fixed symlink keyed on its PCI address
  # from facts.nix. ID_PATH is matched exactly so the early-boot
  # simple-framebuffer card (which also sits under the Intel PCI device) doesn't
  # claim the Intel name.
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
    '';
  environment.sessionVariables.WLR_DRM_DEVICES = "/dev/dri/intel-igpu:/dev/dri/nvidia-dgpu";

  # Streaming and discovery ports, only on the home Wi-Fi ("Tricks") and on
  # a cable: marvin is a laptop, and on anyone else's Wi-Fi these stay
  # closed. The wired profile isn't tied to one network -- it's what any
  # cable in enp12s0 gets -- so a cable plugged in elsewhere opens them too.
  # The modules that would open them everywhere are told not to.
  nexos.homeNetwork = {
    connections = [
      "b0efb593-69d3-47e9-915d-a293249fad3d" # Tricks (Wi-Fi)
      "e4fb6299-a298-307e-b057-3b7137dec3fb" # Conexão cabeada 1 (enp12s0)
    ];
    allowedTCPPorts = [
      # Steam Remote Play.
      27036 27037
      # WiVRn (Quest 3 streaming, see services.wivrn below).
      9757
    ];
    allowedUDPPorts = [
      # Steam: peer discovery, Remote Play.
      27036 10400 10401
      # WiVRn streaming; mDNS, so the headset finds marvin by itself.
      9757 5353
    ];
    # Steam Remote Play.
    allowedUDPPortRanges = [ { from = 27031; to = 27035; } ];
  };
  programs.steam.remotePlay.openFirewall = lib.mkForce false;
  services.avahi.openFirewall = false;

  # Meta Quest 3 as a PC VR headset over Wi-Fi: WiVRn's server streams
  # OpenXR to the WiVRn app on the Quest (from the Meta store), and starts
  # WayVR (ex wlx-overlay-s) once the headset connects, to see and use the
  # desktop in VR. Firewall ports are in nexos.homeNetwork above, not
  # openFirewall. Steam games find the runtime through importOXRRuntimes.
  services.wivrn = {
    enable = true;
    # Started from the launcher instead (desktop entry below): running from
    # login, it showed a pairing PIN notification at every start and kept
    # the server published on the network.
    autoStart = false;
    # Encodes on the GTX 1650's NVENC. cudaSupport only builds WiVRn's NVENC
    # encoder, which loads libnvidia-encode from the driver at runtime, so
    # no CUDA toolkit (nor anything unfree); WiVRn itself builds locally.
    package = pkgs.wivrn.override { cudaSupport = true; };
    # Realtime priority (CAP_SYS_NICE) for asynchronous reprojection; drops
    # the unit's sandboxing, which the capability can't coexist with.
    highPriority = true;
    # The server's compositor renders on NVIDIA too, so frames reach NVENC
    # without a copy from the Intel iGPU (same variables as nvidia-offload).
    monadoEnvironment = {
      __NV_PRIME_RENDER_OFFLOAD = "1";
      __NV_PRIME_RENDER_OFFLOAD_PROVIDER = "NVIDIA-G0";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
      __VK_LAYER_NV_optimus = "NVIDIA_only";
    };
    steam.importOXRRuntimes = true;
    config = {
      enable = true;
      json.application = [ pkgs.wayvr ];
    };
  };
  # The server is a user service; only henrique's session runs it.
  systemd.user.services.wivrn.unitConfig.ConditionUser = lib.mkForce "henrique";
  # Replaces WiVRn's own launcher entry (same desktop file ID). That one
  # opens the dashboard, which can start a server of its own, outside the
  # unit and so without monadoEnvironment's NVIDIA variables. This starts
  # the unit first, then opens the dashboard on it.
  home-manager.users.henrique.xdg.desktopEntries."io.github.wivrn.wivrn" = {
    name = "WiVRn server";
    genericName = "WiVRn dashboard";
    comment = "Play your PC VR games on a standalone headset";
    icon = "io.github.wivrn.wivrn";
    exec = toString (pkgs.writeShellScript "wivrn-launch" ''
      systemctl --user start wivrn.service
      exec ${config.services.wivrn.package}/bin/wivrn-dashboard
    '');
    categories = [ "Network" ];
    settings.Keywords = "VR;Virtual reality;OpenVR;OpenXR;";
    actions.stop = {
      name = "Parar servidor";
      exec = "systemctl --user stop wivrn.service";
    };
  };
  # WayVR types and clicks on the desktop through /dev/uinput.
  hardware.uinput.enable = true;
  users.users.henrique.extraGroups = [ "uinput" ];
  # ~/codigos/compartilhamento-de-video-legal publishes its nginx on
  # 192.168.15.141:443 from rootless Podman, which can only bind ports at or
  # above this. 443 is deliberately NOT in allowedTCP/UDPPorts above: only
  # marvin itself (loopback path to its own IP) reaches it, never the LAN.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 443;

  # Builds aarch64 NixOS systems (~/codigos/nixos-switch, the Switch Lite)
  # through QEMU user emulation, so their packages come from the binary
  # cache instead of being cross-compiled from source; also registers
  # aarch64-linux as an extra platform for the nix daemon.
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

  # The proprietary driver above (see modules/nixos/unfree.nix).
  nexos.unfree = [ "nvidia-x11" "nvidia-kernel-modules" "nvidia-settings" "nvidia-persistenced" ];

  home-manager.users.henrique.home.packages = [
    # Quickshell's own CLI (`qs`), for running shell configs by hand.
    # Noctalia bundles Quickshell but doesn't put it on PATH.
    pkgs.quickshell
    # To put Moonlight on the TV (see apps2samsung.nix).
    (pkgs.callPackage ./apps2samsung.nix { })
    # OpenAI's coding agent; reads ~/.codex/AGENTS.md (modules/home/ai.nix).
    pkgs.codex
    # Torrent client (Qt GUI).
    pkgs.qbittorrent
    (pkgs.writeShellApplication {
      name = "patch_switch";
      runtimeInputs = [ pkgs.python3 pkgs.util-linux pkgs.udisks pkgs.coreutils ];
      text = ''
        exec python3 -I ${../../scripts/nintendo-switch-package3-splash.py} "$@"
      '';
    })
  ];

  sops.defaultSopsFile = ../../secrets/marvin.yaml;

  # Bump to whatever release you actually install; do not change on upgrades.
  system.stateVersion = "24.05";
}
