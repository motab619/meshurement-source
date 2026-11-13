# Meshurement - maps LoRa mesh radio coverage.
# Copyright (C) 2026 Andy Brunker (Plateau Nerd)
# SPDX-License-Identifier: GPL-3.0-or-later
# Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.
"""`bench` command. Run from tool/bench with `uv run bench ...`.

  bench ports                     what is plugged in (no side effects)
  bench snapshot <radio> [--json] read a Meshtastic radio's settings over USB
  bench check <radio>             snapshot + Radio Setup checks for its role
  bench reboot <radio>            reboot (brings a Heltec's Bluetooth back)
  bench latest [--json] [--max-age-h N] [--commit SHA]
                                  the latest report, judged as the release gate
                                  does (fastlane bench_check); exit 1 on a problem
  bench prepare                   bench radios: Bluetooth NO_PIN (no pairing prompts)
  bench firmware <protocol>       list downloadable firmware releases
  bench flash <radio> <protocol> <version>  download (cached) + flash + prepare
  bench install <app>             install a bench build (release, BENCH=true)
  bench launch                    launch it with -MeshBench and print /state
  bench run <scenario|all> [-o k=v]  run scenarios, write a report
  bench matrix [--dry-run] [--resume] [--reflash] [--unattended]
                                  firmware matrix from [matrix] in bench.toml:
                                  flash what differs, run the scenarios per
                                  combo, one matrix report
  bench ui [report.json]          replay a run report in the live view

`--ui` on run and matrix opens a live view in the browser: the bench drawn
(Mac, cables, phone, radios), animated as the run talks to them, and the
checklist ticking off (bench/live.py, page in bench/ui/index.html).

Reading a Meshtastic radio over USB turns an ESP32's (Heltec) Bluetooth off
until a reboot: every command that reads one ends with that reboot
(`meshtastic.serial_session`); `--no-reboot` on snapshot/check skips it.

`--phone NAME` (install, launch, run) picks a `[phones.NAME]` table; the
default is `[phone]`. A `platform = "ios-sim"` phone is the iOS simulator
(T1: no radios, demo mode; scenario `smoke`).

`install`, `launch` and `run` take `--phone <name>`: a `[phones.<name>]`
table in bench.toml (or just its platform, `--phone android`); the default
is the first phone listed (a lone `[phone]` table counts as the first).

Build the app with `flutter build ios --release --dart-define=BENCH=true`
(debug builds can't be launched outside `flutter run` on iOS 14+); for the
simulator `flutter build ios --simulator --debug --dart-define=BENCH=true`,
`flutter build apk --release --dart-define=BENCH=true` for Android.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

from . import config, live, ports, report


def cmd_ports(_: argparse.Namespace) -> int:
    items = ports.list_ports()
    print(ports.format_table(items))
    for p in items:
        if p.in_bootloader:
            print(f"\nnote: {p.device} is in the UF2 bootloader (copy a .uf2 to its "
                  "volume, or press reset once, before using it)")
    return 0


def _log(s: str) -> None:
    print(f"[{time.strftime('%H:%M:%S')}] {s}", flush=True)
    live.log(s)


def _start_ui(a: argparse.Namespace) -> None:
    """`--ui`: serve the live page and give it a moment to open."""
    if not getattr(a, "ui", False):
        return
    try:
        url = live.serve(a.ui_port, open_browser=not a.no_browser)
    except OSError as e:
        if e.errno != 48:  # EADDRINUSE on macOS
            raise
        sys.exit(f"port {a.ui_port} is taken: a finished run's live view stays up until "
                 f"Ctrl-C (`lsof -nP -iTCP:{a.ui_port}`), or pass --ui-port")
    print(f"live view: {url}", flush=True)
    live.wait_for_page(timeout=8)


def _linger_ui(a: argparse.Namespace) -> None:
    """Keep the page's server up after the run so the result can be read."""
    if not getattr(a, "ui", False) or not live.active():
        return
    print("live view stays up: Ctrl-C to quit", flush=True)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass


