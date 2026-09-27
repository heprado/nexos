#!/usr/bin/env bash
# Interactive installer for marvin. Run as root from the NixOS installer
# ISO, inside a clone of this repo:
#
#   sudo ./machines/marvin/install.sh            # full install
#   ./machines/marvin/install.sh --dry-run       # detect + show facts only,
#                                                # touches no disk/file
#
# Automates README.md's "Option A" steps for marvin: pick the disk, detect
# the PRIME bus IDs, write machines/marvin/facts.nix, run disko, place the
# sops age key, generate hardware-configuration.nix, run nixos-install and
# copy the repo (with the generated files) into the new system.
#
# The age private key is read from keys/marvin-key.txt (gitignored, so a
# fresh clone won't have it -- bring it via USB) or from $MARVIN_AGE_KEY.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
facts="$repo/machines/marvin/facts.nix"
hwconf="$repo/machines/marvin/hardware-configuration.nix"
key="${MARVIN_AGE_KEY:-$repo/keys/marvin-key.txt}"

dry_run=0
[[ "${1:-}" == "--dry-run" ]] && dry_run=1

die() { echo "erro: $*" >&2; exit 1; }
# Fatal for a real install, just a warning under --dry-run.
check() { if (( dry_run )); then echo "aviso: $*" >&2; else die "$*"; fi; }
ask() { local reply; read -rp "$1 " reply; printf '%s' "$reply"; }

# --- preflight ---------------------------------------------------------------

if (( ! dry_run )); then
  (( EUID == 0 )) || die "rode como root (sudo), ou use --dry-run"
  [[ -d /sys/firmware/efi ]] || die "não bootou em modo UEFI (systemd-boot precisa de UEFI)"
fi

# The flake only sees git-tracked files, so an untracked secrets/marvin.yaml
# would make nixos-install fail late, after the disk is already wiped.
if [[ ! -f "$repo/secrets/marvin.yaml" ]]; then
  check "secrets/marvin.yaml não existe (veja secrets/README.md)"
elif command -v git >/dev/null; then
  git -C "$repo" ls-files --error-unmatch secrets/marvin.yaml >/dev/null 2>&1 \
    || check "secrets/marvin.yaml não está no git: dê commit (ou git add) antes -- o flake não enxerga arquivo não rastreado"
else
  echo "aviso: git não encontrado, não deu pra conferir se secrets/marvin.yaml está commitado"
fi

if (( ! dry_run )); then
  while [[ ! -f "$key" ]]; do
    echo "Chave age do marvin não encontrada em $key"
    key=$(ask "Caminho da marvin-key.txt (ex.: /run/media/pendrive/marvin-key.txt):")
  done
fi

# --- disk --------------------------------------------------------------------

