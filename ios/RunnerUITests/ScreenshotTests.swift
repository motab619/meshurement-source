// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import XCTest

/// App screenshots for fastlane snapshot (`cd ios && fastlane snapshot`).
///
/// Each screen is a fresh launch in demo mode (`-MeshDemo`): a pretend
/// connected radio and the demo site's sessions (La Quinta Cove by default,
/// readings modelled from real terrain; `-demoSite polo` for the old
/// Empire Polo walk).
/// `-demoScreen` opens the app straight to that screen, so no taps are
/// needed. Nothing touches Bluetooth or real data.
@MainActor
final class ScreenshotTests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  private func capture(_ screen: String, as name: String, wait: UInt32 = 18) {
    let app = XCUIApplication()
    setupSnapshot(app)
    app.launchArguments += ["-MeshDemo", "-demoScreen", screen]
    app.launchEnvironment["MESH_DEMO"] = screen
    app.launch()
    // Flutter never reports "idle" to XCTest; give the demo data and map
    // tiles time to load instead.
    sleep(wait)
    snapshot(name, timeWaitingForIdle: 0)
    app.terminate()
  }

  func testScreenshots() {
    capture("map", as: "01-live-map")
    capture("charts", as: "02-live-charts")
    capture("coverage", as: "03-signal-map", wait: 45)
    capture("pings", as: "04-pings-map", wait: 75)
    capture("radio", as: "05-node-setup", wait: 8)
    capture("report-compare", as: "06-field-report", wait: 20)
    // Last: it leaves the map on Terrain for later launches.
    capture("terrain", as: "07-terrain-map", wait: 60)
  }
}
