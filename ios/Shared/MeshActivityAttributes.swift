// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import ActivityKit
import Foundation

/// Live Activity data for a recording session. Shared by the Runner app
/// (which starts/updates it) and the MeshActivity widget extension (which
/// draws it in the Dynamic Island and on the lock screen).
@available(iOS 16.1, *)
struct MeshActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    /// "connected" | "reconnecting" | "disconnected"
    var link: String
    /// "in" | "out" | "unknown" | "radioLost"
    var range: String
    var snr: Double?
    var rssi: Int?
    /// Link margin (dB above the preset's decode limit, RSSI-based when
    /// SNR has stopped rising; Dart `linkMarginDb`). Optional: states from
    /// older app builds have none and the widget falls back to SNR.
    var margin: Double? = nil
    /// When a packet from the base was last received.
    var lastHeard: Date?
    var packets: Int
    var pingsOk: Int
    var pingsTotal: Int
  }

  var sessionName: String
  var baseName: String
  /// The range setting's display name ("Medium Fast"), never a raw id.
  var preset: String
  /// "Pings" (Meshtastic) or "Link checks" (MeshCore); nil from older
  /// app builds.
  var probeLabel: String?
}
