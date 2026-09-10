"""
fnb_native — TikTokDownloader (tkd) / XHS-Downloader (xhs) 原生引擎封装
=====================================================================
在嵌入式 Python 环境中组装上游项目的原生组件：

  DouYin: Settings + ColorfulConsole + Parameter → Extractor/Downloader
          + LinkExtractor + 各 API 接口类（Detail/Account/Comment/Hot/Search…）
  XHS   : XHS(...) 单例（Manager/Download/Explore 全家桶）

设计原则（对上游零修改，数据目录通过 FNB_DATA_DIR 环境变量重定向）：
  - 异步原生 API → 引擎独占事件循环 + 专用线程串行同步化，供 FFI/MethodChannel 调用
  - 无终端环境：API.init_progress_object(server_mode=True) + Downloader(server_mode=True)
    统一使用 FakeProgress，避免 rich 在嵌入式环境渲染失败
  - 存储根目录：tkd/custom/internal.py、xhs/module/static.py 在 import 时
    读取 FNB_DATA_DIR（fnb_bridge.init 在引擎创建前设置）
  - Cookie/代理由 Dart 侧注入
"""
from __future__ import annotations

import asyncio
import functools
import os
import threading


def _sync(async_fn):
    """把引擎的 async 方法包装为同步方法（在引擎独占事件循环中执行）。"""

    @functools.wraps(async_fn)
    def wrapper(self, *args, **kwargs):
        return self._runner.run(async_fn(self, *args, **kwargs))

    return wrapper


# ─────────────────────────── 事件循环工具 ───────────────────────────


class _LoopRunner:
    """独占事件循环：在常驻后台线程中运行，供同步调用方等待协程结果。"""

    def __init__(self, name: str):
        self._loop = asyncio.new_event_loop()
        self._thread = threading.Thread(
            target=self._run_loop, name=name, daemon=True
        )
        self._thread.start()

    def _run_loop(self):
        asyncio.set_event_loop(self._loop)
        self._loop.run_forever()

    def run(self, coro):
        if not self._loop.is_running():
            return asyncio.run(coro)
        done = threading.Event()
        box: dict = {}

        def _schedule():
            task = asyncio.ensure_future(coro, loop=self._loop)

            def _done(t):
                box["exc"] = t.exception()
                box["val"] = None if t.exception() is not None else t.result()
                done.set()

            task.add_done_callback(_done)

        self._loop.call_soon_threadsafe(_schedule)
        done.wait()
        if box.get("exc") is not None:
            raise box["exc"]
        return box.get("val")


# ─────────────────────────── 抖音引擎 (tkd) ───────────────────────────

_tkd_engine = None


