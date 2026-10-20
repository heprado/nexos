#!/usr/bin/env bash
set -uo pipefail

expected_kernel_prefix="7.3"
expected_cursor="Vanilla-DMZ"
cursor_size="24"
report_file="${TMPDIR:-/tmp}/marvin-switch-report-$(date +%Y%m%d-%H%M%S).txt"

exec > >(tee "$report_file") 2>&1

echo "Marvin switch report"
echo "Generated: $(date --iso-8601=seconds)"
echo "Report file: $report_file"
echo

running_kernel="$(uname -r)"
echo "Running kernel (current boot): $running_kernel"
if [[ "$running_kernel" == "$expected_kernel_prefix."* ]]; then
  echo "Running kernel status: PASS (7.3 is active)"
else
  echo "Running kernel status: WAITING FOR REBOOT (expected 7.3.x)"
fi

module_dirs=(/run/current-system/kernel-modules/lib/modules/*)
if ((${#module_dirs[@]})); then
  echo "Kernel module release(s) in current system generation:"
  found_73=0
  for module_dir in "${module_dirs[@]}"; do
    release="${module_dir##*/}"
    echo "  - $release"
    [[ "$release" == "$expected_kernel_prefix."* ]] && found_73=1
  done
  if ((found_73)); then
    echo "Configured kernel status: PASS (the switched generation contains 7.3.x)"
  else
    echo "Configured kernel status: FAIL (the switched generation does not contain 7.3.x)"
  fi
else
  echo "Configured kernel status: UNKNOWN (/run/current-system/kernel-modules not found)"
fi

echo
echo "Cursor environment:"
echo "  XCURSOR_THEME=${XCURSOR_THEME:-<unset>}"
echo "  XCURSOR_SIZE=${XCURSOR_SIZE:-<unset>}"
echo "  HYPRCURSOR_THEME=${HYPRCURSOR_THEME:-<unset>}"

cursor_dirs=(
  "$HOME/.nix-profile/share/icons/$expected_cursor"
  "$HOME/.local/state/nix/profile/share/icons/$expected_cursor"
  "/etc/profiles/per-user/${USER:-}/share/icons/$expected_cursor"
  "/run/current-system/sw/share/icons/$expected_cursor"
  "$HOME/.local/share/icons/$expected_cursor"
  "$HOME/.icons/$expected_cursor"
)
cursor_found=""
for cursor_dir in "${cursor_dirs[@]}"; do
  if [[ -e "$cursor_dir/cursors/left_ptr" ]]; then
    cursor_found="$cursor_dir"
    break
  fi
done

if [[ -n "$cursor_found" ]]; then
  echo "Vanilla-DMZ files: PASS ($cursor_found)"
else
  echo "Vanilla-DMZ files: FAIL (theme files not found in the usual profile paths)"
fi

if [[ "${XCURSOR_THEME:-}" == "$expected_cursor" ]]; then
  echo "XCursor selection: PASS (environment points to $expected_cursor)"
else
  echo "XCursor selection: WAITING (this shell still has XCURSOR_THEME=${XCURSOR_THEME:-<unset>})"
fi

if command -v hyprctl >/dev/null 2>&1 && hyprctl setcursor "$expected_cursor" "$cursor_size"; then
  echo "Hyprland cursor test: PASS (setcursor accepted $expected_cursor at ${cursor_size}px)"
else
  echo "Hyprland cursor test: UNKNOWN/FAIL (Hyprland session unavailable or rejected the theme)"
fi

echo
echo "KIO checks (read-only; no build is started):"
if command -v nix >/dev/null 2>&1; then
  if closure="$(nix path-info --recursive /run/current-system 2>&1)"; then
    if grep -Eiq '/[^/]*kio[^/]*($|[[:space:]])' <<< "$closure"; then
      echo "Installed system closure: KIO is present"
      grep -Ei '/[^/]*kio[^/]*($|[[:space:]])' <<< "$closure" | sed 's/^/  /'
    else
      echo "Installed system closure: KIO not found"
    fi
  else
    echo "Installed system closure: UNKNOWN (could not query Nix store)"
    sed 's/^/  /' <<< "$closure"
  fi

  flake_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
  if build_plan="$(nix build "$flake_dir#nixosConfigurations.marvin.config.system.build.toplevel" --dry-run --no-link 2>&1)"; then
    if grep -Eiq 'kio' <<< "$build_plan"; then
      echo "Pending build plan: KIO appears in the dry-run output"
      grep -Ei 'kio' <<< "$build_plan" | sed 's/^/  /'
    else
      echo "Pending build plan: no KIO derivation shown (dry-run only)"
    fi
  else
    echo "Pending build plan: UNKNOWN (dry-run evaluation failed)"
    sed 's/^/  /' <<< "$build_plan"
  fi
else
  echo "KIO checks: UNKNOWN (nix command not found)"
fi

echo
echo "Summary: compare the configured kernel status and cursor checks above before rebooting."
echo "After reboot, run this script again; Running kernel status should say PASS (7.3 is active)."
