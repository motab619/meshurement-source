// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import ActivityKit
import Flutter
import Foundation
import UIKit

/// Method channel `mesh_analyzer/live_activity`: start / update / end the
/// session Live Activity (Dynamic Island + lock screen).
final class LiveActivityBridge: NSObject {
  /// The running Activity<MeshActivityAttributes>, typed Any so the class
  /// itself doesn't need iOS 16.2. `start` returns "ok", "disabled" (Live
  /// Activities turned off for the app) or "error: <reason>".
  private var current: Any?

  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "mesh_analyzer/live_activity",
      binaryMessenger: registrar.messenger()
    )
    let instance = LiveActivityBridge()
    channel.setMethodCallHandler(instance.handle)
    // The handler closure retains the instance; keep the channel alive.
    _retained.append(channel)
  }

  private static var _retained: [FlutterMethodChannel] = []

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    // Live Activities exist on iPhone only: an iPad (or the app on a Mac)
    // says "not here" so the app shows no Live Activity line at all.
    if call.method == "supported" {
      if #available(iOS 16.2, *) {
        result(UIDevice.current.userInterfaceIdiom == .phone)
      } else {
        result(false)
      }
      return
    }
    guard #available(iOS 16.2, *) else {
      result("unsupported")
      return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start":
      result(start(args))
    case "update":
      update(args)
      result(true)
    case "end":
      end()
      result(true)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  @available(iOS 16.2, *)
  private func start(_ args: [String: Any]) -> String {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      print("LiveActivityBridge: Live Activities are disabled for this app")
      return "disabled"
    }
    // ActivityKit only starts an activity from a foreground app ("Target is
    // not foreground"): a session resumed while launching in the
    // background, or picked up before the window is active, waits for the
    // next resume (field, 2026-10-27).
    guard UIApplication.shared.applicationState == .active else {
      print("LiveActivityBridge: app not active; start deferred")
      return "background"
    }
    // Only one session at a time; clear leftovers (e.g. after a crash).
    for activity in Activity<MeshActivityAttributes>.activities {
      Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }
    let attributes = MeshActivityAttributes(
      sessionName: args["sessionName"] as? String ?? "Session",
      baseName: args["baseName"] as? String ?? "Base",
      preset: args["preset"] as? String ?? "",
      probeLabel: args["probeLabel"] as? String
    )
    do {
      current = try Activity.request(
        attributes: attributes,
        content: ActivityContent(state: Self.state(from: args), staleDate: nil),
        pushType: nil
      )
      print("LiveActivityBridge: started")
      return "ok"
    } catch {
      print("LiveActivityBridge: start failed: \(error)")
      if error.localizedDescription.lowercased().contains("foreground") {
        return "background"
      }
      return "error: \(error.localizedDescription)"
    }
  }

  @available(iOS 16.2, *)
  private func update(_ args: [String: Any]) {
    guard let activity = current as? Activity<MeshActivityAttributes> else { return }
    let content = ActivityContent(
      state: Self.state(from: args),
      // Greyed out if the app stops updating for this long.
      staleDate: Date().addingTimeInterval(10 * 60)
    )
    Task { await activity.update(content) }
  }

  @available(iOS 16.2, *)
  private func end() {
    let activity = current as? Activity<MeshActivityAttributes>
    current = nil
    Task {
      await activity?.end(nil, dismissalPolicy: .immediate)
      for other in Activity<MeshActivityAttributes>.activities {
        await other.end(nil, dismissalPolicy: .immediate)
      }
    }
  }

  @available(iOS 16.2, *)
  private static func state(from args: [String: Any]) -> MeshActivityAttributes.ContentState {
    let lastHeardMs = args["lastHeardMs"] as? NSNumber
    return MeshActivityAttributes.ContentState(
      link: args["link"] as? String ?? "disconnected",
      range: args["range"] as? String ?? "unknown",
      snr: (args["snr"] as? NSNumber)?.doubleValue,
      rssi: (args["rssi"] as? NSNumber)?.intValue,
      margin: (args["margin"] as? NSNumber)?.doubleValue,
      lastHeard: lastHeardMs.map { Date(timeIntervalSince1970: $0.doubleValue / 1000) },
      packets: (args["packets"] as? NSNumber)?.intValue ?? 0,
      pingsOk: (args["pingsOk"] as? NSNumber)?.intValue ?? 0,
      pingsTotal: (args["pingsTotal"] as? NSNumber)?.intValue ?? 0
    )
  }
}
