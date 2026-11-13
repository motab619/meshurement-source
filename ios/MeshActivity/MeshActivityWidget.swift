// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MeshActivityBundle: WidgetBundle {
  var body: some Widget {
    MeshLiveActivity()
  }
}

struct MeshLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: MeshActivityAttributes.self) { context in
      LockScreenView(context: context)
        .activityBackgroundTint(Color.black.opacity(0.75))
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let s = context.state
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 2) {
            Text("SNR").font(.caption2).foregroundStyle(.secondary)
            Text(snrText(s.snr)).font(.title3.monospacedDigit().bold())
              .foregroundStyle(signalColor(s))
            if let rssi = s.rssi {
              Text("\(rssi) dBm").font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
            }
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text(context.attributes.probeLabel ?? "Pings").font(.caption2).foregroundStyle(.secondary)
            Text(s.pingsTotal > 0 ? "\(s.pingsOk)/\(s.pingsTotal)" : "–")
              .font(.title3.monospacedDigit().bold())
            Text("\(s.packets) pkts").font(.caption2.monospacedDigit())
              .foregroundStyle(.secondary)
          }
        }
        DynamicIslandExpandedRegion(.center) {
          HStack(spacing: 6) {
            Image(systemName: rangeIcon(s))
            Text(rangeText(s)).lineLimit(1)
          }
          .font(.subheadline.bold())
          .foregroundStyle(rangeColor(s))
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack {
            Text(context.attributes.baseName).lineLimit(1)
            Spacer()
            LastHeardText(date: s.lastHeard)
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
      } compactLeading: {
        Image(systemName: rangeIcon(s)).foregroundStyle(rangeColor(s))
      } compactTrailing: {
        Text(snrText(s.snr)).monospacedDigit().foregroundStyle(signalColor(s))
      } minimal: {
        Image(systemName: rangeIcon(s)).foregroundStyle(rangeColor(s))
      }
    }
  }
}

struct LockScreenView: View {
  let context: ActivityViewContext<MeshActivityAttributes>

  var body: some View {
    let s = context.state
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Image(systemName: rangeIcon(s))
        Text(rangeText(s)).bold()
        Spacer()
        Text(context.attributes.preset).font(.caption).foregroundStyle(.secondary)
      }
      .foregroundStyle(rangeColor(s))

      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading) {
          Text("SNR").font(.caption2).foregroundStyle(.secondary)
          Text(snrText(s.snr)).font(.title2.monospacedDigit().bold())
            .foregroundStyle(signalColor(s))
        }
        Spacer()
        VStack(alignment: .leading) {
          Text("RSSI").font(.caption2).foregroundStyle(.secondary)
          Text(s.rssi.map { "\($0)" } ?? "–").font(.title2.monospacedDigit())
        }
        Spacer()
        VStack(alignment: .leading) {
          Text(context.attributes.probeLabel ?? "Pings").font(.caption2).foregroundStyle(.secondary)
          Text(s.pingsTotal > 0 ? "\(s.pingsOk)/\(s.pingsTotal)" : "–")
            .font(.title2.monospacedDigit())
        }
      }
      .foregroundStyle(.white)

      HStack {
        Text("\(context.attributes.sessionName) · \(context.attributes.baseName)")
          .lineLimit(1)
        Spacer()
        LastHeardText(date: s.lastHeard)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding()
  }
}

/// "heard 2 min ago", updated by the system without app updates.
struct LastHeardText: View {
  let date: Date?

  var body: some View {
    if let date {
      HStack(spacing: 3) {
        Text("heard")
        Text(date, style: .relative)
        Text("ago")
      }
      .monospacedDigit()
    } else {
      Text("base not heard yet")
    }
  }
}

private func snrText(_ snr: Double?) -> String {
  guard let snr else { return "–" }
  return String(format: "%.1f", snr)
}

/// Colour by the app's link-margin bands (Dart `MarginBand`: Strong 20+,
/// Good 10 to 20, Weak 0 to 10, Below limit under 0). States from app
/// builds without `margin` fall back to rough absolute SNR steps.
private func signalColor(_ s: MeshActivityAttributes.ContentState) -> Color {
  if let m = s.margin {
    if m >= 20 { return .green }
    if m >= 10 { return .yellow }
    if m >= 0 { return .orange }
    return .red
  }
  guard let snr = s.snr else { return .gray }
  if snr >= 5 { return .green }
  if snr >= -5 { return .yellow }
  if snr >= -12 { return .orange }
  return .red
}

private func rangeText(_ s: MeshActivityAttributes.ContentState) -> String {
  if s.link == "reconnecting" { return "Reconnecting to node" }
  if s.link != "connected" { return "Bluetooth link lost" }
  switch s.range {
  case "in": return "Base in range"
  case "out": return "Base out of range"
  case "radioLost": return "Bluetooth link lost"
  default: return "Waiting for base"
  }
}

private func rangeIcon(_ s: MeshActivityAttributes.ContentState) -> String {
  if s.link != "connected" || s.range == "radioLost" {
    return "antenna.radiowaves.left.and.right.slash"
  }
  return s.range == "out"
    ? "antenna.radiowaves.left.and.right.slash"
    : "antenna.radiowaves.left.and.right"
}

private func rangeColor(_ s: MeshActivityAttributes.ContentState) -> Color {
  if s.link != "connected" || s.range == "radioLost" { return .orange }
  switch s.range {
  case "in": return .green
  case "out": return .red
  default: return .gray
  }
}
