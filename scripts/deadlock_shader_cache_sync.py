#!/usr/bin/env python3
"""Keep a private copy of Steam's NVIDIA shader-cache inputs for Deadlock.

Steam's NVIDIA cache merger currently loses entries in large merged caches.
The driver can read Steam's individual cache fragments as read-only inputs, so
keep those files in a separate cache directory before Steam merges/removes them.
"""

from __future__ import annotations

import errno
import fcntl
import logging
import os
from pathlib import Path
import shutil
import signal
import time


STEAM_CACHE = (
    Path.home()
    / ".local/share/Steam/steamapps/shadercache/1422450/nvidiav1/GLCache"
)
PROC_ROOT = Path("/proc")
PRIVATE_CACHE = Path.home() / ".cache/nexos/deadlock-nvidia/GLCache"
READY_FILE = PRIVATE_CACHE.parent / ".ready"
POLL_SECONDS = 0.2
STABLE_SECONDS = 0.4
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
FICLONE = 0x40049409
REFLINK_UNAVAILABLE = {
    errno.EINVAL,
    errno.ENOSYS,
    errno.ENOTTY,
    errno.EOPNOTSUPP,
    errno.EXDEV,
}

stopping = False


def stop(_signum: int, _frame: object) -> None:
    global stopping
    stopping = True


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

# Require two unchanged observations before copying. If Steam is still writing
# a file, its final size/mtime change schedules another complete atomic copy.
observed: dict[Path, tuple[int, int, float]] = {}
copied: dict[Path, tuple[int, int]] = {}

# A service restart must revalidate the snapshot before the launcher trusts it,
# without recopying multi-gigabyte files that are already identical.
READY_FILE.unlink(missing_ok=True)
startup_time = time.monotonic()
try:
    for source in list(STEAM_CACHE.rglob("steam*.bin")) + list(
        STEAM_CACHE.rglob("steam*.toc")
    ):
        try:
            stat = source.stat()
            signature = (stat.st_size, stat.st_mtime_ns)
            destination = PRIVATE_CACHE / source.relative_to(STEAM_CACHE)
            cached = destination.stat()
        except OSError:
            continue
        if (cached.st_size, cached.st_mtime_ns) == signature:
            observed[source] = (*signature, startup_time - STABLE_SECONDS)
            copied[source] = signature
except OSError:
    pass


def fossilize_replay_running() -> bool:
    # Linux limits /proc/<pid>/comm to 15 characters, so the full process name
    # "fossilize_replay" appears as "fossilize_repla".
    for comm in PROC_ROOT.glob("[0-9]*/comm"):
        try:
            if comm.read_text().strip().startswith("fossilize_repla"):
                return True
        except OSError:
            continue
    return False


def snapshot_file(source: Path, temporary: Path) -> bool:
    """Create an independent snapshot, reflinking where the filesystem allows."""
    with source.open("rb") as input_file, temporary.open("wb") as output_file:
        try:
            fcntl.ioctl(output_file.fileno(), FICLONE, input_file.fileno())
        except OSError as error:
            if error.errno not in REFLINK_UNAVAILABLE:
                raise
            input_file.seek(0)
            shutil.copyfileobj(input_file, output_file, length=1024 * 1024)
            reflinked = False
        else:
            reflinked = True
    shutil.copystat(source, temporary)
    return reflinked


was_replaying = fossilize_replay_running()
while not stopping:
    now = time.monotonic()
    replaying = fossilize_replay_running()
    flush_fragments = was_replaying and not replaying
    was_replaying = replaying
    if flush_fragments:
        logging.info("Fossilize replay ended; immediately preserving new cache fragments")
    try:
        sources = list(STEAM_CACHE.rglob("steam*.bin")) + list(
            STEAM_CACHE.rglob("steam*.toc")
        )
        sources.sort(
            key=lambda path: (
                not path.name.startswith("steamapp_shader_cache"),
                str(path),
            )
        )
    except OSError:
        sources = []

    for source in sources:
        try:
            stat = source.stat()
        except OSError:
            observed.pop(source, None)
            continue

        signature = (stat.st_size, stat.st_mtime_ns)
        previous = observed.get(source)
        changed = previous is None or previous[:2] != signature
        if changed:
            observed[source] = (*signature, now)
            READY_FILE.unlink(missing_ok=True)
        urgent_fragment = flush_fragments and source.name.startswith(
            "steamapp_shader_cache"
        )
        if changed and not urgent_fragment:
            continue
        if (
            (not urgent_fragment and now - previous[2] < STABLE_SECONDS)
            or copied.get(source) == signature
        ):
            continue

        destination = PRIVATE_CACHE / source.relative_to(STEAM_CACHE)
        temporary = destination.with_name(destination.name + ".sync-tmp")
        try:
            destination.parent.mkdir(parents=True, exist_ok=True)
            reflinked = snapshot_file(source, temporary)
            # Do not publish a copy if the Steam file changed during the copy.
            after = source.stat()
            if (after.st_size, after.st_mtime_ns) != signature:
                temporary.unlink(missing_ok=True)
                observed[source] = (after.st_size, after.st_mtime_ns, now)
                continue
            os.replace(temporary, destination)
            copied[source] = signature
            method = "reflink" if reflinked else "copy"
            logging.info(
                "preserved %s (%d bytes, %s)", source.name, signature[0], method
            )
        except FileNotFoundError:
            temporary.unlink(missing_ok=True)
        except OSError:
            temporary.unlink(missing_ok=True)
            logging.exception("could not preserve %s", source)

    # Let the launcher fall back to Steam's normal cache while a snapshot is
    # incomplete. Publish readiness only after every currently present file
    # has a matching, fully copied counterpart in the private cache.
    synchronized = True
    for source in sources:
        try:
            stat = source.stat()
        except OSError:
            continue
        signature = (stat.st_size, stat.st_mtime_ns)
        if observed.get(source, (None, None, 0))[:2] != signature:
            observed[source] = (*signature, now)
            synchronized = False
        elif copied.get(source) != signature:
            synchronized = False

    if sources and synchronized:
        try:
            READY_FILE.parent.mkdir(parents=True, exist_ok=True)
            ready_tmp = READY_FILE.with_suffix(".ready-tmp")
            ready_tmp.touch()
            was_ready = READY_FILE.exists()
            os.replace(ready_tmp, READY_FILE)
            if not was_ready:
                logging.info(
                    "private NVIDIA shader cache is ready (%d source files)",
                    len(sources),
                )
        except OSError:
            logging.exception("could not mark the private cache ready")
    else:
        was_ready = READY_FILE.exists()
        READY_FILE.unlink(missing_ok=True)
        if was_ready:
            logging.info(
                "private cache changed; launcher will use Steam's cache until sync completes"
            )

    time.sleep(POLL_SECONDS)
