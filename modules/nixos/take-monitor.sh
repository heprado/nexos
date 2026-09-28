# Switches every external monitor ddcutil can reach over DDC/CI (VCP 0x60,
# Input Source) to the input this host is plugged into. The input is worked
# out from the DRM connector's type (HDMI/DP/DVI) against the standard MCCS
# codes the monitor says it supports; `overrides` (serial -> code) settles
# monitors with more than one input of that type. Monitors already on this
# host's input are left alone, since re-selecting the current input can make
# them blank and resync. Retries because right after boot the GPU's DDC bus
# may not be up yet, and a monitor may still be busy auto-scanning inputs.
#
# Expects PATH (ddcutil, coreutils, gnugrep, gawk) and an `overrides` associative
# array to be set up by the Nix wrapper.

declare -A done_monitors=()

# Standard MCCS VCP 0x60 codes per connector type, in port order.
candidates_for() {
  case $1 in
    *-HDMI-*) echo "11 12" ;;
    *-DP-*) echo "0f 10" ;;
    *-DVI-*) echo "03 04" ;;
  esac
}

take() { # bus connector serial
  local bus=$1 connector=$2 serial=$3 code supported candidate matches=()

  if [[ -n $serial && -n ${overrides[$serial]:-} ]]; then
    code=${overrides[$serial]#0x}
  else
    # "... vcp(... 60(03 0F 11) ...)" -> "03 0f 11"
    supported=$(ddcutil --bus "$bus" capabilities --terse 2>/dev/null |
      grep -oE ' 60\([0-9A-Fa-f ]+\)') || return 1
    supported=${supported#* 60(}
    supported=${supported%)}
    supported=${supported,,}
    for candidate in $(candidates_for "$connector"); do
      [[ " $supported " == *" $candidate "* ]] && matches+=("$candidate")
    done
    if (( ${#matches[@]} != 1 )); then
      echo "$serial on $connector: can't tell which input this host is on (supported: ${supported:-none}), skipping; set nexos.takeMonitor.overrides.\"$serial\""
      return 0
    fi
    code=${matches[0]}
  fi

  if [[ $(ddcutil --bus "$bus" --terse getvcp 60 2>/dev/null) == *" x$code" ]]; then
    echo "$serial on $connector: already on 0x$code"
    return 0
  fi
  ddcutil --bus "$bus" setvcp 60 "0x$code" || return 1
  echo "$serial on $connector: switched to 0x$code"
}

for _ in $(seq 20); do
  pending=0 found=0
  # "Display N" blocks: "I2C bus: /dev/i2c-6", "DRM connector: card0-HDMI-A-1",
  # "Monitor: AUS:VG278:M3LMQS291655". Laptop panels come out as
  # "Invalid display" (no DDC/CI) and are skipped.
  while read -r bus connector serial; do
    found=1
    key=${serial:-bus$bus} # some monitors report no serial
    [[ -n ${done_monitors[$key]:-} ]] && continue
    if take "$bus" "$connector" "$serial"; then
      done_monitors[$key]=1
    else
      pending=1
    fi
  done < <(ddcutil detect --terse 2>/dev/null | awk '
    /^Display / { valid = 1; next }
    /^Invalid display/ { valid = 0; next }
    valid && /I2C bus:/ { sub(".*/i2c-", ""); bus = $0 }
    valid && /DRM connector:/ { connector = $NF }
    valid && /Monitor:/ { n = split($NF, m, ":"); print bus, connector, m[n] }')

  (( found && !pending )) && exit 0
  sleep 1
done
exit 1
