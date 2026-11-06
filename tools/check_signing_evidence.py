#!/usr/bin/env python3
"""Validate a given xcconfig or `xcodebuild -showBuildSettings` output file as release signing
evidence. Never runs xcodebuild, never signs/uploads. Exit 0 only if evidence is real."""
import re
import sys

PLACEHOLDER = ("<", ">", "invalid", "placeholder", "your_", "example", "changeme", "todo")
BAD_HOSTS = {"47.103.124.64", "localhost", "127.0.0.1"}


def parse(text):
    out = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith(("//", "#")) or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k = k.strip()
        if re.fullmatch(r"[A-Za-z0-9_]+", k):
            out[k] = v.strip().replace("$()", "")
    return out


def placeholder(v):
    v = v.strip().lower()
    return not v or any(p in v for p in PLACEHOLDER)


def validate(settings):
    if not settings:
        return ["no build settings evidence provided"]
    v = []
    if settings.get("CODE_SIGNING_ALLOWED", "").strip().upper() != "YES":
        v.append("CODE_SIGNING_ALLOWED must be YES")
    if not re.fullmatch(r"[A-Z0-9]{10}", settings.get("DEVELOPMENT_TEAM", "").strip()):
        v.append("DEVELOPMENT_TEAM missing or malformed")
    b = settings.get("PRODUCT_BUNDLE_IDENTIFIER", "")
    if placeholder(b) or "." not in b:
        v.append("PRODUCT_BUNDLE_IDENTIFIER missing or placeholder")
    api = settings.get("QUESTIFY_API_BASE_URL", "")
    m = re.fullmatch(r"https://([^/:\s]+)(:\d+)?(/\S*)?", api.strip())
    host = m.group(1).lower() if m else ""
    if placeholder(api) or not m or host in BAD_HOSTS or host.endswith(".invalid"):
        v.append("QUESTIFY_API_BASE_URL missing, placeholder or disallowed")
    if placeholder(settings.get("QUESTIFY_SESSION_REALM", "")):
        v.append("QUESTIFY_SESSION_REALM missing or placeholder")
    return v


def main(argv):
    if len(argv) != 2:
        print("usage: check_signing_evidence.py <settings-file>", file=sys.stderr)
        return 2
    with open(argv[1], encoding="utf-8") as f:
        violations = validate(parse(f.read()))
    for item in violations:
        print("FAIL:", item)
    print("OK" if not violations else "REJECTED")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
