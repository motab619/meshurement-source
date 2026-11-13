// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Without a delegate iOS drops local notifications while the app is in
    // the foreground; FlutterAppDelegate forwards willPresent to the
    // flutter_local_notifications plugin, which then shows the
    // out-of-range / radio-lost banner with sound while the app is open.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityBridge") {
      LiveActivityBridge.register(with: registrar)
    }
    // Launch arguments (e.g. -MeshDemo from the screenshot UI tests).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppInfo") {
      let channel = FlutterMethodChannel(
        name: "mesh_analyzer/app", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        if call.method == "launchArguments" {
          result(ProcessInfo.processInfo.arguments)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      appChannel = channel
    }
  }
}