def _snapshot(name: str, *, reboot: bool = True):
    from .radios import meshtastic as mt
    cfg = config.load()
    r = cfg.radio(name)
    if r.protocol != "meshtastic":
        sys.exit(f"{name} is {r.protocol}; only Meshtastic read-back exists yet")
    if reboot:
        return r, mt.read_then_reboot(r, lambda s: print(s, file=sys.stderr))
    port = r.port()
    if mt.bluetooth_off_after_serial(r):
        print(f"reading {name} on {port}: its Bluetooth is off until `bench reboot {name}`",
              file=sys.stderr)
    return r, mt.snapshot(port)


def cmd_snapshot(a: argparse.Namespace) -> int:
    _, snap = _snapshot(a.radio, reboot=not a.no_reboot)
    if a.json:
        print(json.dumps(snap.to_dict(), indent=2))
    else:
        print(f"{snap.node_id} {snap.owner.get('longName')!r}/{snap.owner.get('shortName')!r} "
              f"{snap.hw_model} fw {snap.firmware_version or '?'}")
        for c in snap.channels:
            if c["enabled"]:
                print(f"  ch{c['index']} {c['role']:<9} {c['name']!r} psk {len(c['psk']) // 2} B")
        print(f"  lora: preset {snap.lora.get('modem_preset')} region {snap.lora.get('region')} "
              f"slot {snap.lora.get('channel_num', 0)} tx {snap.lora.get('tx_power')} dBm "
              f"hops {snap.lora.get('hop_limit')}")
        print(f"  device: role {snap.device.get('role', 'CLIENT')} "
              f"rebroadcast {snap.device.get('rebroadcast_mode', 'ALL')}")
        print(f"  telemetry: device_telemetry_enabled={snap.telemetry.get('device_telemetry_enabled', False)} "
              f"interval {snap.telemetry.get('device_update_interval')}")
        print(f"  range_test: {snap.range_test or '{}'}  excluded: {snap.excluded_modules}")
        print(f"  admin keys: {len([k for k in snap.security.get('admin_key', []) if k])}  "
              f"bluetooth: {snap.bluetooth.get('mode', 'RANDOM_PIN')}")
        print(f"  public channel: {snap.on_public_channel}")
    return 0


def cmd_check(a: argparse.Namespace) -> int:
    from .radios import meshtastic as mt
    r, snap = _snapshot(a.radio, reboot=not a.no_reboot)
    checks = mt.check_meshtest_setup(snap, role=r.role, psk_hex=a.psk, preset=a.preset)
    bad = 0
    for c in checks:
        mark = "ok  " if c.ok else "FAIL"
        bad += not c.ok
        print(f"{mark} {c.name}" + (f"  [{c.detail}]" if c.detail and not c.ok else ""))
    return 1 if bad else 0


def cmd_reboot(a: argparse.Namespace) -> int:
    from .radios import meshtastic as mt
    cfg = config.load()
    mt.reboot(cfg.radio(a.radio).port())
    return 0


def cmd_latest(a: argparse.Namespace) -> int:
    """The gate's view of the newest report. `--json` prints one object
    ({ok, problems, summary, ...}; fastlane `bench_check` reads it and does no
    parsing of its own). Exit 0 only when there is no problem."""
    try:
        cfg = config.load()
        r = report.latest(cfg.reports_dir)
        where = str(cfg.reports_dir)
    except FileNotFoundError as e:
        r, where = None, ""
        res = {"ok": False, "found": False, "problems": [str(e)], "summary": "no bench.toml"}
    else:
        res = report.evaluate(r, max_age_h=a.max_age_h, commit=a.commit, where=where)
    if a.json:
        print(json.dumps(res, indent=2))
    else:
        print(res["summary"])
        for p in res["problems"]:
            print(f"problem: {p}")
    return 0 if res["ok"] else 1


def _phone_cfg(cfg, name: str | None):
    try:
        return cfg.phone_named(name)
    except KeyError as e:
        sys.exit(str(e))