mapfile -t disks < <(lsblk -dpno NAME,TYPE | awk '$2 == "disk" { print $1 }')
(( ${#disks[@]} )) || die "nenhum disco encontrado"

echo
echo "Discos disponíveis:"
for i in "${!disks[@]}"; do
  d=${disks[$i]}
  info=$(lsblk -dno SIZE,TRAN,MODEL "$d" | tr -s ' ')
  fstypes=$(lsblk -nro FSTYPE "$d" | grep . | sort -u | paste -sd, - || true)
  notes=""
  [[ -n "$fstypes" ]] && notes+="  [contém: $fstypes]"
  [[ "$fstypes" == *ntfs* ]] && notes+="  <-- provavelmente o Windows!"
  lsblk -nro MOUNTPOINTS "$d" | grep -q . && notes+="  [em uso/montado]"
  printf '  %d) %-14s %s%s\n' "$((i + 1))" "$d" "$info" "$notes"
done

while :; do
  n=$(ask "Em qual disco instalar o marvin? (número)")
  [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#disks[@]} )) && break
  echo "opção inválida"
done
disk=${disks[$((n - 1))]}
if lsblk -nro MOUNTPOINTS "$disk" | grep -q .; then
  check "$disk tem partições montadas (é o pendrive do instalador?)"
fi

# Record a stable by-id path rather than /dev/sdX, which can change between
# boots depending on what else is attached.
target=$disk
for link in /dev/disk/by-id/*; do
  name=$(basename "$link")
  [[ "$name" == *-part* || "$name" == wwn-* || "$name" == *-eui.* ]] && continue
  if [[ $(readlink -f "$link") == "$disk" ]]; then target=$link; break; fi
done

# --- PRIME bus IDs -----------------------------------------------------------

# /sys PCI address (hex "0000:01:00.0") -> NixOS format (decimal "PCI:1:0:0").
pci_id() {
  local addr=${1#*:}
  local bus=${addr%%:*} rest=${addr#*:}
  local dev=${rest%%.*} fn=${rest#*.}
  printf 'PCI:%d:%d:%d' "$((16#$bus))" "$((16#$dev))" "$((16#$fn))"
}

intel=() nvidia=()
for dev in /sys/bus/pci/devices/*; do
  # Display controllers only: VGA (0300), 3D (0302), other (0380).
  case $(<"$dev/class") in 0x0300* | 0x0302* | 0x0380*) ;; *) continue ;; esac
  case $(<"$dev/vendor") in
    0x8086) intel+=("$(pci_id "$(basename "$dev")")") ;;
    0x10de) nvidia+=("$(pci_id "$(basename "$dev")")") ;;
  esac
done

pick_gpu() { # label, default, detected ids...
  local label=$1 default=$2; shift 2
  if (( $# == 1 )); then printf '%s' "$1"; return; fi
  echo "aviso: $# GPU(s) $label detectada(s): ${*:-nenhuma}" >&2
  local id
  id=$(ask "Bus ID da GPU $label (formato PCI:bus:dev:fn) [$default]:")
  printf '%s' "${id:-$default}"
}
intel_id=$(pick_gpu Intel "PCI:0:2:0" "${intel[@]}")
nvidia_id=$(pick_gpu NVIDIA "PCI:1:0:0" "${nvidia[@]}")

# --- facts.nix ---------------------------------------------------------------

new_facts=$(cat <<EOF
# Hardware facts only knowable on marvin itself. Written by
# machines/marvin/install.sh on $(date -I) -- rerun it rather than editing.
{
  # Disk disko formats (everything on it is wiped).
  disk = "$target";

  # PRIME offload bus IDs, NixOS format (decimal "PCI:bus:device:function").
  intelBusId = "$intel_id";
  nvidiaBusId = "$nvidia_id";
}
EOF
)

echo
echo "facts.nix que será gravado:"
echo "$new_facts"
echo

if (( dry_run )); then
  echo "(--dry-run: nada foi gravado nem formatado)"
  exit 0
fi

echo "ATENÇÃO: tudo em $disk ($target) será APAGADO."
confirm=$(ask "Digite '$(basename "$disk")' para confirmar:")
[[ "$confirm" == "$(basename "$disk")" ]] || die "confirmação não bate, abortando sem mexer em nada"

printf '%s\n' "$new_facts" > "$facts"

# --- install -----------------------------------------------------------------

echo ">> disko: particionando, formatando e montando em /mnt (vai pedir a senha do LUKS)"
nix --extra-experimental-features "nix-command flakes" run github:nix-community/disko -- \
  --mode disko "$repo/machines/marvin/disko-config.nix"

echo ">> copiando a chave age do sops"
install -D -m 600 "$key" /mnt/var/lib/sops-nix/key.txt

echo ">> gerando hardware-configuration.nix"
tmp=$(mktemp)
nixos-generate-config --no-filesystems --root /mnt --show-hardware-config > "$tmp"
mv "$tmp" "$hwconf"

echo ">> nixos-install (vai pedir a senha do LUKS de novo e a senha do root no fim)"
nixos-install --root /mnt --flake "$repo#marvin"

# The generated facts.nix/hardware-configuration.nix only exist in this
# (installer-side) clone; without copying them over they're lost on reboot.
copy=$(ask "Copiar o repo (com os arquivos gerados) para /home/henrique/codigos/nexos no marvin? [S/n]")
if [[ ! "$copy" =~ ^[nN] ]]; then
  mkdir -p /mnt/home/henrique/codigos
  cp -a "$repo" /mnt/home/henrique/codigos/nexos
  nixos-enter --root /mnt -c 'chown -R henrique:users /home/henrique' 2>/dev/null \
    || chown -R 1000:100 /mnt/home/henrique
fi

cat <<'EOF'

Pronto! Próximos passos:
  1. reboot
  2. em ~/codigos/nexos: commit + push de machines/marvin/facts.nix e
     machines/marvin/hardware-configuration.nix
EOF
