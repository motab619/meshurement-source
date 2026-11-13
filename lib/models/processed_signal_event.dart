// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// A signal measurement event after processing by the PacketProcessor.
/// This is the domain model that flows from service layer to UI.
class ProcessedSignalEvent {
  final DateTime timestamp;
  final int sourceNodeId;
  final String sourceNodeName;
  final double? rxSnr;
  final int? rxRssi;
  final int hopCount;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? gpsAccuracy;
  final String packetType;
  final String direction; // 'rx', 'tx', 'ack'
  final int? meshPacketId;
  final bool viaMqtt;

  const ProcessedSignalEvent({
    required this.timestamp,
    required this.sourceNodeId,
    this.sourceNodeName = 'Unknown',
    this.rxSnr,
    this.rxRssi,
    this.hopCount = 0,
    this.latitude,
    this.longitude,
    this.altitude,
    this.gpsAccuracy,
    required this.packetType,
    required this.direction,
    this.meshPacketId,
    this.viaMqtt = false,
  });

  bool get hasGps => latitude != null && longitude != null;
  bool get isDirect => hopCount == 0;

  @override
  String toString() =>
      'SignalEvent($direction $packetType from 0x${sourceNodeId.toRadixString(16)} '
      'SNR=${rxSnr?.toStringAsFixed(1)} RSSI=$rxRssi hops=$hopCount)';
}
