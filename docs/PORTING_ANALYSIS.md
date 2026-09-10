# TikTokDownloader / XHS-Downloader 移植分析结论

> 更新：2026-09-09 · FNB_Download 项目架构说明与上游功能对比

---

## 一、结论（TL;DR）

> **架构说明（最终版）**：本项目采用"**上游零修改完整移植**"方案——
> - `assets/python/tkd/` ← TikTokDownloader 完整源码包
> - `assets/python/xhs/` ← XHS-Downloader 完整源码包
> - `assets/python/fnb_native.py` ← 上游引擎组装层（Settings/Extractor/Downloader/XHS 单例，asyncio 同步化）
> - `native/bridge/fnb_bridge.py` ← 双端统一 JSON 调度层（Linux CPython / Android Chaquopy 共用）
>
> 该方案让上游**全部工程化能力**（curl-cffi TLS 指纹、断点续传、多线程下载、SQLite 记录、增量下载、作者别名映射等）随源码直接可用，升级上游 = 替换对应子目录，无需重新移植。
>
> - Linux 依赖：`requirements-fnb.txt`（curl-cffi/rich/pydantic/lxml/aiofiles，装到 `python_runtime/linux`）
> - Android 依赖：Chaquopy pip（`android/app/build.gradle.kts`）+ 预编译 wheel（`scripts/build_cffi_wheel.sh`）
> - 原生库构建：`hook/build.dart`（native_assets_cli，Linux CMake / Android Gradle externalNativeBuild）

### 与早期"内联精简 bridge"方案的对比

早期方案（`dy_bridge.py` 2596 行内联脚本）已内联上游大部分核心功能，但存在两个结构性缺陷：

1. **工程化能力缺失**：多线程下载、断点续传、SQLite 下载记录去重、增量下载、作者别名映射等均未实现，补齐等于重写上游一半代码。
2. **加密参数维护困境**：ABogus/msToken 实现为复制粘贴，上游若修复风控对抗逻辑无法跟进。

完整源码方案一次性解决这两个问题。

---

## 二、上游功能覆盖情况（当前完整源码方案）

### 抖音（TikTokDownloader → `tkd/` + `fnb_native.get_tkd_engine`）

| 功能 | 状态 | 说明 |
|---|---|---|
| 下载视频/图集/实况 | ✅ | 上游原生 Extractor/Downloader |
| 最高画质/多线程下载 | ✅ | 上游 downloader 原生支持 |
| 断点续传 | ✅ | Range 续传 |
| 已下载去重（ID 库） | ✅ | 上游 manager/cache |
| 批量账号/合集/收藏夹 | ✅ | Account/Mix/Collects API |
| 直播录制 | ✅ | Live + ffmpeg |
| 评论采集 | ✅ | Comment API → CSV/SQLite/XLSX |
| 数据统计/热榜/搜索 | ✅ | Hot/Search API |
| Cookie 自动更新 msToken/ttwid | ✅ | 上游 encrypt 模块 |
| TikTok 支持 | ✅ | 上游原生（需自行配置参数） |

### 小红书（XHS-Downloader → `xhs/` + `fnb_native.get_xhs_engine`）

| 功能 | 状态 | 说明 |
|---|---|---|
| 视频/图集/livePhoto | ✅ | 上游 XHS() 单例 |
| 指定序号选图下载 | ✅ | `extract(link, index=[...])` |
| 数据统计采集 | ✅ | |
| 用户主页批量 | ✅ | User Posted API |
| 图片格式 AUTO/PNG/WEBP/JPEG/HEIC | ✅ | 上游配置项 |
| 作者别名映射/归档 | ✅ | mapping_data |
| xsec_token 链接兼容 | ✅ | |
| MCP / API 模式 | ➖ | 由 Flutter/Ffi 通道替代 |

---

## 三、当前架构

```
Flutter UI (Material 3, Dart 仅交互)
   │  DouyinBridge / XhsBridge / KuaishouBridge
   ▼
DownloadEngine（双通道门面 + progress.json 轮询）
   ├── Linux:  dart:ffi → libfnb_download.so (hook/build.dart 构建)
   │              └─ CPython 嵌入 → fnb_bridge.call()
   └── Android: MethodChannel → Chaquopy → fnb_bridge.call()
                     ▼
        fnb_bridge.py（统一 JSON 调度 + 进度/暂停钩子）
                     ▼
        fnb_native.py（上游引擎组装，asyncio.run 同步化）
           ├── tkd/  (TikTokDownloader 完整源码)
           └── xhs/  (XHS-Downloader 完整源码)
```

**进度上报**：Python 侧劫持上游进度对象 → 原子写 `fnb_progress.json` → Dart 每 800ms 读文件（不进 GIL）。终态立即落盘。

---

## 四、构建与运行

```bash
# 1. Linux Python 运行时（一次性）
bash scripts/download_python.sh
python_runtime/linux/bin/pip3 install -r requirements-fnb.txt

# 2. 同步 Android Python 资产（每次改脚本后）
bash scripts/sync_android_python.sh

# 3. 运行
flutter run -d linux
flutter run -d android
```

Android 原生依赖（curl-impersonate 等）如需预编译：`scripts/build_android_deps.sh`、`scripts/build_cffi_wheel.sh`。

---

## 五、风险与限制

- **加密参数时效性**：上游 README 明确 ABogus/msToken 已过期且不再维护，有效性随平台风控波动；完整源码方案支持按上游文档自行配置参数生成代码。
- **Android 体积**：curl-cffi/rich/pydantic 打包会显著增大 APK；可按平台裁剪依赖。
- **xsec_token**：小红书旧链接可能被风控，建议使用最新分享链接。
- **快手**：沿用轻量 `ks_bridge`（上游 KS-Downloader 仅支持单作品解析）。

---

*上游项目：*
- *TikTokDownloader (DouK-Downloader) by JoeanAmier — GPL-3.0*
- *XHS-Downloader by JoeanAmier — GPL-3.0*
- *本项目延续 GPL-3.0 协议*
