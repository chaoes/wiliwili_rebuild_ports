#!/usr/bin/env python3
"""核对仓库 VERSION 与最新 Release 是否一致；不一致时准备标题和正文。"""
import json
import os
import subprocess
import sys
from pathlib import Path

OUT = Path("/tmp/release_check")
OUT.mkdir(parents=True, exist_ok=True)

version = Path("VERSION").read_text(encoding="utf-8").strip()
repo = os.environ["REPO"]


def gh_api(path: str):
    try:
        raw = subprocess.run(
            ["gh", "api", path], check=True, capture_output=True, text=True
        ).stdout
        return json.loads(raw) if raw.strip() else None
    except subprocess.CalledProcessError:
        return None


latest = gh_api(f"repos/{repo}/releases/latest")
tag = (latest or {}).get("tag_name", "")

state = "ok"
title = ""
body = ""

if not tag:
    state = "none"
    title = "发版检查：仓库还没有 Release"
    body = (
        f"仓库里 `VERSION` 是 `{version}`，但还没有任何 Release 产物。\n\n"
        "发版步骤：\n"
        "1. 确认补丁与 `VERSION` 都已提交\n"
        "2. `git tag <tag> && git push origin <tag>`（形如 `v1.6.0`、`v1.6.0-r3`）\n"
        "3. 等 build-port 跑完，检查 Release 里的 zip 与 `SHA256SUMS`\n"
    )
elif tag == version or tag.startswith(version + "-"):
    state = "ok"
else:
    state = "mismatch"
    title = f"发版检查：VERSION（{version}）与最新 Release（{tag}）不一致"
    body = (
        f"- 仓库里的 `VERSION`：`{version}`\n"
        f"- 最新 Release：`{tag}`\n\n"
        "两种情况之一：\n"
        f"- 已经改了 `VERSION` 但还没发版 → 打 tag 推送（`v{version.lstrip('v')}` 或修复版后缀）触发 build-port\n"
        "- 已经发了版但忘了改 `VERSION` → 补一次提交，并在 `MERGE_LOG.md` 里对齐\n"
    )

(OUT / "state.txt").write_text(state)
if title:
    (OUT / "title.txt").write_text(title)
    (OUT / "body.md").write_text(body)

print(f"VERSION={version} latest={tag or '(none)'} state={state}")

if "GITHUB_OUTPUT" in os.environ:
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as f:
        f.write(f"state={state}\n")

sys.exit(0)
