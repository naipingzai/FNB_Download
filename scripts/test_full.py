#!/usr/bin/env python3
"""全面测试 Python 引擎"""
import sys, os, time, traceback
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'assets', 'python'))
import fnb_bridge

def test(name, fn):
    t0 = time.time()
    try:
        r = fn()
        dt = time.time() - t0
        ok = '"success":true' in r.replace(' ', '').replace("'", '"') or '"success": true' in r
        print(f"[{'OK' if ok else 'FAIL'}] {name} ({dt:.1f}s): {r[:200]}")
        return ok
    except Exception as e:
        dt = time.time() - t0
        print(f"[ERR]  {name} ({dt:.1f}s): {e}")
        traceback.print_exc()
        return False

# 1. init
test("init", lambda: fnb_bridge.init("/tmp/fnb_full_test"))

# 2. status
test("status", lambda: fnb_bridge.call("status", "{}"))

# 3. set_cookie douyin
test("set_cookie_douyin", lambda: fnb_bridge.call("set_cookie", '{"platform": "douyin", "cookie": "test=1"}'))

# 4. set_cookie xhs
test("set_cookie_xhs", lambda: fnb_bridge.call("set_cookie", '{"platform": "xhs", "cookie": "test=1"}'))

# 5. get_progress
test("get_progress", lambda: fnb_bridge.call("get_progress", "{}"))

# 6. get_hot_list (should timeout fast without cookie)
test("get_hot_list", lambda: fnb_bridge.call("get_hot_list", "{}"))

print("DONE")
