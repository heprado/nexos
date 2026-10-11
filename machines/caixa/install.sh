#!/usr/bin/env bash
# Interactive installer for caixa (ZFS + native encryption). Run as root
# from the NixOS installer ISO, with this repo and the admin age key on a
# writable stick (Ventoy):
#
#   sudo bash machines/caixa/install.sh
#
# Ventoy (before 1.1.18) keeps its data partition busy while the ISO runs
# from it, so it can't be mounted. Boot the "Copy ISO Files to RAM" entry
# (copytoram), then free the partition and mount it:
#   sudo dmsetup remove ventoy
#   sudo mkdir -p /media/ventoy && sudo mount /dev/disk/by-label/Ventoy /media/ventoy
#
# caixa's SSH host key is generated here, straight onto the encrypted pool,
# and never leaves it; sops-nix uses that same key (converted to age) to
# decrypt secrets/caixa.yaml. The admin age key (passphrase-protected, see
# .sops.yaml) is what re-encrypts the secrets for the new host key, right
# here. Its path comes from $ADMIN_AGE_KEY, or keys/admin.age (or admin.age)
# at the stick's root, next to the repo, or is asked for.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
work=/tmp/nexos # RAM copy that nix builds from (the stick is exFAT)
hostkey=/mnt/etc/ssh/ssh_host_ed25519_key
export NIX_CONFIG="extra-experimental-features = nix-command flakes"

