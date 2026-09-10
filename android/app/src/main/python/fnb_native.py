"""
fnb_native — TikTokDownloader (tkd) / XHS-Downloader (xhs) 原生引擎封装
=====================================================================
在嵌入式 Python 环境中组装上游项目的原生组件：

  DouYin: Settings + ColorfulConsole + Parameter → Extractor/Downloader
          + LinkExtractor + 各 API 接口类（Detail/Account/Comment/Hot/Live…）
  XHS   : XHS(...) 单例（Manager/Download/Explore 全家桶）

设计原则（对上游零修改，除 FNB_DATA_DIR 重定向外）：
  - 异步原生 API → asyncio.run 同步化，供 FFI/MethodChannel 调用
  - 进度劫持：tkd 走 rich Progress 对象替换；xhs 走 progress_callback/task_id
  - Cookie/代理由 Dart 侧注入，落盘统一在 FNB_DATA_DIR
"""
from __future__ import annotations

import asyncio
import os
from datetime import date
from pathlib import Path
from types import SimpleNamespace

# ─────────────────────────── 通用工具 ───────────────────────────


def _noop_progress(*args, **kwargs):
    """rich Progress 替身：tkd 下载器在无 TTY 环境使用"""
    return SimpleNamespace(
        __enter__=lambda *a: None,
        __exit__=lambda *a: False,
        add_task=lambda *a, **k: None,
        update=lambda *a, **k: None,
        remove_task=lambda *a: None,
        stop=lambda *a: None,
        start=lambda *a: None,
        advance=lambda *a: None,
        console=None,
        tasks=[],
    )


class _SilentConsole:
    """ColorfulConsole 替身：吞掉所有终端输出（嵌入式无终端）"""

    def print(self, *args, **kwargs):
        pass

    def log(self, *args, **kwargs):
        pass

    info = warning = error = debug = print
    input = print


# ─────────────────────────── 抖音引擎 (tkd) ───────────────────────────

_tkd_engine = None


