"""
fnb_bridge — FNB Download 纯原生调度层（v3）
============================================
所有功能走 fnb_native (TikTokDownloader + XHS-Downloader) 原生实现。
Android 上通过 compat shim (curl_cffi/pydantic/javascript) 兼容运行。
无精简版回退，功能与参考工程完全一致。
"""
import json
import os
import sys
import time
import traceback
from concurrent.futures import ThreadPoolExecutor, TimeoutError as FuturesTimeout

# 全局线程池，用于给引擎调用加超时
_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="fnb-dispatch")
_DISPATCH_TIMEOUT = 30  # 秒，引擎调用超时

_APP_DATA_DIR = ""
_READY = False
_ENGINE = {"douyin": None, "xhs": None}
_PROGRESS = {}
_LOCAL_PAUSES = set()
_PROGRESS_FILENAME = "fnb_progress.json"
_progress_last_write = 0.0
_PROGRESS_MIN_INTERVAL = 0.4


def _log(msg):
    try:
        sys.stderr.write(f"[fnb_bridge] {msg}\n")
        sys.stderr.flush()
    except Exception:
        pass


# ── 进度管理 ──

def _progress_file():
    d = _APP_DATA_DIR or os.path.expanduser("~")
    return os.path.join(d, _PROGRESS_FILENAME)


