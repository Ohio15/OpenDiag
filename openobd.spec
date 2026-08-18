# PyInstaller spec — builds a single-file Windows exe: openobd.exe
# Build:  pyinstaller openobd.spec   (run from the repo root on Windows)
# Output: dist/openobd.exe
#
# Bundles the seed calibration (data/2010_silverado_full.cal.json) so the exe
# opens on the 2010 Silverado #24 calibration with no external files.

block_cipher = None

a = Analysis(
    ['run.py'],
    pathex=[],
    binaries=[],
    datas=[('data/2010_silverado_full.cal.json', 'data'),
           ('assets/openobd.ico', 'assets')],
    hiddenimports=['serial', 'serial.tools', 'serial.tools.list_ports',
                   'openobd.gt', 'pyqtgraph'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    # numpy is REQUIRED since v0.4.0 (pyqtgraph charting) — do not exclude it
    excludes=['tkinter', 'matplotlib', 'scipy', 'PIL'],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)

pyz = PYZ(a.pure, a.zipped_data, cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.zipfiles,
    a.datas,
    [],
    name='openobd',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=False,      # windowed app, no console
    disable_windowed_traceback=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='assets/openobd.ico',
)
