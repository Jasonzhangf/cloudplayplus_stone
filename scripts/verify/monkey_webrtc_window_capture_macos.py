#!/usr/bin/env python3
"""Monkey test driver for the Verify WebRTC Window Capture app (macOS).

This script connects to the Dart VM Service and triggers screenshot saves.

Prereqs:
  1) Start the app via: scripts/verify/verify_webrtc_window_capture.sh
  2) Ensure the app window is visible.

Note:
  We keep this minimal: it triggers the app's own "Shot" logic via an exposed
  service extension, which avoids fragile UI automation.
"""

import json
import os
import re
import sys
import time
import urllib.request


def read_vmservice_uri():
  # Try flutter tool cache logs first.
  candidates = []
  for path in [
    "flutter_01.log",
    "flutter_02.log",
    "build/verify/webrtc_window_capture_run.log",
  ]:
    if os.path.exists(path):
      candidates.append(path)
  pattern = re.compile(r"A Dart VM Service on macOS is available at: (http://127\.0\.0\.1:\d+/[^\s]+)")
  for p in candidates:
    with open(p, "r", errors="ignore") as f:
      m = None
      for line in f:
        m = pattern.search(line)
        if m:
          return m.group(1)
  return None


def http_get_json(url):
  with urllib.request.urlopen(url) as resp:
    return json.loads(resp.read().decode("utf-8"))


def main():
  vm = read_vmservice_uri()
  if not vm:
    print("ERROR: Could not find VM Service URI in logs.")
    print("Tip: copy the VM service URL from flutter run output into build/verify/webrtc_window_capture_run.log")
    sys.exit(2)

  print("VM:", vm)
  # Find the isolate
  vminfo = http_get_json(vm + "/json")
  # Heuristic: pick first isolate
  if not vminfo:
    print("ERROR: VM /json empty")
    sys.exit(3)
  isolate = vminfo[0].get("isolate")
  if not isolate:
    print("ERROR: No isolate found")
    sys.exit(4)
  # Service extension endpoint
  ext = vm + "/" + isolate + "/_serviceExtension"  # not real; placeholder
  print("NOTE: This script is a placeholder until we expose a real service extension.")
  print("Next: add a Dart ServiceExtension (ext.cloudplayplus.screenshot) and call it here.")
  print("Isolate:", isolate)


if __name__ == "__main__":
  main()

