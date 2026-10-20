#!/usr/bin/env python3
"""Package 02 source contract: member home avatar fallback + unified refresh, no new endpoints."""
import pathlib, re, sys
root = pathlib.Path(__file__).resolve().parents[2]
src = (root / "App/MemberHomeHeader.swift").read_text()
errs = []
for sym in ("remoteAvatarURL", "AsyncImage", "lettermark", "refreshToken", "TaskKey"):
    if sym not in src: errs.append(f"missing {sym}")
if 'hasPrefix("https://")' not in src: errs.append("avatar must be https only")
if re.search(r'"(/?api/[^"]+)"', src): errs.append("endpoint string in MemberHomeHeader")
if src.count("balancePreviewText") != 1: errs.append("balance field duplicated")
if errs: print("\n".join(errs)); sys.exit(1)
print("member home pkg02 contract OK")