def _phone(cfg, name: str | None = None):
    from . import phones
    return phones.for_config(_phone_cfg(cfg, name))


def cmd_prepare(a: argparse.Namespace) -> int:
    from .radios import meshtastic as mt
    cfg = config.load()
    bad = 0
    for name, r in cfg.radios.items():
        if r.protocol != "meshtastic" or (a.radio and name not in a.radio):
            continue
        with mt.serial_session(r, _log) as port:
            print(f"{name}: region {cfg.region}, bluetooth {a.mode} on {port} (reboots)...")
            changed = mt.prepare_fresh(port, region=cfg.region, bluetooth_mode=a.mode)
            snap = mt.snapshot(port)
        ok = snap.lora.get("region") == cfg.region and snap.bluetooth.get("mode") == a.mode
        bad += not ok
        print(f"  changed {changed or 'nothing'}; now region {snap.lora.get('region')} "
              f"bluetooth {snap.bluetooth.get('mode')} {'ok' if ok else 'FAIL'}")
    return 1 if bad else 0


def cmd_firmware(a: argparse.Namespace) -> int:
    from . import firmware
    cfg = config.load()
    for r in firmware.releases(a.protocol, limit=a.limit):
        cached = (cfg.firmware_cache / r.protocol / (r.tag if r.protocol == "meshcore" else r.version))
        mark = "pre " if r.prerelease else "    "
        print(f"{mark}{r.version:<18} {r.published}  {'cached' if cached.exists() else ''}")
    return 0


def cmd_flash(a: argparse.Namespace) -> int:
    from . import provision
    cfg = config.load()
    radio = cfg.radio(a.radio)
    try:
        provision.flash_radio(cfg, radio, a.protocol, a.version, _log, boot_wait=a.boot_wait,
                              prepare=not a.no_prepare, dry_run=a.dry_run)
    except provision.PrepareError as e:
        _log(f"FAIL: {e}")
        return 1
    return 0


def cmd_install(a: argparse.Namespace) -> int:
    cfg = config.load()
    phone = _phone(cfg, a.phone)
    ok, why = phone.ready()
    if not ok:
        sys.exit(f"phone not ready: {why}")
    print(f"installing on {why}...")
    phone.install(Path(a.app))
    print("installed")
    return 0


def cmd_launch(a: argparse.Namespace) -> int:
    from .app import AppLink, Forward
    cfg = config.load()
    pcfg = _phone_cfg(cfg, a.phone)
    phone = _phone(cfg, a.phone)
    ok, why = phone.ready()
    if not ok:
        sys.exit(f"phone not ready: {why}")
    phone.launch(*pcfg.launch_args())
    with Forward(pcfg.platform, pcfg.id, pcfg.port):
        link = AppLink(port=pcfg.port, log=print if a.verbose else None)
        st = link.wait_up(timeout=a.timeout)
        print(json.dumps(st, indent=2))
    return 0


def cmd_run(a: argparse.Namespace) -> int:
    from . import runner, scenarios
    cfg = config.load()
    try:
        names = runner.check_scenarios(a.scenario)
    except KeyError as e:
        sys.exit(str(e.args[0]))
    if a.scenario != ["all"] and scenarios.ordered(names) != names:
        names = scenarios.ordered(names)
        print(f"running in bench order: {' '.join(names)}")
    for n in names:
        for dep in scenarios.REQUIRES.get(n, ()):
            if dep not in names[:names.index(n)]:
                _log(f"note: {n} needs {dep} to have run on this phone + radios "
                     f"(not in this run; using what the app remembers)")
    _start_ui(a)
    try:
        rep = runner.run_scenarios(cfg, names, runner.parse_options(a.option), _log,
                                   launch=not a.no_launch, verbose=a.verbose,
                                   phone=a.phone)
    except runner.PhoneNotReady as e:
        live.emit("run_end", passed=False, report="", error=str(e))
        if not getattr(a, "ui", False):
            sys.exit(str(e))
        print(str(e))
        _linger_ui(a)
        return 1
    print(f"\nreport: {rep.written}\n{'PASS' if rep.passed else 'FAIL'}")
    _linger_ui(a)
    return 0 if rep.passed else 1


