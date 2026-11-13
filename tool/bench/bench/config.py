# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""bench.toml: which radios and phones are on the bench."""

from __future__ import annotations

import tomllib
from dataclasses import dataclass, field
from pathlib import Path

from . import ports

DEFAULT_PORT = 8765


@dataclass
class RadioConfig:
    name: str
    serial: str
    board: str
    protocol: str
    role: str
    firmware: str | None = None   # version last flashed by `bench flash` (flashed.json)

    def port(self) -> str:
        """The /dev/cu.* path for this radio right now (raises if unplugged)."""
        for p in ports.list_ports():
            if p.serial_number == self.serial:
                return p.device
        raise FileNotFoundError(
            f"radio '{self.name}' (serial {self.serial}) is not plugged in; "
            "`bench ports` lists what is")


# The app's id per platform: the iOS bundle id and the Android application
# id differ (CLAUDE.md: the iOS id is never reused on Android).
APP_IDS = {"ios": "com.andybrunker.meshAnalyzer", "android": "com.plateaunerd.meshurement"}


@dataclass
class PhoneConfig:
    """One `[phone]` / `[phones.<name>]` table.

    `platform`: ios (devicectl), android (adb) or ios-sim (the iOS
    simulator: T1, no radios, bench-rig §8). `id`: UDID / adb serial /
    simulator name or UDID. `demo` adds `-MeshDemo` to the launch (the
    demo's pretend radio and database); on by default for the simulator.
    """
    platform: str
    id: str
    bundle_id: str = ""   # default per platform (APP_IDS)
    name: str = "phone"
    demo: bool = False
    demo_screen: str | None = None
    port: int = DEFAULT_PORT

    def __post_init__(self) -> None:
        if not self.bundle_id:
            self.bundle_id = APP_IDS.get(self.platform, APP_IDS["ios"])

    @property
    def simulator(self) -> bool:
        return self.platform == "ios-sim"

    @property
    def tier(self) -> str:
        """Bench tier of a run on this phone (bench-rig §1)."""
        return "T1" if self.simulator else "T2"

    def launch_args(self) -> list[str]:
        args = ["-MeshBench"]
        if self.port != DEFAULT_PORT:
            args += ["-benchPort", str(self.port)]
        if self.demo:
            args.append("-MeshDemo")
            if self.demo_screen:
                args += ["-demoScreen", self.demo_screen]
        return args


@dataclass
class MatrixConfig:
    """`[matrix]`: firmware combos for `bench matrix` (README §6).

    `combos` is a list of inline tables, one per cell: `<radio name> =
    "<protocol> <version>"` for every radio the cell pins (versions as
    `bench flash` takes them: `2.8.1`, `2.8.1.8e6a88d`, `1.18.0`, `latest`,
    `pre`), plus an optional `scenarios` list overriding the matrix-wide one.
    """
    scenarios: list[str] = field(default_factory=list)
    combos: list[dict[str, object]] = field(default_factory=list)


@dataclass
class BenchConfig:
    path: Path
    reports_dir: Path
    firmware_cache: Path
    region: str = "US"   # LoRa region written to a freshly flashed Meshtastic radio
    radios: dict[str, RadioConfig] = field(default_factory=dict)
    # Every phone: `[phone]` under the key "phone", `[phones.<name>]` under
    # its name. `phone` is the default one (`[phone]`, else the first listed).
    phones: dict[str, PhoneConfig] = field(default_factory=dict)
    phone: PhoneConfig | None = None
    matrix: MatrixConfig | None = None

    def radio(self, name: str) -> RadioConfig:
        try:
            return self.radios[name]
        except KeyError:
            raise KeyError(f"no [radios.{name}] in {self.path}") from None

    def phone_named(self, name: str | None) -> PhoneConfig:
        """`--phone <name>`: a `[phones.<name>]` table, or its platform when
        exactly one phone runs it; None picks the default."""
        if name is None:
            p = self.phone
            if p is None:
                raise KeyError(f"no [phone] or [phones.*] table in {self.path}")
            return p
        if name in self.phones:
            return self.phones[name]
        same = [p for p in self.phones.values() if p.platform == name]
        if len(same) == 1:
            return same[0]
        have = ", ".join(self.phones) or "none"
        raise KeyError(f"no [phones.{name}] (or platform {name!r}) in {self.path}; have {have}")


def _phone(name: str, p: dict) -> PhoneConfig:
    platform = p["platform"]
    if platform not in ("ios", "android", "ios-sim"):
        raise ValueError(f"[phones.{name}] platform {platform!r}: ios | android | ios-sim")
    return PhoneConfig(
        platform=platform, id=str(p["id"]),
        bundle_id=p.get("bundle_id", ""), name=name,
        demo=bool(p.get("demo", platform == "ios-sim")),
        demo_screen=p.get("demo_screen"),
        port=int(p.get("port", DEFAULT_PORT)))


def load(path: Path | None = None) -> BenchConfig:
    path = path or Path(__file__).resolve().parents[1] / "bench.toml"
    if not path.exists():
        raise FileNotFoundError(
            f"{path} not found; copy bench.toml.example and fill it in")
    with path.open("rb") as f:
        raw = tomllib.load(f)
    bench = raw.get("bench", {})
    cfg = BenchConfig(
        path=path,
        reports_dir=Path(bench.get("reports_dir", "~/mesh-bench/reports")).expanduser(),
        firmware_cache=Path(bench.get("firmware_cache", "~/mesh-bench/firmware")).expanduser(),
        region=bench.get("region", "US"),
    )
    # What `bench flash` last put on each radio wins over bench.toml's `protocol`.
    flashed_path = cfg.firmware_cache / "flashed.json"
    flashed: dict = {}
    if flashed_path.exists():
        import json
        flashed = json.loads(flashed_path.read_text())
    for name, r in raw.get("radios", {}).items():
        f = flashed.get(str(r["serial"]), {})
        cfg.radios[name] = RadioConfig(
            name=name, serial=str(r["serial"]), board=r["board"],
            protocol=f.get("protocol", r["protocol"]), role=r.get("role", name),
            firmware=f.get("version"))
    tables: dict[str, dict] = {}
    if "phone" in raw:
        cfg.phones["phone"] = _phone("phone", raw["phone"])
    for name, p in raw.get("phones", {}).items():
        cfg.phones[name] = _phone(name, p)
    if cfg.phones:
        cfg.phone = cfg.phones.get("phone") or next(iter(cfg.phones.values()))
    if "matrix" in raw:
        m = raw["matrix"]
        cfg.matrix = MatrixConfig(scenarios=list(m.get("scenarios", [])),
                                  combos=[dict(c) for c in m.get("combos", [])])
    return cfg
