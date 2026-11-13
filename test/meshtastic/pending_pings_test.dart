// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// A ping in flight when the phone's link goes away ends as a LINK_LOST
// error, not a timeout (which would read as the base out of range), and
// dispose never leaves a caller waiting.

import 'package:flutter_test/flutter_test.dart';
import 'package:mesh_analyzer/data/radio/mesh_radio.dart';
import 'package:mesh_analyzer/data/radio/meshtastic/meshtastic_radio.dart';
import 'package:mesh_analyzer/proto/meshtastic/mesh.pb.dart' as pb;
import 'package:mesh_analyzer/proto/meshtastic/portnums.pbenum.dart' as pn;

import 'fake_meshtastic_transport.dart';

const mobileNum = 0x10;
const baseNum = 0x20;

FakeMeshtasticTransport fakeMobile() => FakeMeshtasticTransport(
      myNodeNum: mobileNum,
      nodes: [
        pb.NodeInfo(num: mobileNum, user: pb.User(longName: 'Mobile')),
        pb.NodeInfo(num: baseNum, user: pb.User(longName: 'Base')),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<MeshtasticRadio> connected() async {
    final radio = MeshtasticRadio(transport: fakeMobile());
    await radio.connect(const RadioDescriptor(id: 'mob', name: 'Mobile'));
    expect(radio.isReady, isTrue);
    return radio;
  }

  test('disconnect ends a ping in flight as LINK_LOST', () async {
    final radio = await connected();
    var id = 0;
    final f = radio.ping(baseNum,
        timeout: const Duration(seconds: 30), beforeSend: (p) => id = p);
    await Future<void>.delayed(Duration.zero);
    await radio.disconnect();
    final out = await f.timeout(const Duration(seconds: 1));
    expect(out.status, PingStatus.error);
    expect(out.errorReason, 'LINK_LOST');
    expect(out.pingId, id);
    await radio.dispose();
  });

  // Firmware ReliableRouter gives up on a want_ack DM after its retries and
  // NAKs it with MAX_RETRANSMIT from our own node: on air, unanswered. The
  // bench saw this for every ping to a deaf base (2026-11-09).
  Future<PingOutcome> nakFrom(int from, pb.Routing_Error error) async {
    final t = fakeMobile();
    t.onPacket = (p) =>
        p.to == baseNum && p.decoded.portnum == pn.PortNum.PRIVATE_APP
            ? [routingFrame(p, from: from, error: error)]
            : null;
    final radio = MeshtasticRadio(transport: t);
    await radio.connect(const RadioDescriptor(id: 'mob', name: 'Mobile'));
    final out = await radio
        .ping(baseNum, timeout: const Duration(seconds: 30))
        .timeout(const Duration(seconds: 2));
    await radio.dispose();
    return out;
  }

  test('MAX_RETRANSMIT from our own radio is a timeout', () async {
    final out = await nakFrom(mobileNum, pb.Routing_Error.MAX_RETRANSMIT);
    expect(out.status, PingStatus.timeout);
    expect(out.errorReason, 'MAX_RETRANSMIT');
  });

  test('other NAKs stay errors', () async {
    final out = await nakFrom(mobileNum, pb.Routing_Error.NO_CHANNEL);
    expect(out.status, PingStatus.error);
    expect(out.errorReason, 'NO_CHANNEL');
  });

  test('dispose completes a ping in flight', () async {
    final radio = await connected();
    final f = radio.ping(baseNum, timeout: const Duration(seconds: 30));
    await Future<void>.delayed(Duration.zero);
    await radio.dispose();
    final out = await f.timeout(const Duration(seconds: 1));
    expect(out.status, PingStatus.error);
    expect(out.errorReason, 'LINK_LOST');
  });
}
