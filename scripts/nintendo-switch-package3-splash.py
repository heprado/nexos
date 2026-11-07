#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3
"""Find / patch the boot sysmodule splash screen inside an Atmosphère package3.

Edits the BLZ-compressed text of the `boot` KIP in place (literal bytes only) and
re-decompresses to verify that nothing else changed. Output keeps the same size.

usage:
  nintendo-switch-package3-splash.py [apply [patch]]                       # interactive: find SD (hekate UMS), backup, patch, verify, eject
  nintendo-switch-package3-splash.py scan  <package3>
  nintendo-switch-package3-splash.py skip  <package3_in> <package3_out>   # never turn the display on (no flash)
  nintendo-switch-package3-splash.py patch <package3_in> <package3_out>   # keep splash, 0 s delay (flashes)

The SD must be exposed through hekate UMS (Fechar → Ferramentas → Ferramentas USB → Cartão SD);
DBI's MTP refuses to overwrite package3. Backups go to ~/.local/share/nintendo-switch-package3/
and to backup/custom-boot/ on the SD.
"""
import hashlib
import json
import os
import struct
import subprocess
import sys
import time
from pathlib import Path

BOOT_NAME = b"boot"


def find_entry(pkg, name):
    # package3 content table: 0x20-byte entries from 0x40: u32 off, u32 size, u8 type, pad[7], char name[0x10]
    for base in range(0x40, 0x400, 0x20):
        off, size = struct.unpack_from("<II", pkg, base)
        ename = pkg[base + 0x10: base + 0x20].split(b"\0")[0]
        if ename == name:
            return off, size
    raise SystemExit("boot entry not found")


def kip_segments(kip):
    assert kip[:4] == b"KIP1"
    flags = kip[0x1F]
    segs = []
    pos = 0x100
    for i in range(3):
        out_off, dec_size, comp_size = struct.unpack_from("<III", kip, 0x20 + i * 0x10)
        segs.append(dict(idx=i, file_off=pos, dec=dec_size, comp=comp_size, compressed=bool(flags & (1 << i))))
        pos += comp_size
    return segs


def blz_decompress(cmp):
    """Return (out, src) where src[i] = index into cmp for literal bytes, -1 for back-ref copies."""
    cmp_size = len(cmp)
    compressed_size, init_index, addl = struct.unpack_from("<III", cmp, cmp_size - 0xC)
    out = bytearray(cmp) + bytearray(addl)
    src = list(range(cmp_size)) + [-1] * addl
    cmp_start = cmp_size - compressed_size
    cmp_ofs = compressed_size - init_index
    out_ofs = compressed_size + addl
    while out_ofs > 0:
        cmp_ofs -= 1
        control = cmp[cmp_start + cmp_ofs]
        for _ in range(8):
            if control & 0x80:
                cmp_ofs -= 2
                assert cmp_ofs >= 0
                seg_val = cmp[cmp_start + cmp_ofs] | (cmp[cmp_start + cmp_ofs + 1] << 8)
                seg_size = ((seg_val >> 12) & 0xF) + 3
                seg_ofs = (seg_val & 0x0FFF) + 3
                seg_size = min(seg_size, out_ofs)
                out_ofs -= seg_size
                for j in range(seg_size):
                    p = cmp_start + out_ofs + j
                    out[p] = out[p + seg_ofs]
                    src[p] = -1
            else:
                cmp_ofs -= 1
                assert cmp_ofs >= 0
                out_ofs -= 1
                p = cmp_start + out_ofs
                out[p] = cmp[cmp_start + cmp_ofs]
                src[p] = cmp_start + cmp_ofs
            control = (control << 1) & 0xFF
            if out_ofs == 0:
                break
    return bytes(out), src


def find_delay(text):
    """Locate movz/movk pairs that build 0xEE6B2800 (4 s in ns)."""
    hits = []
    for i in range(0, len(text) - 4, 4):
        ins = struct.unpack_from("<I", text, i)[0]
        # movz {w,x}d, #0x2800
        if (ins & 0x7FFFFFE0) == 0x52850000:
            rd = ins & 0x1F
            for j in range(i + 4, min(i + 24, len(text) - 4), 4):
                k = struct.unpack_from("<I", text, j)[0]
                # movk {w,x}d, #0xee6b, lsl #16
                if (k & 0x7FFFFFFF) == (0x72BDCD60 | rd) and (k >> 31) == (ins >> 31):
                    hits.append((i, ins, j, k))
    return hits




SKIP_OLD = 0x7A441804  # ccmp w0, #4, #4, ne
SKIP_NEW = 0x6B00001F  # cmp w0, w0


class AlreadyPatched(Exception):
    pass


def parse(data):
    pkg = bytearray(data)
    assert pkg[:4] == b"PK31" and len(pkg) == 0x800000, "not an Atmosphère package3"
    off, size = find_entry(pkg, BOOT_NAME)
    kip = pkg[off: off + size]
    text = kip_segments(kip)[0]
    assert text["compressed"]
    cmp = bytes(kip[text["file_off"]: text["file_off"] + text["comp"]])
    out, src = blz_decompress(cmp)
    assert len(out) == text["dec"], (len(out), text["dec"])
    return pkg, off, text, cmp, out, src


