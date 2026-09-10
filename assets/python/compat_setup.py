"""
compat_setup — Android/Linux 兼容层
===================================
为嵌入式 CPython 环境提供缺失依赖的 shim:
  - curl_cffi   → httpx 回退
  - pydantic    → dataclasses 简化版
  - javascript  → 空 stub
同时把 assets/python/{tkd,xhs} 加入 sys.path。
"""
from __future__ import annotations

import os
import sys
from types import ModuleType


def setup(app_data_dir: str = ""):
    """在 fnb_bridge.init() 中调用，完成所有兼容配置。"""
    # 1) 确保 assets/python 在 sys.path（含 tkd/、xhs/ 子包）
    _add_asset_paths()

    # 2) curl_cffi → httpx shim
    _install_curl_cffi_shim()

    # 3) pydantic stub (仅满足 import 需求)
    _install_pydantic_shim()

    # 4) javascript stub
    _install_javascript_shim()

    # 5) rich 嵌入式 stub（fnb_native 已有 _noop_progress，此处兜底）
    _install_rich_shim()


def _add_asset_paths():
    """把 native/bridge/ 和 assets/python/ 加入 sys.path（开发态/发行态）。"""
    # 本文件位于 native/bridge/
    here = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(os.path.dirname(here))  # FNB_Download/
    assets_python = os.path.join(project_root, "assets", "python")

    paths_to_add = [here, assets_python]
    # 发行态：当前目录可能就是 scripts 目录
    cwd = os.getcwd()
    for p in [os.path.join(cwd, "assets", "python"), cwd]:
        if os.path.isdir(p) and p not in paths_to_add:
            paths_to_add.append(p)

    for p in paths_to_add:
        if p and os.path.isdir(p) and p not in sys.path:
            sys.path.insert(0, p)


def _install_curl_cffi_shim():
    """curl_cffi → httpx 兼容 shim"""
    try:
        import curl_cffi  # noqa: F401 — 已安装则跳过
        return
    except ImportError:
        pass

    try:
        import httpx
    except ImportError:
        return  # httpx 也不可用，放弃

    shim = ModuleType("curl_cffi")
    shim_requests = ModuleType("curl_cffi.requests")

    class _Session:
        """httpx-backed session mimicking curl_cffi.requests.Session"""

        def __init__(self, impersonate=None, **kw):
            self._client = httpx.Client(
                timeout=30,
                follow_redirects=True,
                http2=True,
            )
            self.headers = {}
            self.cookies = {}

        def get(self, url, **kw):
            headers = {**self.headers, **(kw.get("headers") or {})}
            r = self._client.get(url, headers=headers)
            return _Response(r)

        def post(self, url, **kw):
            headers = {**self.headers, **(kw.get("headers") or {})}
            data = kw.get("data") or kw.get("content")
            r = self._client.post(url, headers=headers, content=data)
            return _Response(r)

        def head(self, url, **kw):
            headers = {**self.headers, **(kw.get("headers") or {})}
            r = self._client.head(url, headers=headers)
            return _Response(r)

        def close(self):
            self._client.close()

        def __enter__(self):
            return self

        def __exit__(self, *a):
            self.close()

    class _Response:
        """httpx.Response → curl_cffi.Response-like"""

        def __init__(self, httpx_resp):
            self._r = httpx_resp

        @property
        def status_code(self):
            return self._r.status_code

        @property
        def text(self):
            return self._r.text

        @property
        def content(self):
            return self._r.content

        @property
        def headers(self):
            return dict(self._r.headers)

        @property
        def url(self):
            return str(self._r.url)

        def json(self):
            return self._r.json()

        def raise_for_status(self):
            self._r.raise_for_status()

    # ── Standalone functions (used by tkd: `from curl_cffi.requests import get`) ──
    def _get(url, **kw):
        return _Session().get(url, **kw)

    def _post(url, **kw):
        return _Session().post(url, **kw)

    def _head(url, **kw):
        return _Session().head(url, **kw)

    shim_requests.get = _get
    shim_requests.post = _post
    shim_requests.head = _head
    shim_requests.Session = _Session

    # ── Async version stub ──
    class _AsyncSession:
        def __init__(self, **kw):
            self._client = httpx.AsyncClient(
                timeout=30, follow_redirects=True, http2=True
            )
            self.headers = {}

        async def get(self, url, **kw):
            r = await self._client.get(url, headers={**self.headers, **(kw.get("headers") or {})})
            return _Response(r)

        async def post(self, url, **kw):
            r = await self._client.post(
                url,
                headers={**self.headers, **(kw.get("headers") or {})},
                content=kw.get("data") or kw.get("content"),
            )
            return _Response(r)

        async def close(self):
            await self._client.aclose()

        async def __aenter__(self):
            return self

        async def __aexit__(self, *a):
            await self.close()

    shim_requests.AsyncSession = _AsyncSession
    shim.AsyncSession = _AsyncSession

    # ── Exceptions (used by tkd: `from curl_cffi.requests.exceptions import RequestException, Timeout`) ──
    shim_exceptions = ModuleType("curl_cffi.requests.exceptions")

    class RequestException(Exception):
        pass

    class Timeout(RequestException):
        pass

    class HTTPError(RequestException):
        pass

    shim_exceptions.RequestException = RequestException
    shim_exceptions.Timeout = Timeout
    shim_exceptions.HTTPError = HTTPError

    shim.requests = shim_requests
    sys.modules["curl_cffi"] = shim
    sys.modules["curl_cffi.requests"] = shim_requests
    sys.modules["curl_cffi.requests.exceptions"] = shim_exceptions


def _install_pydantic_shim():
    """极简 pydantic stub（满足 import pydantic / from pydantic import BaseModel）"""
    try:
        import pydantic  # noqa: F401
        return
    except ImportError:
        pass

    shim = ModuleType("pydantic")

    class BaseModel:
        def __init__(self, **kw):
            for k, v in kw.items():
                setattr(self, k, v)

        def model_dump(self, **kw):
            return self.__dict__.copy()

        def dict(self):
            return self.__dict__.copy()

        class Config:
            extra = "allow"

    shim.BaseModel = BaseModel
    shim.Field = lambda default=None, **kw: default

    sys.modules["pydantic"] = shim


def _install_javascript_shim():
    """javascript 空 stub"""
    try:
        import javascript  # noqa: F401
        return
    except ImportError:
        pass

    shim = ModuleType("javascript")
    shim.document = ModuleType("javascript.document")
    shim.window = ModuleType("javascript.window")
    sys.modules["javascript"] = shim
    sys.modules["javascript.document"] = shim.document
    sys.modules["javascript.window"] = shim.window


def _install_rich_shim():
    """rich 嵌入式 stub"""
    try:
        import rich  # noqa: F401
        # 已安装，但 Progress 等在无终端环境需要 stub
    except ImportError:
        pass

    # 不覆盖已安装的 rich，仅确保 Progress 在无 TTY 下不崩溃
    # fnb_native.py 已有 _noop_progress 处理
