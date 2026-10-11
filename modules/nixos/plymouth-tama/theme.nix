# Plymouth theme: nixos-bgrt's spinning NixOS snowflake, but with Tama
# (users/henrique/tama-robot.gif) centered on screen instead of the
# firmware's Lenovo logo.
#
# two-step only loops one animation (the "throbber"), so every frame in
# frames/ is a composite: the GIF at 75% (405x480, so it fits above
# the snowflake on a 1080px-tall screen) with nixos-bgrt's snowflake
# 100px below it (its top at y=580 in the frame). two-step plays the
# whole throbber in 2s (THROBBER_DURATION in
# ply-throbber.c), so 40 frames = the 20-frame, 1s GIF twice at its own
# speed plus one snowflake turn. Opaque on black and 256 colors, like the
# GIF, since all of this lives in every initrd on a 512M ESP. They were
# made with (gif-NN.png being the GIF's frames, -coalesce'd and resized):
#
#   magick -size 405x674 xc:black \
#     gif-$((i % 20)).png -geometry +0+0 -composite \
#     <nixos-bgrt>/throbber-$((i * 30 / 40 + 1)).png -geometry +170+580 -composite \
#     -colors 256 PNG8:throbber-$((i + 1)).png       # i = 0..39
#
# The password prompt (LUKS) is two-step's own, with nixos-bgrt's images;
# two-step hides the throbber while it's up, so it's just the prompt on
# black then.
{ runCommand, nixos-bgrt-plymouth }:
runCommand "plymouth-theme-tama" { } ''
  t=$out/share/plymouth/themes/tama
  mkdir -p $t
  cp ${builtins.path { path = ./frames; name = "plymouth-tama"; }}/throbber-*.png $t/
  cp ${nixos-bgrt-plymouth}/share/plymouth/themes/nixos-bgrt/images/{bullet,capslock,entry,keyboard,keymap-render,lock}.png $t/

  # The frame's top at y=300 puts the GIF's center on the screen's (540),
  # so the frame's center (337px down) goes at (300+337)/1080 = .5898.
  cat > $t/tama.plymouth <<PLY
  [Plymouth Theme]
  Name=Tama
  Description=Tama with the spinning NixOS logo
  ModuleName=two-step

  [two-step]
  Font=Cantarell 20
  ImageDir=$t
  DialogHorizontalAlignment=.5
  DialogVerticalAlignment=.8
  HorizontalAlignment=.5
  VerticalAlignment=.5898148
  Transition=none
  TransitionDuration=0.0
  BackgroundStartColor=0x000000
  BackgroundEndColor=0x000000
  ProgressBarBackgroundColor=0x606060
  ProgressBarForegroundColor=0xffffff
  MessageBelowAnimation=true

  [boot-up]
  UseEndAnimation=false

  [shutdown]
  UseEndAnimation=false

  [reboot]
  UseEndAnimation=false
  PLY
''
