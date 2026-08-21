"""
appsettings — the ONE way OpenOBD constructs its persistent QSettings.

Every read/write of per-user settings goes through app_settings(). The
4-argument QSettings constructor is used deliberately: it honors
QSettings.setDefaultFormat() and QSettings.setPath(), so a test can redirect
ALL settings to a throwaway INI tree. The familiar 2-argument
QSettings("OpenOBD", "OpenOBD") constructor ignores both and always hits the
real per-user store (the registry on Windows) — which is how a test run once
wrote a demo Live Data layout into the user's real settings. Constructing
QSettings any other way in app code is a defect.

For the app itself nothing changes: with no redirect installed,
defaultFormat() is NativeFormat and the store is exactly the registry key the
2-argument form used.
"""
from __future__ import annotations

from PySide6.QtCore import QSettings

ORGANIZATION = "OpenOBD"
APPLICATION = "OpenOBD"


def app_settings() -> QSettings:
    return QSettings(QSettings.defaultFormat(), QSettings.UserScope,
                     ORGANIZATION, APPLICATION)
