import argparse
import ctypes
import datetime as dt
import glob
import json
import msvcrt
import os
import shutil
import sqlite3
import sys
import time


def write_json_atomic(path, payload):
    temporary = f"{path}.tmp.{os.getpid()}"
    with open(temporary, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=True, separators=(",", ":"))
        handle.write("\n")
    os.replace(temporary, path)


def set_below_normal_priority():
    try:
        ctypes.windll.kernel32.SetPriorityClass(
            ctypes.windll.kernel32.GetCurrentProcess(), 0x00004000
        )
    except Exception:
        pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    parser.add_argument("--destination", required=True)
    parser.add_argument("--marker", required=True)
    parser.add_argument("--minimum-interval-seconds", type=int, default=900)
    parser.add_argument("--retain", type=int, default=20)
    args = parser.parse_args()

    os.makedirs(args.destination, exist_ok=True)
    receipt_path = os.path.join(args.destination, "opencode-backup-receipt.json")
    lock_path = os.path.join(args.destination, ".opencode-backup.lock")
    lock_handle = open(lock_path, "a+b")
    if os.path.getsize(lock_path) == 0:
        lock_handle.write(b"\0")
        lock_handle.flush()
    lock_handle.seek(0)

    try:
        msvcrt.locking(lock_handle.fileno(), msvcrt.LK_NBLCK, 1)
    except OSError:
        return 0

    temporary_path = None
    try:
        with open(args.marker, "w", encoding="ascii") as marker:
            marker.write(str(os.getpid()))
        set_below_normal_priority()

        if not os.path.isfile(args.source):
            write_json_atomic(
                receipt_path,
                {
                    "status": "source_missing",
                    "completedUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "source": args.source,
                },
            )
            return 2

        backups = sorted(
            glob.glob(os.path.join(args.destination, "opencode_*.db")),
            key=os.path.getmtime,
            reverse=True,
        )
        now = time.time()
        if backups and now - os.path.getmtime(backups[0]) < args.minimum_interval_seconds:
            write_json_atomic(
                receipt_path,
                {
                    "status": "recent_backup",
                    "completedUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "backup": backups[0],
                    "sourceBytes": os.path.getsize(args.source),
                },
            )
            return 0

        source_size = os.path.getsize(args.source)
        required_free = source_size + 512 * 1024 * 1024
        if shutil.disk_usage(args.destination).free < required_free:
            write_json_atomic(
                receipt_path,
                {
                    "status": "insufficient_space",
                    "completedUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
                    "sourceBytes": source_size,
                    "requiredFreeBytes": required_free,
                },
            )
            return 3

        stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        final_path = os.path.join(
            args.destination, f"opencode_{stamp}_pid{os.getpid()}.db"
        )
        temporary_path = final_path + ".tmp"

        source = sqlite3.connect(
            f"file:{args.source}?mode=ro", uri=True, timeout=30
        )
        destination = sqlite3.connect(temporary_path, timeout=30)
        try:
            source.execute("PRAGMA busy_timeout=30000")
            source.backup(destination, pages=16384, sleep=0.05)
        finally:
            destination.close()
            source.close()

        os.replace(temporary_path, final_path)
        temporary_path = None
        completed = dt.datetime.now(dt.timezone.utc).isoformat()
        write_json_atomic(
            receipt_path,
            {
                "status": "completed",
                "completedUtc": completed,
                "source": args.source,
                "sourceBytes": source_size,
                "backup": final_path,
                "backupBytes": os.path.getsize(final_path),
            },
        )

        backups = sorted(
            glob.glob(os.path.join(args.destination, "opencode_*.db")),
            key=os.path.getmtime,
            reverse=True,
        )
        for stale_path in backups[max(1, args.retain) :]:
            try:
                os.remove(stale_path)
            except OSError:
                pass
        return 0
    except Exception as exc:
        write_json_atomic(
            receipt_path,
            {
                "status": "failed",
                "completedUtc": dt.datetime.now(dt.timezone.utc).isoformat(),
                "error": str(exc),
            },
        )
        return 1
    finally:
        if temporary_path:
            try:
                os.remove(temporary_path)
            except OSError:
                pass
        try:
            msvcrt.locking(lock_handle.fileno(), msvcrt.LK_UNLCK, 1)
        except OSError:
            pass
        lock_handle.close()
        try:
            os.remove(args.marker)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
