// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:shared_preferences/shared_preferences.dart';

/// App-wide constants
class AppConstants {
  AppConstants._();

  /// Endpoint of the AI session-analysis backend (tool/ai-analysis, an AWS
  /// Lambda Function URL). Null = feature not available: the UI hides it and
  /// the app makes no such request. Fill in after deploying.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const String? aiAnalysisUrl =
      'https://3bcigbfgfzlr356zaubtr3lqju0rfkll.lambda-url.us-west-2.on.aws/';

  /// Address for "Report a problem with this analysis". Null = open
  /// [supportUrl] (About) instead and copy the details to the clipboard.
  // ignore: unnecessary_nullable_for_final_variable_declarations
  static const String? supportEmail = 'support@meshurement.com';

  // Meshtastic port numbers
  static const int portTextMessage = 1;
  static const int portPosition = 3;
  static const int portNodeInfo = 4;
  static const int portRouting = 5;
  static const int portAdmin = 6;
  static const int portRangeTest = 66;
  static const int portTelemetryDevice = 67;
  static const int portTraceroute = 70;

  // Default intervals (seconds)
  static const int defaultPingIntervalSec = 15;
  static const int defaultOutOfRangeTimeoutSec = 90;

  /// No longer forces anything (Phase 2: intervals are clamped by
  /// AirtimeModel). Kept so older call sites still compile.
  static const bool devForceTimingDefaults = false;

  static int pingIntervalSec(SharedPreferences prefs) =>
      prefs.getInt(prefPingIntervalSec) ?? defaultPingIntervalSec;

  /// Map tiles from remote servers (OSM / our CloudFront). Default on: the
  /// map is core. Off: no tile request leaves the phone.
  static bool mapTilesEnabled(SharedPreferences prefs) =>
      prefs.getBool(prefMapTilesEnabled) ?? true;

  static bool terrainOnlineEnabled(SharedPreferences prefs) =>
      prefs.getBool(prefTerrainOnlineEnabled) ?? false;

  static bool fasterThanRecommended(SharedPreferences prefs) =>
      prefs.getBool(prefFasterThanRecommended) ?? false;

  /// Whether relayed packets (hops > 0) count as measurements. Off by
  /// default: their SNR/RSSI describe the relay's link, not the base's,
  /// and a relay makes a dead spot look alive.
  static bool countRelayedPackets(SharedPreferences prefs) =>
      prefs.getBool(prefCountRelayedPackets) ?? false;

  static int outOfRangeTimeoutSec(SharedPreferences prefs) =>
      prefs.getInt(prefOutOfRangeTimeoutSec) ?? defaultOutOfRangeTimeoutSec;
  static const int defaultAckTimeoutSec = 30;
  static const int defaultGpsBackfillWindowSec = 10;

  // BLE reconnection
  static const int bleReconnectInitialDelaySec = 2;
  static const int bleReconnectMaxDelaySec = 60;

  // Map defaults
  static const double defaultMapZoom = 14.0;
  static const double defaultMapLat = 37.7749; // fallback if no GPS
  static const double defaultMapLon = -122.4194;

  // Tile caching
  static const int tileCacheMaxStaleDays = 30;

  // Signal colour bands: MarginBand in utils/link_margin.dart (link margin,
  // not absolute SNR).

  /// "45 s", "90 s", "5 min", "2.5 min".
  static String formatSeconds(int sec) {
    if (sec < 120) return '$sec s';
    final min = sec / 60;
    return min == min.roundToDouble()
        ? '${min.round()} min'
        : '${min.toStringAsFixed(1)} min';
  }

  // SharedPreferences keys

  /// AI analysis: random per-install id sent as X-Device-Id (daily quota).
  static const String prefAiDeviceId = 'ai_device_id';

  /// AI analysis: the user accepted the one-time "what is sent" sheet.
  static const String prefAiConsent = 'ai_analysis_consent';

  /// Last AI result for a comparison: `ai_analysis_<hash of session ids>`.
  static const String prefAiAnalysisPrefix = 'ai_analysis_';
  static const String prefActiveSessionId = 'active_session_id';
  static const String prefKeepScreenOn = 'keep_screen_on';

  /// Live map turns with the compass so the way you face is up.
  static const String prefMapHeadingUp = 'map_heading_up';
  static const String prefSignalDirection = 'signal_direction';
  static const String prefColorMetric = 'color_metric';
  static const String prefPingIntervalSec = 'ping_interval_sec';

  /// "Faster than recommended": pings and the base beacon may go below the
  /// airtime budget (down to AirtimeModel.fastestIntervalSecFor).
  static const String prefFasterThanRecommended = 'faster_than_recommended';
  static const String prefCountRelayedPackets = 'count_relayed_packets';
  static const String prefShowSignalLegend = 'show_signal_legend';
  static const String prefLastMobileRig = 'last_mobile_rig_id';
  static const String prefLastBaseRig = 'last_base_rig_id';
  static const String prefOutOfRangeTimeoutSec = 'out_of_range_timeout_sec';

  /// Privacy: fetch map tiles from remote servers (default on).
  static const String prefMapTilesEnabled = 'privacy_map_tiles_enabled';

  /// Base map style on the maps (`MapStyle.name`: standard | terrain).
  static const String prefMapStyle = 'map_style';

  /// Distance units (`DistanceUnits.name`: automatic | miles | kilometres).
  static const String prefDistanceUnits = 'distance_units';