def load(path):
    with open(path, "rb") as f:
        return parse(f.read())


def find_skip_branch(text, delay_off):
    """Find the `b.ne` that skips the early return (boot reason AcOk/RtcAlarm2) before the splash."""
    for p in range(delay_off - 4, max(delay_off - 0x80, 0), -4):
        ins = struct.unpack_from("<I", text, p)[0]
        # b.ne #12 followed by ldp x29, x30, [sp], #16 ; ret
        if ins == 0x54000061 and text[p + 4: p + 12] == bytes.fromhex("fd7bc1a8c0035fd6"):
            return p
    raise SystemExit("early-return branch not found")


def build_patch(data, mode, log=print):
    """Return the patched package3 bytes. Raises AlreadyPatched if `skip` is already applied."""
    pkg, off, text, cmp, out, src = parse(data)
    hits = find_delay(out)
    log(f"boot kip @ 0x{off:x}, text comp 0x{text['comp']:x} dec 0x{text['dec']:x}")
    for i, ins, j, k in hits:
        log(f"  movz @0x{i:x} {ins:08x}  movk @0x{j:x} {k:08x}  literal-src: "
            f"{[src[i + n] for n in range(4)]} {[src[j + n] for n in range(4)]}")
    assert len(hits) == 1, "expected exactly one 4s delay"
    i, ins, j, k = hits[0]
    want = bytearray(out)
    if mode == "skip":
        # never show the splash: always take the early-return path
        # ccmp w0, #4, #4, ne -> cmp w0, w0: Z is always set, so the b.ne after it never skips the return
        b = find_skip_branch(out, i)
        c = b - 4
        cur = struct.unpack_from("<I", out, c)[0]
        if cur == SKIP_NEW:
            raise AlreadyPatched()
        assert cur == SKIP_OLD, "unexpected instruction before b.ne"
        log(f"  ccmp @0x{c:x} literal-src: {[src[c + n] for n in range(4)]}")
        struct.pack_into("<I", want, c, SKIP_NEW)
        positions = list(range(c, c + 4))
    else:
        struct.pack_into("<I", want, i, ins & ~(0xFFFF << 5))  # movz rd, #0
        struct.pack_into("<I", want, j, 0xD503201F)            # nop
        positions = list(range(i, i + 4)) + list(range(j, j + 4))
    new_cmp = bytearray(cmp)
    for pos in positions:
        if want[pos] == out[pos]:
            continue
        s = src[pos]
        assert s >= 0, f"byte 0x{pos:x} comes from a back-reference, cannot patch in place"
        new_cmp[s] = want[pos]
    check, _ = blz_decompress(bytes(new_cmp))
    diff = [p for p in range(len(out)) if check[p] != out[p]]
    assert check == bytes(want), f"re-decompression mismatch, changed bytes: {[hex(p) for p in diff[:20]]}"
    log(f"verified: decompressed text differs only at {[hex(p) for p in diff]}")
    base = off + text["file_off"]
    pkg[base: base + len(new_cmp)] = new_cmp
    return bytes(pkg)


# ---------------------------------------------------------------------------
# apply: full workflow against the SD card exposed by hekate UMS
# ---------------------------------------------------------------------------

LOCAL_BACKUP_DIR = Path.home() / ".local/share/nintendo-switch-package3"
SD_BACKUP_DIR = "backup/custom-boot"


def ask(prompt, default=False):
    suffix = " [S/n] " if default else " [s/N] "
    try:
        answer = input(prompt + suffix).strip().lower()
    except EOFError:
        answer = ""
    if not answer:
        return default
    return answer in ("s", "sim", "y", "yes")


def wait_enter(prompt):
    try:
        input(prompt + " (Enter para continuar, Ctrl+C para sair) ")
    except EOFError:
        raise SystemExit("sem terminal interativo, abortando")


def is_switch_sd(root):
    return (root / "atmosphere/package3").is_file() and (root / "bootloader").is_dir()


def mounted_candidates():
    base = Path("/run/media") / os.environ.get("USER", "")
    return [p for p in sorted(base.glob("*")) if p.is_dir() and is_switch_sd(p)] if base.is_dir() else []


def unmounted_usb_partitions():
    out = subprocess.run(["lsblk", "-J", "-p", "-o", "NAME,TRAN,FSTYPE,MOUNTPOINTS,MODEL"],
                         capture_output=True, text=True, check=True).stdout
    parts = []
    for disk in json.loads(out)["blockdevices"]:
        if disk.get("tran") != "usb":
            continue
        for part in disk.get("children") or []:
            if part.get("fstype") in ("exfat", "vfat") and not any(part.get("mountpoints") or []):
                parts.append((part["name"], disk.get("model") or "?"))
    return parts


