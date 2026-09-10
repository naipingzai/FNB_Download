#!/usr/bin/env python3
"""测试 fnb_subprocess.py 握手：验证 stdout 只输出 JSON 行。"""
import subprocess, json, sys, os

SCRIPT = os.path.join(os.path.dirname(__file__), "..", "assets", "python", "fnb_subprocess.py")
VENV = os.path.join(os.path.dirname(__file__), "..", ".venv-linux", "bin", "python3")
APP_DIR = "/tmp/fnb_test_handshake2"

proc = subprocess.Popen(
    [VENV, SCRIPT, APP_DIR],
    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    text=True,
)

# 读取握手行
handshake = proc.stdout.readline().strip()
print(f"HANDSHAKE: {handshake}")
try:
    j = json.loads(handshake)
    print(f"OK: valid JSON with keys={list(j.keys())}")
except Exception as e:
    print(f"FAIL: not valid JSON: {e}")

# 测试 status call（在引擎装配前）
proc.stdin.write(json.dumps({"function": "status", "args": {}}) + "\n")
proc.stdin.flush()
resp = proc.stdout.readline().strip()
print(f"STATUS: {resp}")
try:
    j2 = json.loads(resp)
    print(f"OK: valid JSON with keys={list(j2.keys())}")
except Exception as e:
    print(f"FAIL: not valid JSON: {e}")

# 测试引擎装配（触发 tkd rich Console 输出到 stderr 而非 stdout）
import time
time.sleep(0.5)  # 等待之前的 init 引擎装配完成
proc.stdin.write(json.dumps({"function": "set_cookie", "args": {"platform": "douyin", "cookie": "test=1"}}) + "\n")
proc.stdin.flush()
resp2 = proc.stdout.readline().strip()
print(f"SET_COOKIE: {resp2}")
try:
    j3 = json.loads(resp2)
    print(f"OK: valid JSON with keys={list(j3.keys())}")
except Exception as e:
    print(f"FAIL: not valid JSON: {e}")

proc.terminate()
proc.wait(timeout=5)
stderr_out = proc.stderr.read()
lines = [l for l in stderr_out.strip().split("\n") if l.strip()]
print(f"STDERR: {len(lines)} log lines")
if lines:
    for l in lines[:5]:
        print(f"  | {l}")
print("DONE")