  /// App and map look (`Appearance.name`: automatic | bright | night).
  static const String prefAppearance = 'app_appearance';

  /// Opt-in: allow fetching elevations from api.opentopodata.org (sends the
  /// map area's coordinates). Default off.
  static const String prefTerrainOnlineEnabled = 'terrain_online_enabled';
  static const String prefTerrainOnlineConfirmed = 'terrain_online_confirmed';
  static const String prefTerrainBaseHeightM = 'terrain_base_height_m';
  static const String prefTerrainMobileHeightM = 'terrain_mobile_height_m';

  /// Base location the user placed for one coverage map ("lat,lon").
  static String prefTerrainBaseLocation(int mapId) =>
      'terrain_base_location_$mapId';

  /// Set when the user unticked "Use the base location from Radio Setup" for
  /// this map: the Radio Setup location must not stand in for the base.
  static String prefTerrainBaseOptOut(int mapId) =>
      'terrain_base_optout_$mapId';
}

/// Direction of signal being measured
enum SignalDirection { rx, tx, both }

/// Collection tier
enum CollectionTier { passive, rangeTest, activeProbe }

/// Range state for out-of-range monitor
/// Range state for out-of-range monitor. [radioLost] means the phone lost
/// its Bluetooth link to the mobile radio, so the base can't be judged.
enum RangeState { inRange, outOfRange, unknown, radioLost }

/// Packet direction stored in DB
class PacketDirection {
  static const String rx = 'rx';
  static const String tx = 'tx';
  static const String ack = 'ack';
}

/// Packet type stored in DB
class PacketType {
  static const String position = 'position';
  static const String telemetry = 'telemetry';
  static const String nodeinfo = 'nodeinfo';
  static const String rangeTest = 'range_test';
  static const String ping = 'ping';
  static const String ack = 'ack';
  static const String other = 'other';

  // MeshCore packet kinds (payload type of the raw frame).
  static const String advert = 'advert';
  static const String trace = 'trace';

  /// Group (channel) text or data.
  static const String group = 'group';

  /// Direct (encrypted, addressed) message, request or response.
  static const String direct = 'direct';

  /// Anything else heard but not decoded (raw/custom payloads).
  static const String raw = 'raw';

  static String fromPortNum(int portNum) {
    switch (portNum) {
      case AppConstants.portPosition:
        return position;
      case AppConstants.portTelemetryDevice:
        return telemetry;
      case AppConstants.portNodeInfo:
        return nodeinfo;
      case AppConstants.portRangeTest:
        return rangeTest;
      case AppConstants.portRouting:
        return ack;
      default:
        return other;
    }
  }
}

/// What produced a packet_events row (`source_kind`, schema v7).
class SourceKind {
  static const String rangeTest = 'range_test';
  static const String telemetry = 'telemetry';
  static const String position = 'position';
  static const String ack = 'ack';
  static const String traceroute = 'traceroute';

  /// Anything else heard, and every row from before schema v7.
  static const String passive = 'passive';

  /// A beacon the base should have sent but the mobile did not hear
  /// (synthesised from timing; carries no signal).
  static const String telemetryMiss = 'telemetry_miss';

  /// A packet heard but kept only for the log: where it came from over
  /// the air is unknown (MeshCore direct packets still travelling along a
  /// path carry only the hops ahead, `ReceivedPacket.hopsKnown == false`),
  /// so its signal belongs to an unknown relay. Never a coverage sample or
  /// dot; only the full CSV export lists it.
  static const String logOnly = 'log_only';

  /// Rows that are a heard beacon sample.
  static const beaconSamples = {rangeTest, telemetry};

  /// Rows that are not a signal sample at the phone's position: synthesised
  /// misses and log-only packets. Maps, counts, statistics and every export
  /// but the full CSV leave them out.
  static const notSamples = {telemetryMiss, logOnly};
}

/// Ack status stored in ping_correlations
class AckStatus {
  static const String received = 'received';

  /// Acked by a relaying node (implicit ack), not by the destination.
  static const String implicit = 'implicit';
  static const String timeout = 'timeout';
  static const String error = 'error';

  /// The radio refused to send because of its duty-cycle / rate limit.
  static const String throttled = 'throttled';

  /// Routing_Error names that mean "throttled" rather than "failed".
  static const throttleReasons = {'DUTY_CYCLE_LIMIT', 'RATE_LIMIT_EXCEEDED'};

  /// Radio's NAK reason is appended, e.g. "error:PKI_UNKNOWN_PUBKEY".
  static String errorWithReason(String reason) => '$error:$reason';
  static bool isError(String status) =>
      status == error || status.startsWith('$error:');

  /// NAK reasons that mean "sent, nobody answered": our radio transmitted
  /// (and retransmitted) the ping and gave up waiting for an ACK. Firmware
  /// `ReliableRouter` NAKs a want_ack packet with MAX_RETRANSMIT after its
  /// retries; the bench saw every ping to a deaf base end this way
  /// (2026-11-09, T1000-E 2.7.26), never as a 30 s timeout. New pings are
  /// stored as [timeout] (`MeshtasticRadio`); rows recorded before that
  /// still say "error:MAX_RETRANSMIT".
  static const noReplyReasons = {'MAX_RETRANSMIT'};

  /// The ping went on air and no reply came: a [timeout], or an older
  /// row with a [noReplyReasons] NAK.
  static bool isNoReply(String status) =>
      status == timeout ||
      noReplyReasons.any((r) => status == errorWithReason(r));
}
