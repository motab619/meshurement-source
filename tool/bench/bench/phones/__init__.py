# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""Phone control: iOS over `xcrun devicectl`, Android over `adb`, the iOS
simulator over `xcrun simctl` (T1, no radios)."""

from __future__ import annotations

from ..config import PhoneConfig


def for_config(cfg: PhoneConfig):
    if cfg.platform == "ios":
        from .ios import IosPhone
        return IosPhone(cfg.id, cfg.bundle_id)
    if cfg.platform == "android":
        from .android import AndroidPhone
        return AndroidPhone(cfg.id, cfg.bundle_id)
    if cfg.platform == "ios-sim":
        from .simulator import SimulatorPhone
        return SimulatorPhone(cfg.id, cfg.bundle_id)
    raise ValueError(f"unknown phone platform {cfg.platform!r}")
