# -*- mode: python ; coding: utf-8 -*-
from PyInstaller.utils.hooks import collect_submodules
from PyInstaller.utils.hooks import collect_all

datas = [('/home/npznnz/Project/FNB_Download/assets/python/tkd', 'tkd'), ('/home/npznnz/Project/FNB_Download/assets/python/xhs', 'xhs'), ('/home/npznnz/Project/FNB_Download/assets/python/fnb_bridge.py', '.'), ('/home/npznnz/Project/FNB_Download/assets/python/fnb_native.py', '.'), ('/home/npznnz/Project/FNB_Download/assets/python/compat_setup.py', '.')]
binaries = []
hiddenimports = ['_sqlite3', 'aiosqlite', 'fnb_bridge', 'fnb_native', 'compat_setup', 'tkd', 'tkd.config', 'tkd.config.parameter', 'tkd.tools', 'tkd.custom', 'tkd.manager', 'tkd.interface', 'tkd.interface.template', 'tkd.interface.detail', 'tkd.interface.account', 'tkd.interface.mix', 'tkd.interface.comment', 'tkd.interface.hot', 'tkd.interface.search', 'tkd.extract', 'tkd.downloader', 'tkd.link', 'tkd.storage', 'tkd.record', 'tkd.module', 'tkd.models', 'tkd.encrypt', 'xhs', 'xhs.application', 'xhs.expansion', 'xhs.module', 'httpx', 'httpx._client', 'curl_cffi', 'curl_cffi.requests']
hiddenimports += collect_submodules('http')
hiddenimports += collect_submodules('email')
hiddenimports += collect_submodules('xml')
hiddenimports += collect_submodules('json')
hiddenimports += collect_submodules('encodings')
tmp_ret = collect_all('sqlite3')
datas += tmp_ret[0]; binaries += tmp_ret[1]; hiddenimports += tmp_ret[2]


a = Analysis(
    ['/home/npznnz/Project/FNB_Download/assets/python/fnb_subprocess.py'],
    pathex=[],
    binaries=binaries,
    datas=datas,
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='fnb_engine',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