def _flush_progress(force=False):
    global _progress_last_write
    now = time.time()
    if not force and (now - _progress_last_write) < _PROGRESS_MIN_INTERVAL:
        return
    _progress_last_write = now
    try:
        path = _progress_file()
        os.makedirs(os.path.dirname(path), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(_PROGRESS, f, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception as e:
        _log(f"flush_progress failed: {e}")


def _update_progress(task_id, downloaded, total, title="", status=""):
    if not task_id:
        return
    key = str(task_id)
    item = _PROGRESS.setdefault(key, {})
    if downloaded is not None:
        item["downloaded"] = int(downloaded)
    if total is not None:
        item["total"] = int(total)
    if title:
        item["title"] = str(title)
    if status:
        item["status"] = status
    item["ts"] = int(time.time() * 1000)
    _flush_progress(force=(status in ("done", "failed", "pausing")))


def get_progress(task_id: str = "") -> str:
    try:
        if task_id:
            item = _PROGRESS.get(str(task_id))
            return json.dumps({"success": True, "progress": item}, ensure_ascii=False)
        return json.dumps({"success": True, "progress": _PROGRESS}, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"success": False, "message": str(e)})


def clear_progress(task_id: str = "") -> str:
    try:
        if task_id:
            _PROGRESS.pop(str(task_id), None)
        else:
            _PROGRESS.clear()
        _flush_progress(force=True)
        return json.dumps({"success": True})
    except Exception as e:
        return json.dumps({"success": False, "message": str(e)})


def pause_task(task_id: str) -> str:
    _LOCAL_PAUSES.add(str(task_id))
    _update_progress(task_id, None, None, status="pausing")
    _flush_progress(force=True)
    return json.dumps({"success": True})


def resume_task(task_id: str) -> str:
    _LOCAL_PAUSES.discard(str(task_id))
    _update_progress(task_id, None, None, status="running")
    _flush_progress(force=True)
    return json.dumps({"success": True})


def is_task_paused(task_id: str) -> bool:
    return str(task_id) in _LOCAL_PAUSES


# ── 引擎管理 ──

def _get_engine(platform: str):
    if _ENGINE.get(platform) is not None:
        return _ENGINE[platform]
    import fnb_native
    if platform == "douyin":
        eng = fnb_native.get_tkd_engine(_APP_DATA_DIR)
    elif platform == "xhs":
        eng = fnb_native.get_xhs_engine(_APP_DATA_DIR)
    else:
        return None
    _ENGINE[platform] = eng
    return eng


def _ensure_site_packages():
    """把项目 venv 的 site-packages 加入 sys.path（嵌入式解释器不带 venv 激活）。"""
    import glob
    roots = [
        os.path.dirname(_APP_DATA_DIR) if _APP_DATA_DIR else "",
        os.getcwd(),
    ]
    seen = set()
    for root in roots:
        if not root:
            continue
        for sp in glob.glob(os.path.join(root, ".venv-linux", "lib", "python3*", "site-packages")):
            if sp not in sys.path and sp not in seen:
                sys.path.append(sp)
                seen.add(sp)
                _log(f"site-packages: {sp}")


def init(app_data_dir: str = "") -> str:
    global _APP_DATA_DIR, _READY
    try:
        _APP_DATA_DIR = app_data_dir or ""
        if _APP_DATA_DIR:
            os.makedirs(_APP_DATA_DIR, exist_ok=True)
            os.environ["HOME"] = _APP_DATA_DIR
            # tkd/xhs 在 import 时依据该变量重定向存储根目录，必须在创建引擎前设置
            os.environ["FNB_DATA_DIR"] = _APP_DATA_DIR
        here = os.path.dirname(os.path.abspath(__file__))
        assets = os.path.join(os.path.dirname(here), "assets", "python")
        for p in [here, assets]:
            if p not in sys.path:
                sys.path.insert(0, p)
        _ensure_site_packages()
        import compat_setup
        compat_setup.setup(_APP_DATA_DIR)
        _READY = True
        _log(f"initialized, app_data_dir={_APP_DATA_DIR}")
        return json.dumps({"success": True, "app_data_dir": _APP_DATA_DIR})
    except Exception as e:
        _READY = False
        return json.dumps({"success": False, "message": str(e)})


def status() -> str:
    return json.dumps({
        "success": True, "ready": _READY,
        "app_data_dir": _APP_DATA_DIR,
        "active_tasks": list(_PROGRESS.keys()),
        "python": sys.version.split()[0],
    })


def call(function: str, json_args: str = "{}") -> str:
    try:
        a = json.loads(json_args) if json_args else {}
    except Exception as e:
        return json.dumps({"success": False, "message": f"参数解析失败: {e}"})

    platform = str(a.pop("platform", "") or "douyin")
    task_id = str(a.get("task_id", "") or "")
    label = a.get("link") or a.get("keyword") or function

    if function == "status":
        return status()
    if function == "get_progress":
        return get_progress(a.get("task_id", ""))
    if function == "clear_progress":
        return clear_progress(a.get("task_id", ""))

    if task_id:
        _update_progress(task_id, 0, 0, str(label)[:80], status="running")
        _flush_progress(force=True)

    result = None
    try:
        eng = _get_engine(platform)
        if eng is None:
            result = {"success": False, "message": f"平台 {platform} 不支持"}
        else:
            # 用线程池 + 超时包装，防止网络请求无限卡死
            future = _executor.submit(_dispatch, eng, platform, function, a)
            try:
                result = future.result(timeout=_DISPATCH_TIMEOUT)
            except FuturesTimeout:
                result = {"success": False, "message": f"{function} 超时（{_DISPATCH_TIMEOUT}秒），请检查网络或 Cookie"}
    except Exception as e:
        _log(traceback.format_exc())
        result = {"success": False, "message": f"{function} 异常: {e}"}

    if task_id and result:
        status_tag = "done" if result.get("success") else "failed"
        _update_progress(task_id, None, None,
                         str(result.get("title") or result.get("message", ""))[:80],
                         status=status_tag)
        _flush_progress(force=True)

    return json.dumps(result, ensure_ascii=False, default=str)


def _dispatch(eng, platform, function, a):
    """根据功能名路由到原生引擎方法（引擎方法已同步化）。"""
    save_path = a.get("save_path", "") or ""
    task_id = a.get("task_id", "") or ""

    if function == "set_cookie":
        return eng.set_cookie(a.get("cookie", ""))
    if function == "set_proxy":
        return eng.set_proxy(a.get("proxy", ""))
    if function == "get_cookie_status":
        return {"success": True, "logged_in": getattr(
            getattr(eng, "parameter", None), "cookie_state", True)}

    handlers = {
        "parse_and_download": lambda: eng.parse_and_download(
            a.get("link", ""), save_path, task_id),
        "detect_link_info": lambda: eng.detect_link_info(a.get("link", "")),
        "batch_download_account": lambda: eng.batch_download_account(
            a.get("sec_uid", ""), a.get("nickname", ""), save_path, task_id),
        "batch_download_mix": lambda: eng.batch_download_mix(
            a.get("mix_id", ""), a.get("mix_name", ""), save_path, task_id),
        "scrape_comments": lambda: eng.scrape_comments(
            a.get("link", ""), save_path, task_id),
        "get_hot_list": lambda: eng.get_hot_list(int(a.get("board", 0))),
        "search_general": lambda: eng.search_general(
            a.get("keyword", ""), save_path, task_id),
        "extract_data": lambda: eng.extract_data(a.get("link", ""), task_id),
    }
    if function in handlers:
        return _as_dict(handlers[function]())

    return {"success": False, "message": f"未知功能: {function}"}


def _as_dict(x):
    if isinstance(x, dict):
        return x
    if isinstance(x, str):
        try:
            v = json.loads(x)
            return v if isinstance(v, dict) else {"success": True, "data": v}
        except Exception:
            return {"success": True, "message": x}
    return {"success": True, "data": x}


def parse_args_and_call(module: str, function: str, args_json: str) -> str:
    return call(function, args_json)