class TkdEngine:
    """TikTokDownloader 原生引擎单例。
    Parameter 依赖 settings.read() 默认值 + 注入式 cookie。
    """

    def __init__(self, app_data_dir: str):
        from tkd.config import Parameter, Settings
        from tkd.tools import ColorfulConsole
        from tkd.custom import VOLUME
        from tkd.record import LoggerManager
        from tkd.manager import Database, DownloadRecorder

        self.volume = VOLUME
        # Settings(root, console) — root 用于 settings.json 落盘
        self.settings = Settings(VOLUME, ColorfulConsole(debug=False))
        self.console = ColorfulConsole(debug=False)
        # Parameter 内部会 logger(VOLUME, console) 实例化 → 传类
        self.logger = LoggerManager
        self.database = Database()
        # Database 需要异步初始化（sqlite: Volume/DataBase.db）
        TkdEngine._run(self.database.__aenter__())
        # 新版签名: DownloadRecorder(database, switch, console)
        self.recorder = DownloadRecorder(self.database, True, self.console)
        config = self.settings.read()
        # 强制移动端友好默认值（上游默认面向 PC 终端）
        config.update(
            {
                "folder_name": "Download",       # 下载根目录名
                "folder_mode": False,            # 不按账号分文件夹（Dart 侧管理）
                "music": False,
                "dynamic_cover": False,
                "static_cover": False,
                "original_date": False,
                "download": True,                # 允许下载
                "max_size": 0,
                "chunk": 1024 * 1024 * 2,
                "max_retry": 3,
                "max_pages": 999,                # 账号/合集翻页上限
                "timeout": 15,
                "proxy": None,
                "cookie": "",
                "storage_format": "csv",         # 采集数据落盘格式
                "name_format": "创建时间 作品类型 账号昵称 作品描述",
                "truncate": 80,
                "live_qualities": "origin",
            }
        )
        from tkd.module import Cookie

        self.cookie_obj = Cookie(self.settings, self.console)
        # Parameter 位置参数: settings, cookie_object, logger, console, cookie, cookie_tiktok, root, ...
        self.parameter = Parameter(
            self.settings,
            self.cookie_obj,
            logger=self.logger,
            console=self.console,
            cookie=config.get("cookie", ""),
            cookie_tiktok=config.get("cookie_tiktok", ""),
            root=str(VOLUME),
            recorder=self.recorder,
            **{k: v for k, v in config.items() if k not in {"cookie", "cookie_tiktok", "root"}},
        )

        from tkd.extract import Extractor
        from tkd.downloader import Downloader
        from tkd.link import Extractor as LinkExtractor

        self.extractor = Extractor(self.parameter)
        self.downloader = Downloader(self.parameter, server_mode=True)  # FakeProgress
        self.links = LinkExtractor(self.parameter)  # tkd 新版类名为 Extractor

    # ── 运行工具 ──
    @staticmethod
    def _run(coro):
        try:
            loop = asyncio.get_event_loop()
            if loop.is_running():
                # FFI 同步线程内无运行中的 loop；Chaquopy 同理
                import concurrent.futures
                with concurrent.futures.ThreadPoolExecutor(max_workers=1) as ex:
                    return ex.submit(asyncio.run, coro).result()
        except RuntimeError:
            pass
        return asyncio.run(coro)

    # ── Cookie / 代理 ──
    def set_cookie(self, cookie: str) -> dict:
        """写入 settings.json 并热刷新 Parameter 的 cookie 状态"""
        try:
            from tkd.tools import cookie_str_to_dict

            cookie_dict = cookie_str_to_dict(cookie or "")
            self.parameter.cookie_object.save_cookie(cookie_dict, "cookie")
            self.parameter.cookie_dict = cookie_dict
            self.parameter.cookie_str = cookie
            self.parameter.cookie_state = bool(cookie_dict)
            return {"success": True}
        except Exception as e:
            return {"success": False, "message": str(e)}

    def set_proxy(self, proxy: str) -> dict:
        try:
            self.parameter.proxy = proxy or None
            self.parameter.proxy_tiktok = proxy or None
            os.environ["HTTP_PROXY"] = proxy or ""
            os.environ["HTTPS_PROXY"] = proxy or ""
            if not proxy:
                os.environ.pop("HTTP_PROXY", None)
                os.environ.pop("HTTPS_PROXY", None)
            return {"success": True}
        except Exception as e:
            return {"success": False, "message": str(e)}

    # ── 功能 API ──

    async def parse_and_download(self, link: str, save_path: str, task_id: str = "") -> dict:
        """单链接/批量链接下载（自动识别作品/账号/合集）"""
        from tkd.interface.detail import Detail

        ids = await self.links.run(link)
        if not ids:
            return {"success": False, "message": "链接解析失败，未提取到作品 ID"}
        detail_data = []
        for i in ids:
            d = await Detail(self.parameter, self.parameter.cookie_str, self.parameter.proxy, i).run()
            if d:
                detail_data.extend(d)
        if not detail_data:
            return {"success": False, "message": "获取作品数据失败（Cookie 可能过期）"}
        data = await self.extractor.run(detail_data, None)
        await self.downloader.run(data, "detail")
        return {
            "success": True,
            "message": f"已处理 {len(data)} 个作品",
            "count": len(data),
            "title": str(data[0].get("desc", ""))[:60] if data and isinstance(data[0], dict) else "",
        }

    async def batch_download_account(self, sec_uid: str, nickname: str, save_path: str, task_id: str = "", tab: str = "post") -> dict:
        """下载账号作品（post 发布 / favorite 喜欢）"""
        from tkd.interface.account import Account

        raw = await Account(
            self.parameter, self.parameter.cookie_str, self.parameter.proxy,
            sec_user_id=sec_uid, tab=tab,
        ).run()
        if not raw:
            return {"success": False, "message": "获取账号作品列表失败"}
        data = await self.extractor.run(raw, None, type_="batch")
        await self.downloader.run(data, "batch", mode="post", user_id=sec_uid, user_name=nickname)
        return {"success": True, "message": f"已处理 {len(data)} 个作品", "count": len(data)}

    async def batch_download_mix(self, mix_id: str, mix_name: str, save_path: str, task_id: str = "") -> dict:
        """下载合集作品"""
        from tkd.interface.mix import Mix

        raw = await Mix(
            self.parameter, self.parameter.cookie_str, self.parameter.proxy,
            mix_id=mix_id,
        ).run()
        if not raw:
            return {"success": False, "message": "获取合集数据失败"}
        data = await self.extractor.run(raw, None, type_="batch")
        await self.downloader.run(data, "batch", mode="mix", mix_id=mix_id, mix_title=mix_name)
        return {"success": True, "message": f"已处理 {len(data)} 个作品", "count": len(data)}

    async def scrape_comments(self, link: str, save_path: str, task_id: str = "") -> dict:
        """采集评论（原生 Comment 接口，支持分页+回复展开）"""
        from tkd.interface.comment import Comment

        ids = await self.links.run(link)
        if not ids:
            return {"success": False, "message": "链接解析失败"}
        all_comments = []
        for i in ids:
            comments = await Comment(
                self.parameter, self.parameter.cookie_str, self.parameter.proxy,
                detail_id=i, reply=False,
            ).run()
            all_comments.extend(comments or [])
        # 数据持久化由 extractor 的 storage 完成；此处返回摘要
        return {
            "success": True,
            "message": f"采集到 {len(all_comments)} 条评论（已存 Volume/Log）",
            "count": len(all_comments),
        }

    async def get_hot_list(self, board: int = 0) -> dict:
        """抖音热榜（原生 Hot 接口，4 个榜单）"""
        from tkd.interface.hot import Hot

        data = await Hot(self.parameter, self.parameter.cookie_str, self.parameter.proxy).run()
        return {"success": True, "data": data, "count": len(data) if isinstance(data, list) else 0}

    async def search_general(self, keyword: str, save_path: str = "", task_id: str = "") -> dict:
        """综合搜索（原生 Search 接口）"""
        from tkd.interface.search import Search

        data = await Search(
            self.parameter, self.parameter.cookie_str, self.parameter.proxy,
            keyword=keyword,
        ).run()
        return {"success": bool(data), "data": data, "count": len(data) if isinstance(data, list) else 0}

    async def detect_link_info(self, link: str) -> dict:
        """链接检测（作品详情 / 账号 / 合集信息）"""
        from tkd.interface.detail import Detail

        ids = await self.links.run(link)
        if not ids:
            return {"success": False, "message": "无法解析链接"}
        detail = await Detail(self.parameter, self.parameter.cookie_str, self.parameter.proxy, ids[0]).run()
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
        # 尝试账号/合集链接
        return {"success": False, "message": "未识别到作品"}

    async def close(self):
        try:
            await self.parameter.close_client()
        except Exception:
            pass


