#!/usr/bin/env python3
"""Local state helper for the Wardogs Zone widget.

This script ONLY reads/writes a small JSON state file under the user cache
directory (~/.cache/wardogs-plugin/seen.json) that stores the last seen
WARDOGS build version. It makes no network calls and executes no external
input — it exists purely so the QML side can persist a single version string
across shell restarts, mirroring how first-party plugins keep local state.

Usage:
  persist.py read-version                 # print {"version": "..."} or {}
  persist.py write-version --version X    # write {"version": "X"}
"""

import argparse
import json
import os
import sys


def state_path():
    home = os.environ.get("HOME", "")
    cache = os.environ.get("XDG_CACHE_HOME", "") or os.path.join(home, ".cache")
    return os.path.join(cache, "wardogs-plugin", "seen.json")


def read_version():
    path = state_path()
    data = {}
    try:
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    version = data.get("version", "")
    print(json.dumps({"version": version if isinstance(version, str) else ""}))


def write_version(version):
    path = state_path()
    directory = os.path.dirname(path)
    try:
        os.makedirs(directory, exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump({"version": version}, fh)
    except Exception as exc:
        sys.stderr.write(str(exc) + "\n")
        return 1
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["read-version", "write-version"])
    parser.add_argument("--version", default="")
    args = parser.parse_args()

    if args.command == "read-version":
        read_version()
        return 0
    return write_version(args.version)


if __name__ == "__main__":
    sys.exit(main())