class DouyinEngine:
    """抖音原生引擎单例（基于 TikTokDownloader）。"""

    def __init__(self, app_data_dir: str):
        self._runner = _LoopRunner("fnb-tkd-loop")

        from tkd.config import Parameter, Settings
        from tkd.tools import ColorfulConsole
        from tkd import custom
        from tkd.manager import Database, DownloadRecorder
        from tkd.interface.template import API

        # 存储根目录由 tkd/custom/internal.py 在 import 时读取 FNB_DATA_DIR 决定。
        self.volume = custom.VOLUME

        console = ColorfulConsole(debug=False)
        self.console = console

        self.settings = Settings(custom.VOLUME, console)
        self.database = Database()
        self._runner.run(self.database.__aenter__())
        self.recorder = DownloadRecorder(self.database, True, console)

        config = self.settings.read()
        config.update(
            {
                "folder_name": "Download",
                "folder_mode": False,
                "music": False,
                "dynamic_cover": False,
                "static_cover": False,
                "download": True,
                "max_size": 0,
                "chunk": 1024 * 1024 * 2,
                "max_retry": 3,
                "max_pages": 999,
                "timeout": 15,
                "proxy": "",
                "cookie": "",
                # 嵌入式不向文本记录器写采集数据，避免 extractor 需要 recorder
                "storage_format": "",
                "truncate": 80,
                "live_qualities": "origin",
            }
        )

        from tkd.module import Cookie
        from tkd.record import LoggerManager

        self.cookie_obj = Cookie(self.settings, console)
        # logger 形参要求“类”，Parameter 内部执行 logger(VOLUME, console) 实例化
        self.parameter = Parameter(
            self.settings,
            self.cookie_obj,
            logger=LoggerManager,
            console=console,
            cookie=config.get("cookie", ""),
            cookie_tiktok=config.get("cookie_tiktok", ""),
            root=str(custom.VOLUME),
            recorder=self.recorder,
            **{
                k: v
                for k, v in config.items()
                if k not in {"cookie", "cookie_tiktok", "root"}
            },
        )

        # 嵌入式无终端：interface API 统一使用 FakeProgress
        API.init_progress_object(True)

        from tkd.extract import Extractor
        from tkd.downloader import Downloader
        from tkd.link import Extractor as LinkExtractor

        self.extractor = Extractor(self.parameter)
        self.downloader = Downloader(self.parameter, server_mode=True)
        self.links = LinkExtractor(self.parameter)

    def _run(self, coro):
        return self._runner.run(coro)

    @staticmethod
    def _text_recorder(storage_format: str):
        from tkd.storage import RecordManager

        return RecordManager("", False, storage_format)

    # ── Cookie / 代理 ──
    def set_cookie(self, cookie: str) -> dict:
        try:
            from tkd.tools import cookie_str_to_dict

            cookie_dict = cookie_str_to_dict(cookie or "")
            # save_cookie 可能因 _ssl ImportError 或其他问题失败，用 try 保护
            try:
                self.parameter.cookie_object.save_cookie(cookie_dict, "cookie")
            except Exception:
                pass
            # 直接更新 Parameter 上的 cookie 状态
            self.parameter.cookie_dict = cookie_dict
            self.parameter.cookie_str = cookie or ""
            self.parameter.cookie_state = bool(cookie_dict)
            self.parameter.set_headers_cookie()
            # 离线刷新 msToken（从 cookie 字段提取），让上游 API 接受请求
            try:
                self._run(self.parameter.update_params_offline())
            except Exception:
                pass
            return {"success": True}
        except Exception as e:
            return {"success": False, "message": str(e)}

    def set_proxy(self, proxy: str) -> dict:
        try:
            self._run(self.parameter.set_proxy(proxy or None, proxy or None))
            if not proxy:
                os.environ.pop("HTTP_PROXY", None)
                os.environ.pop("HTTPS_PROXY", None)
            else:
                os.environ["HTTP_PROXY"] = proxy
                os.environ["HTTPS_PROXY"] = proxy
            return {"success": True}
        except Exception as e:
            return {"success": False, "message": str(e)}

    # ── 功能 API ──
    async def _details(self, link: str):
        from tkd.interface.detail import Detail

        ids = await self.links.run(link)
        if not ids:
            return []
        details = []
        for i in ids:
            d = await Detail(
                self.parameter,
                self.parameter.cookie_str,
                self.parameter.proxy,
                i,
            ).run()
            if d:
                details.extend(d)
        return details

    @_sync
    async def parse_and_download(
        self, link: str, save_path: str, task_id: str = ""
    ) -> dict:
        details = await self._details(link)
        if not details:
            return {"success": False, "message": "获取作品数据失败（Cookie 可能过期）"}
        recorder = self._text_recorder(self.parameter.storage_format)
        data = await self.extractor.run(details, recorder, type_="detail")
        if not data:
            return {"success": False, "message": "作品数据提取为空"}
        await self.downloader.run(data, "detail")
        title = next((str(d.get("desc", "")) for d in data if d.get("desc")), "")
        return {
            "success": True,
            "message": f"已处理 {len(data)} 个作品",
            "count": len(data),
            "title": title[:60],
        }

    @_sync
    async def batch_download_account(
        self,
        sec_uid: str,
        nickname: str,
        save_path: str,
        task_id: str = "",
        tab: str = "post",
    ) -> dict:
        from datetime import date

        from tkd.interface.account import Account

        account = Account(
            self.parameter,
            self.parameter.cookie_str,
            self.parameter.proxy,
            sec_user_id=sec_uid,
            tab=tab,
        )
        # 批量模式 run() 返回 (response, earliest, latest)
        raw, earliest, latest = await account.run()
        if not raw:
            return {"success": False, "message": "获取账号作品列表失败"}
        recorder = self._text_recorder(self.parameter.storage_format)
        data = await self.extractor.run(
            raw,
            recorder,
            type_="batch",
            name=nickname,
            mark=nickname,
            earliest=earliest or date(2016, 9, 20),
            latest=latest or date.today(),
        )
        if not data:
            return {"success": False, "message": "账号作品筛选后为空"}
        await self.downloader.run(
            data, "batch", mode="post", user_id=sec_uid, user_name=nickname
        )
        return {
            "success": True,
            "message": f"已处理 {len(data)} 个作品",
            "count": len(data),
        }

    @_sync
    async def batch_download_mix(
        self,
        mix_id: str,
        mix_name: str,
        save_path: str,
        task_id: str = "",
    ) -> dict:
        from datetime import date

        from tkd.interface.mix import Mix

        mix = Mix(
            self.parameter,
            self.parameter.cookie_str,
            self.parameter.proxy,
            mix_id=mix_id,
        )
        raw = await mix.run()
        if not raw:
            return {"success": False, "message": "获取合集数据失败"}
        recorder = self._text_recorder(self.parameter.storage_format)
        data = await self.extractor.run(
            raw,
            recorder,
            type_="batch",
            name=mix_name,
            mark=mix_name,
            earliest=date(2016, 9, 20),
            latest=date.today(),
        )
        if not data:
            return {"success": False, "message": "合集作品筛选后为空"}
        await self.downloader.run(
            data, "batch", mode="mix", mix_id=mix_id, mix_title=mix_name
        )
        return {
            "success": True,
            "message": f"已处理 {len(data)} 个作品",
            "count": len(data),
        }

    @_sync
    async def scrape_comments(
        self, link: str, save_path: str, task_id: str = ""
    ) -> dict:
        from tkd.interface.comment import Comment

        ids = await self.links.run(link)
        if not ids:
            return {"success": False, "message": "链接解析失败"}
        total = 0
        for i in ids:
            comments = await Comment(
                self.parameter,
                self.parameter.cookie_str,
                self.parameter.proxy,
                detail_id=i,
                reply=False,
            ).run()
            total += len(comments or [])
        return {
            "success": True,
            "message": f"采集到 {total} 条评论",
            "count": total,
        }

    @_sync
    async def get_hot_list(self, board: int = 0) -> dict:
        from tkd.interface.hot import Hot

        # Hot.run() 返回 (time_str, [(board_index, [words]), ...])
        _, grouped = await Hot(
            self.parameter,
            self.parameter.cookie_str,
            self.parameter.proxy,
        ).run()
        words: list = []
        for index, items in grouped or []:
            if board and index != board:
                continue
            for w in items or []:
                word = getattr(w, "word", None)
                if word is None and isinstance(w, dict):
                    word = w.get("word")
                if word:
                    words.append(str(word))
        return {"success": bool(words), "data": words, "count": len(words)}

    @_sync
    async def search_general(
        self, keyword: str, save_path: str = "", task_id: str = ""
    ) -> dict:
        from tkd.interface.search import Search

        search = Search(
            self.parameter,
            self.parameter.cookie_str,
            self.parameter.proxy,
            keyword=keyword,
            channel=0,
            pages=1,
        )
        raw = await search.run()
        if not raw:
            return {"success": False, "message": "未搜索到结果"}
        recorder = self._text_recorder(self.parameter.storage_format)
        data = await self.extractor.run(raw, recorder, type_="search", tab=0)
        items = [
            {
                "id": str(d.get("id", "")),
                "desc": str(d.get("desc", "")),
                "nickname": str(d.get("nickname", "")),
                "sec_uid": str(d.get("sec_uid", "")),
                "type": str(d.get("type", "")),
            }
            for d in data
        ]
        return {"success": bool(items), "data": items, "count": len(items)}

    @_sync
    async def detect_link_info(self, link: str) -> dict:
        from tkd.interface.detail import Detail

        ids = await self.links.run(link)
        if not ids:
            return {"success": False, "message": "无法解析链接"}
        detail = await Detail(
            self.parameter,
            self.parameter.cookie_str,
            self.parameter.proxy,
            ids[0],
        ).run()
        if detail:
            d = detail[0]
            return {
                "success": True,
                "title": d.get("desc", ""),
                "type": d.get("type", ""),
                "author": {
                    "sec_uid": d.get("sec_uid", ""),
                    "nickname": d.get("nickname", ""),
                    "uid": d.get("uid", ""),
                },
            }
        return {"success": False, "message": "未识别到作品"}

    async def close(self):
        try:
            await self.parameter.close_client()
        except Exception:
            pass