def cmd_ui(a: argparse.Namespace) -> int:
    """Replay a finished report on the live page (no hardware needed)."""
    cfg = config.load()
    path = Path(a.report) if a.report else cfg.reports_dir / "latest.json"
    if not path.exists():
        sys.exit(f"no report at {path}")
    rep = json.loads(path.read_text())
    if not rep.get("scenarios"):
        sys.exit(f"{path} has no scenarios (a matrix report? pass a run report)")
    def play() -> None:
        live.play(rep, total_s=a.seconds)
    url = live.serve(a.ui_port, open_browser=not a.no_browser, on_replay=play)
    print(f"replaying {path.name} at {url} (Ctrl-C to quit)", flush=True)
    live.wait_for_page(timeout=60)
    time.sleep(1.0)
    play()
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        pass
    return 0


def cmd_matrix(a: argparse.Namespace) -> int:
    from . import matrix, runner
    cfg = config.load()
    try:
        combos = matrix.combos_from(cfg)
    except ValueError as e:
        sys.exit(str(e))
    only = a.combo or None
    resolver = matrix.Resolver(cfg.firmware_cache)
    if a.dry_run:
        previous = report.passed_rows(report.latest_matrix(cfg.reports_dir)) if a.resume else {}
        plans = matrix.plan(cfg, [c for c in combos if not only or c.index in only], resolver,
                            reflash=a.reflash, passed_before=previous)
        print(matrix.format_plan(plans, resolver))
        n_flash = sum(len(p.flashes) for p in plans)
        n_forget = sum(p.needs_operator for p in plans)
        print(f"\n{len(plans)} combo(s), {n_flash} flash(es), {n_forget} with an operator pause"
              + (" (blocked with --unattended)" if a.unattended and n_forget else ""))
        return 0
    if cfg.phone is None:
        sys.exit(f"no [phone] in {cfg.path}")
    _start_ui(a)
    live.emit("matrix_start", combos=[{"index": c.index, "label": c.label}
                                      for c in combos if not only or c.index in only],
              radios={n: {"board": r.board, "protocol": r.protocol, "role": r.role,
                          "firmware": r.firmware} for n, r in cfg.radios.items()})
    rep = matrix.run_matrix(cfg, combos, runner.parse_options(a.option), _log,
                            reflash=a.reflash, resume=a.resume, unattended=a.unattended,
                            only=only, boot_wait=a.boot_wait, verbose=a.verbose,
                            resolver=resolver)
    print(f"\nmatrix report: {cfg.reports_dir / (rep.stem + '.md')}")
    for r in rep.rows:
        print(f"  {r.label}: {r.status}" + (f" ({r.note})" if r.note else ""))
    print("PASS" if rep.passed else "FAIL")
    live.emit("matrix_end", passed=rep.passed)
    _linger_ui(a)
    return 0 if rep.passed else 1