die() { echo "erro: $*" >&2; exit 1; }
ask() { local reply; read -rp "$1 " reply; printf '%s' "$reply"; }
step() { echo; echo ">> $*"; }
ssh_to_age() { nix run nixpkgs#ssh-to-age; }
sops() { nix run nixpkgs#sops -- "$@"; }
disko() { nix run github:nix-community/disko -- "$@"; }
command -v git >/dev/null || git() { nix run nixpkgs#git -- "$@"; }
# Recipients sops lists in plain text in a file's metadata; nothing is
# decrypted to read them.
has_recipient() { grep -q "recipient: $2\$" "$1"; }

# --- preflight (nothing is touched until the disk confirmation) ---------------

(( EUID == 0 )) || die "rode como root (sudo)"
[[ -d /sys/firmware/efi ]] || die "não bootou em modo UEFI (systemd-boot precisa de UEFI)"
command -v zpool >/dev/null || die "instalador sem ZFS (use a ISO oficial do NixOS)"

admin=$(sed -n 's/^  - &admin \(age1[0-9a-z]*\).*/\1/p' "$repo/.sops.yaml")
[[ -n "$admin" && "$admin" != *placeholder* ]] || die ".sops.yaml não tem a chave pública &admin real (ainda é placeholder)"
has_recipient "$repo/secrets/caixa.yaml" "$admin" \
  || die "secrets/caixa.yaml ainda não está cifrado para a chave admin: rode 'sops updatekeys secrets/caixa.yaml' no marvin uma vez"

key=${ADMIN_AGE_KEY:-}
if [[ -z "$key" ]]; then
  for k in "$repo/../keys/admin.age" "$repo/../admin.age"; do
    [[ -f "$k" ]] && { key=$k; break; }
  done
fi
while [[ ! -f "$key" ]]; do
  echo "Chave age admin não encontrada${key:+ em $key}"
  key=$(ask "Caminho da admin.age (ex.: /media/ventoy/admin.age):")
done

if grep -q PLACEHOLDER "$repo/users/henrique/default.nix"; then
  echo "aviso: users/henrique/default.nix ainda tem chave SSH PLACEHOLDER"
  [[ $(ask "Continuar mesmo assim? (só as chaves reais vão conseguir entrar) [s/N]") =~ ^[sS] ]] || exit 1
fi

# The pool must be created and imported under caixa's hostid: imported
# under another one, the first boot refuses it ("last accessed by another
# system"), since zfs.nix doesn't force-import the root pool.
hostid=$(sed -n 's/.*networking\.hostId = "\([0-9a-f]\{8\}\)".*/\1/p' "$repo/machines/caixa/zfs.nix")
[[ -n "$hostid" ]] || die "networking.hostId não encontrado em machines/caixa/zfs.nix"
# On the ISO /etc/hostid is a symlink into the read-only store (its own
# networking.hostId), so zgenhostid can't write through it; and the spl
# module may already have read that one, hence setting it there too.
modprobe zfs
rm -f /etc/hostid
zgenhostid -f "$hostid"
echo "$((16#$hostid))" > /sys/module/spl/parameters/spl_hostid
[[ $(hostid) == "$hostid" ]] || die "hostid ficou $(hostid), esperado $hostid"

step "copiando o repo para a RAM ($work)"
rm -rf "$work"
cp -r "$repo" "$work"
rm -rf "$work/keys"
# The index is only a cache, and a flaky stick (exFAT) has corrupted it before:
# rebuild it from HEAD rather than trust the copy.
rm -f "$work/.git/index"
git -C "$work" config core.fileMode false
git -C "$work" reset -q
# Staged right away (facts.nix and the host key's .pub are added later), and
# everything runs from here: no nix command ever sees the stick's tree.
git -C "$work" add -A
cd "$work"
host=$work/machines/caixa

# --- disk --------------------------------------------------------------------

# Leftovers from an interrupted run: the pool imported and mounted at /mnt.
if zpool list zroot >/dev/null 2>&1; then
  step "desmontando o zroot que sobrou de uma execução anterior"
  umount -R /mnt 2>/dev/null || true
  zpool export zroot
fi

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
  lsblk -nro MOUNTPOINTS "$d" | grep -q . && notes+="  [em uso/montado: pendrive?]"
  printf '  %d) %-14s %s%s\n' "$((i + 1))" "$d" "$info" "$notes"
done

while :; do
  n=$(ask "Em qual disco instalar o caixa? (número)")
  [[ "$n" =~ ^[0-9]+$ ]] && (( n >= 1 && n <= ${#disks[@]} )) && break
  echo "opção inválida"
done
disk=${disks[$((n - 1))]}
lsblk -nro MOUNTPOINTS "$disk" | grep -q . && die "$disk tem partições montadas (é o pendrive?)"

# A stable by-id path rather than /dev/sdX, which can change between boots.
target=$disk
for link in /dev/disk/by-id/*; do
  name=$(basename "$link")
  [[ "$name" == *-part* || "$name" == wwn-* || "$name" == *-eui.* ]] && continue
  if [[ $(readlink -f "$link") == "$disk" ]]; then target=$link; break; fi
done

echo
echo "ATENÇÃO: tudo em $disk ($target) será APAGADO."
confirm=$(ask "Digite '$(basename "$disk")' para confirmar:")
[[ "$confirm" == "$(basename "$disk")" ]] || die "confirmação não bate, abortando sem mexer em nada"

cat > "$host/facts.nix" <<EOF
# Hardware facts only knowable on caixa itself. Written by
# machines/caixa/install.sh on $(date -I) -- rerun it rather than editing.
{
  # Disk disko formats (everything on it is wiped).
  disk = "$target";
}
EOF

# --- install -----------------------------------------------------------------

step "disko: particionando, criando o pool zroot e montando em /mnt (vai pedir a senha nova do ZFS duas vezes)"
disko --mode destroy,format,mount --yes-wipe-all-disks "$host/disko-config.nix"

step "gerando a chave de host SSH (ed25519) direto no pool criptografado"
install -d -m 755 /mnt/etc/ssh
ssh-keygen -q -t ed25519 -N "" -C "root@caixa" -f "$hostkey"
cp "$hostkey.pub" "$host/ssh_host_ed25519_key.pub"
age=$(ssh_to_age < "$hostkey.pub")

step "recifrando secrets/caixa.yaml para a chave nova (vai pedir a senha da chave admin)"
sed -i "s|^\(  - &caixa \)age1[0-9a-z]*|\1$age|" "$work/.sops.yaml"
grep -q "&caixa $age" "$work/.sops.yaml" || die "não consegui atualizar o &caixa no .sops.yaml"
(cd "$work" && SOPS_AGE_KEY_FILE=$key sops updatekeys --yes secrets/caixa.yaml)
has_recipient "$work/secrets/caixa.yaml" "$age" || die "secrets/caixa.yaml não ficou cifrado para a chave nova"

step "gerando hardware-configuration.nix"
nixos-generate-config --no-filesystems --root /mnt --show-hardware-config \
  > "$host/hardware-configuration.nix"

# The flake only sees files git knows about (facts.nix and the .pub are new).
git -C "$work" add -A

# No root password: root can't log in over SSH anyway, and henrique's
# password (console + sudo) comes from secrets/caixa.yaml.
step "nixos-install"
nixos-install --root /mnt --flake "$work#caixa" --no-root-passwd

step "copiando o repo para /home/henrique/codigos/nexos no caixa e os arquivos gerados para o pendrive"
mkdir -p /mnt/home/henrique/codigos
rm -rf /mnt/home/henrique/codigos/nexos
cp -a "$work" /mnt/home/henrique/codigos/nexos
nixos-enter --root /mnt -c 'chown -R henrique:users /home/henrique' 2>/dev/null \
  || chown -R 1000:100 /mnt/home/henrique
for f in .sops.yaml secrets/caixa.yaml machines/caixa/facts.nix \
  machines/caixa/hardware-configuration.nix machines/caixa/ssh_host_ed25519_key.pub; do
  cp "$work/$f" "$repo/$f"
done

step "desmontando e exportando o pool"
sync
umount -R /mnt
zpool export zroot

cat <<EOF

Pronto! Chave de host do caixa:
  $(ssh-keygen -lf "$host/ssh_host_ed25519_key.pub")

Pode dar reboot e tirar o pendrive; o Plymouth pede a senha do ZFS.
Depois, no marvin (os arquivos gerados também estão no pendrive): commit de
.sops.yaml, secrets/caixa.yaml e machines/caixa/{facts.nix,
hardware-configuration.nix,ssh_host_ed25519_key.pub}, e ssh-keygen -R para
os nomes antigos do caixa (a chave de host mudou).
EOF
