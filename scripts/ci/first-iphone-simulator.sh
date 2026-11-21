#!/usr/bin/env bash
# Prints the UDID of the first available iPhone simulator (runner images differ).
set -euo pipefail
xcrun simctl list devices available -j | python3 -I -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime in sorted(devices, reverse=True):
    if "iOS" not in runtime:
        continue
    for d in devices[runtime]:
        if d["name"].startswith("iPhone"):
            print(d["udid"]); sys.exit(0)
sys.exit("no iPhone simulator available")
'