def _ui_args(s: argparse.ArgumentParser, *, flag: bool = True) -> None:
    if flag:
        s.add_argument("--ui", action="store_true", help="live view in the browser")
    s.add_argument("--ui-port", type=int, default=live.DEFAULT_PORT, help="port of the live view")
    s.add_argument("--no-browser", action="store_true", help="serve the live view, don't open it")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="bench", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("ports").set_defaults(fn=cmd_ports)
    s = sub.add_parser("snapshot"); s.add_argument("radio"); s.add_argument("--json", action="store_true")
    s.add_argument("--no-reboot", action="store_true", help="leave an ESP32's Bluetooth off afterwards")
    s.set_defaults(fn=cmd_snapshot)
    s = sub.add_parser("check"); s.add_argument("radio")
    s.add_argument("--no-reboot", action="store_true", help="leave an ESP32's Bluetooth off afterwards")
    s.add_argument("--psk", help="expected 32-byte key, hex (the phone's test_channel_psk)")
    s.add_argument("--preset", help="expected modem preset, e.g. MEDIUM_FAST")
    s.set_defaults(fn=cmd_check)
    s = sub.add_parser("reboot"); s.add_argument("radio"); s.set_defaults(fn=cmd_reboot)
    s = sub.add_parser("latest"); s.add_argument("--json", action="store_true", help="one JSON object for the gate")
    s.add_argument("--max-age-h", type=float, default=None, help="a report older than this is a problem")
    s.add_argument("--commit", default=None, help="a report for another commit is a problem")
    s.set_defaults(fn=cmd_latest)
    s = sub.add_parser("prepare"); s.add_argument("radio", nargs="*", help="default: every Meshtastic radio")
    s.add_argument("--mode", default="NO_PIN"); s.set_defaults(fn=cmd_prepare)
    s = sub.add_parser("firmware"); s.add_argument("protocol", choices=("meshtastic", "meshcore"))
    s.add_argument("--limit", type=int, default=15); s.set_defaults(fn=cmd_firmware)
    s = sub.add_parser("flash"); s.add_argument("radio"); s.add_argument("protocol", choices=("meshtastic", "meshcore"))
    s.add_argument("version", help="2.8.1 / 2.8.1.8e6a88d / 1.18.0 / latest / pre")
    s.add_argument("--dry-run", action="store_true", help="download and show, don't flash")
    s.add_argument("--no-prepare", action="store_true", help="skip region + NO_PIN after a Meshtastic flash")
    s.add_argument("--boot-wait", type=int, default=30, help="seconds before the first serial read")
    s.set_defaults(fn=cmd_flash)
    phone_help = "which [phones.<name>] of bench.toml (or its platform); default: the first"
    s = sub.add_parser("install"); s.add_argument("app", help="Runner.app or .apk")
    s.add_argument("--phone", help=phone_help); s.set_defaults(fn=cmd_install)
    s = sub.add_parser("launch"); s.add_argument("-v", "--verbose", action="store_true")
    s.add_argument("--phone", help=phone_help)
    s.add_argument("--timeout", type=float, default=90); s.set_defaults(fn=cmd_launch)
    s = sub.add_parser("run"); s.add_argument("scenario", nargs="+")
    s.add_argument("--phone", help=phone_help)
    s.add_argument("-o", "--option", action="append", help="k=v scenario option")
    s.add_argument("-v", "--verbose", action="store_true", help="print every app event")
    s.add_argument("--no-launch", action="store_true", help="the app is already running in bench mode")
    _ui_args(s)
    s.set_defaults(fn=cmd_run)
    s = sub.add_parser("matrix", help="firmware matrix from [matrix] in bench.toml")
    s.add_argument("--dry-run", action="store_true",
                   help="print the plan: what would be flashed, what is reused, how versions resolve")
    s.add_argument("--resume", action="store_true",
                   help="skip combos matrix-latest.json already passed (carried into the new report)")
    s.add_argument("--reflash", action="store_true",
                   help="flash every radio even when it is already on the combo's firmware")
    s.add_argument("--unattended", action="store_true",
                   help="never wait for the operator: a combo whose ESP32 flash dropped the phone's "
                        "bond is marked blocked instead")
    s.add_argument("--combo", type=int, action="append", metavar="N",
                   help="only combo N (1-based in [matrix].combos); repeatable")
    s.add_argument("-o", "--option", action="append", help="k=v scenario option")
    s.add_argument("--boot-wait", type=int, default=30, help="seconds before the first serial read after a flash")
    s.add_argument("-v", "--verbose", action="store_true", help="print every app event")
    _ui_args(s)
    s.set_defaults(fn=cmd_matrix)
    s = sub.add_parser("ui", help="replay a run report in the live view (no hardware)")
    s.add_argument("report", nargs="?", help="a report .json (default: latest.json)")
    s.add_argument("--seconds", type=float, default=45, help="how long the replay takes")
    _ui_args(s, flag=False)
    s.set_defaults(fn=cmd_ui)
    a = ap.parse_args(argv)
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