def find_sd():
    """Locate the Switch SD; ask the user to enable UMS / mount it when needed."""
    while True:
        found = mounted_candidates()
        if len(found) == 1:
            return found[0]
        if len(found) > 1:
            for n, p in enumerate(found):
                print(f"  [{n}] {p}")
            choice = input("Mais de um cartão encontrado, qual usar? ").strip()
            if choice.isdigit() and int(choice) < len(found):
                return found[int(choice)]
            continue
        for dev, model in unmounted_usb_partitions():
            if ask(f"Partição USB {dev} ({model}) não está montada. Montar?", default=True):
                subprocess.run(["udisksctl", "mount", "-b", dev], check=False)
                time.sleep(1)
        if mounted_candidates():
            continue
        print("Cartão do Switch não encontrado.")
        print("No hekate: Fechar → Ferramentas → Ferramentas USB → Cartão SD, e conecte o cabo no PC.")
        wait_enter("Quando o cartão aparecer no PC,")


def read_direct(path):
    """Read a file bypassing the page cache, so we see what is really on the card."""
    return subprocess.run(["dd", f"if={path}", "iflag=direct", "bs=1M", "status=none"],
                          capture_output=True, check=True).stdout


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_verified(path, data):
    tmp = path.with_name(path.name + ".new")
    with open(tmp, "wb") as f:
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    if read_direct(tmp) != data:
        tmp.unlink()
        raise SystemExit(f"verificação falhou em {tmp}, nada foi substituído")
    os.replace(tmp, path)
    subprocess.run(["sync"], check=True)
    if read_direct(path) != data:
        raise SystemExit(f"verificação falhou em {path} depois de substituir — restaure o backup!")


def eject(root):
    dev = subprocess.run(["findmnt", "-n", "-o", "SOURCE", "--target", str(root)],
                         capture_output=True, text=True, check=True).stdout.strip()
    subprocess.run(["sync"], check=True)
    subprocess.run(["udisksctl", "unmount", "-b", dev], check=True)
    disk = subprocess.run(["lsblk", "-n", "-p", "-o", "PKNAME", dev],
                          capture_output=True, text=True).stdout.strip()
    if disk:
        # hekate drops the USB device on its own; a failure here is harmless
        subprocess.run(["udisksctl", "power-off", "-b", disk], capture_output=True)
    print(f"{dev} desmontado. Pode tocar em Fechar no UMS do hekate e tirar o cabo.")


def apply(mode="skip"):
    root = find_sd()
    print(f"Cartão do Switch: {root}")
    cnx = root / "cnx.txt"
    version = cnx.read_text().strip() if cnx.is_file() else "desconhecida"
    print(f"Versão do pacote CNX: {version}")

    pkg_path = root / "atmosphere/package3"
    current = read_direct(pkg_path)
    print(f"package3 atual: sha256 {sha(current)[:16]}…")

    try:
        patched = build_patch(current, mode, log=lambda *_: None)
    except AlreadyPatched:
        print("O patch já está aplicado neste package3. Nada a fazer.")
        if ask("Ejetar o cartão?", default=True):
            eject(root)
        return

    tag = f"{version}_{sha(current)[:8]}".replace("/", "_")
    LOCAL_BACKUP_DIR.mkdir(parents=True, exist_ok=True)
    local_backup = LOCAL_BACKUP_DIR / f"package3_original_{tag}"
    sd_backup = root / SD_BACKUP_DIR / f"package3_original_{tag}"
    sd_backup.parent.mkdir(parents=True, exist_ok=True)
    for dst in (local_backup, sd_backup):
        if dst.exists() and read_direct(dst) == current:
            print(f"backup já existe: {dst}")
            continue
        write_verified(dst, current)
        print(f"backup salvo e verificado: {dst}")

    print(f"\npackage3 com patch ({mode}) gerado: sha256 {sha(patched)[:16]}…")
    if not ask(f"Gravar em {pkg_path}?"):
        print("Nada foi gravado.")
        return
    write_verified(pkg_path, patched)
    print("package3 gravado e verificado lendo direto do disco.")
    print(f"Para desfazer: copie {sd_backup.relative_to(root)} para atmosphere/package3")

    if ask("Ejetar o cartão?", default=True):
        eject(root)


def main():
    args = sys.argv[1:]
    mode = args[0] if args else "apply"
    try:
        if mode == "apply":
            apply("patch" if len(args) > 1 and args[1] == "patch" else "skip")
        elif mode == "scan":
            pkg, off, text, cmp, out, src = load(args[1])
            print(f"boot kip @ 0x{off:x}, text comp 0x{text['comp']:x} dec 0x{text['dec']:x}")
            for i, ins, j, k in find_delay(out):
                print(f"  movz @0x{i:x} {ins:08x}  movk @0x{j:x} {k:08x}")
        elif mode in ("skip", "patch"):
            with open(args[1], "rb") as f:
                patched = build_patch(f.read(), mode)
            with open(args[2], "wb") as f:
                f.write(patched)
            print("written", args[2])
        else:
            raise SystemExit(__doc__)
    except AlreadyPatched:
        raise SystemExit("patch já aplicado neste package3")
    except KeyboardInterrupt:
        raise SystemExit("\ncancelado")


if __name__ == "__main__":
    main()