def get_tkd_engine(app_data_dir: str = ""):
    global _tkd_engine
    if _tkd_engine is None:
        _tkd_engine = DouyinEngine(app_data_dir)
    return _tkd_engine


# ─────────────────────────── 小红书引擎 (xhs) ───────────────────────────

_xhs_engine = None


class XhsEngine:
    """XHS-Downloader 原生引擎（XHS 单例）。"""

    def __init__(self, app_data_dir: str):
        self._runner = _LoopRunner("fnb-xhs-loop")

        from xhs.application import XHS as _XHS

        self.app = _XHS(
            work_path=app_data_dir or "",
            folder_name="XhsDownload",
            name_format="发布时间 作者昵称 作品标题",
            cookie="",
            proxy=None,
            timeout=10,
            max_retry=3,
            image_format="AUTO",
            image_download=True,
            video_download=True,
            live_download=False,
            download_record=True,
            author_archive=False,
            folder_mode=False,
            script_server=False,
        )

    def _run(self, coro):
        return self._runner.run(coro)

    def set_cookie(self, cookie: str) -> dict:
        try:
            self.app.manager.cookie = cookie or ""
            return {"success": True}
        except Exception as e:
            return {"success": False, "message": str(e)}

    def set_proxy(self, proxy: str) -> dict:
        try:
            self.app.manager.proxy = proxy or None
            return {"success": True}
        except Exception as e:
            return {"success": False, "message": str(e)}

    @_sync
    async def parse_and_download(
        self, link: str, save_path: str, task_id: str = ""
    ) -> dict:
        result = await self.app.extract(link, download=True, check_record=True)
        ok = [r for r in result if isinstance(r, dict) and r.get("下载地址")]
        return {
            "success": bool(ok),
            "message": (
                f"共 {len(result)} 个作品，成功 {len(ok)}" if result else "解析失败"
            ),
            "count": len(result),
        }

    @_sync
    async def extract_data(self, link: str, task_id: str = "") -> dict:
        result = await self.app.extract(link, download=False)
        return {
            "success": bool(result),
            "data": result,
            "count": len(result),
        }

    @_sync
    async def detect_link_info(self, link: str) -> dict:
        result = await self.app.extract(link, download=False, check_record=False)
        if not result:
            return {"success": False, "message": "无法解析小红书链接"}
        first = result[0] if isinstance(result[0], dict) else {}
        return {
            "success": True,
            "title": str(first.get("作品标题", "")),
            "type": str(first.get("作品类型", "")),
            "author": {
                "sec_uid": "",
                "nickname": str(first.get("作者昵称", "")),
                "uid": str(first.get("作者ID", "")),
            },
        }


def get_xhs_engine(app_data_dir: str = ""):
    global _xhs_engine
    if _xhs_engine is None:
        _xhs_engine = XhsEngine(app_data_dir)
    return _xhs_engine
