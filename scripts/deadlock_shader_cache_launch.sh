set -euo pipefail

cache_root="$HOME/.cache/nexos/deadlock-nvidia"

if [[ -f "$cache_root/.ready" ]]; then
  mapfile -t cache_names < <(
    find "$cache_root/GLCache" -type f -name 'steam*.bin' -printf '%f\n' \
      2>/dev/null | sed 's/\.bin$//' | sort -u
  )
else
  cache_names=()
fi

if (( ${#cache_names[@]} )); then
  readonly_names=$(IFS=';'; printf '%s' "${cache_names[*]}")
  export __GL_SHADER_DISK_CACHE_PATH="$cache_root"
  export __GL_SHADER_DISK_CACHE_APP_NAME="deadlock_live"
  export __GL_SHADER_DISK_CACHE_SIZE=17179869184
  export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
  export __GL_SHADER_DISK_CACHE_READ_ONLY_APP_NAME="$readonly_names"
fi

exec "$@"