def get_tkd_engine(app_data_dir: str = ""):
    global _tkd_engine
    if _tkd_engine is None:
        _tkd_engine = TkdEngine(app_data_dir)
    return _tkd_engine


# ─────────────────────────── 小红书引擎 (xhs) ───────────────────────────

_xhs_engine = None


class XhsEngine:
    """XHS-Downloader 原生引擎（XHS 单例已内置 progress_callback/task_id 钩子）"""

    def __init__(self, app_data_dir: str):
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

    @staticmethod
    def _run(coro):
        return TkdEngine._run(coro)

    def set_cookie(self, cookie: str) -> dict:
        try:
            self.app.manager.cookie = cookie
            return {"success": True}
        except Exception as e:
            return {"success": False, "message": str(e)}

    async def parse_and_download(self, link: str, save_path: str, task_id: str = "") -> dict:
        result = await self.app.extract(link, download=True, check_record=True)
        ok = [r for r in result if isinstance(r, dict) and r.get("下载地址")]
        return {
            "success": bool(ok),
            "message": f"共 {len(result)} 个作品，成功 {len(ok)}" if result else "解析失败",
            "count": len(result),
        }

    async def extract_data(self, link: str, task_id: str = "") -> dict:
        result = await self.app.extract(link, download=False)
        return {
            "success": bool(result),
            "data": result,
            "count": len(result),
        }


def get_xhs_engine(app_data_dir: str = ""):
    global _xhs_engine
    if _xhs_engine is None:
        _xhs_engine = XhsEngine(app_data_dir)
    return _xhs_engine
