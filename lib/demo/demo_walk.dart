// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

// Demo data for screenshots (demo mode only). Signal readings and timing
// come from a real 19-minute field test (two Seeed T1000-E radios, Medium
// Fast); the track has been MOVED to start at the Empire Polo Club, Indio,
// so it doesn't show where the test actually took place.
// Columns: seconds from start, lat, lon, alt, gps accuracy, snr, rssi,
// hops, packet type, direction, from base?, ping ack status, round trip ms.

class DemoRow {
  final int t;
  final double lat;
  final double lon;
  final double? alt;
  final double? accuracy;
  final double? snr;
  final int? rssi;
  final int hops;
  final String type;
  final String direction;
  final bool fromBase;
  final String? ackStatus;
  final int? roundTripMs;

  const DemoRow(this.t, this.lat, this.lon, this.alt, this.accuracy, this.snr,
      this.rssi, this.hops, this.type, this.direction, this.fromBase,
      this.ackStatus, this.roundTripMs);
}

/// Where the base radio sits in the demo.
const demoBaseLat = 33.679811;
const demoBaseLon = -116.237256;

const demoWalk = <DemoRow>[
  DemoRow(0, 33.6798110, -116.2372560, -10.0, 9.6, 10.25, -67, 0, 'nodeinfo', 'rx', true, null, null),
  DemoRow(7, 33.6798110, -116.2372560, -10.0, 9.6, null, null, 0, 'ping', 'tx', false, 'received', 3959),
  DemoRow(11, 33.6798787, -116.2372157, -8.6, 13.9, 11.25, -70, 0, 'ack', 'ack', true, null, null),
  DemoRow(13, 33.6798851, -116.2371766, -8.9, 7.8, 8.75, -68, 0, 'range_test', 'rx', true, null, null),
  DemoRow(22, 33.6798731, -116.2371120, -11.4, 2.4, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(28, 33.6799743, -116.2371047, -11.6, 4.7, 7.0, -87, 0, 'range_test', 'rx', true, null, null),
  DemoRow(30, 33.6799743, -116.2371047, -11.6, 4.7, 8.75, -91, 0, 'position', 'rx', true, null, null),
  DemoRow(37, 33.6800706, -116.2371124, -11.8, 4.7, null, null, 0, 'ping', 'tx', false, 'received', 7890),
  DemoRow(45, 33.6801095, -116.2371433, -11.8, 4.7, 7.25, -100, 0, 'ack', 'ack', true, null, null),
  DemoRow(52, 33.6801546, -116.2371351, -11.8, 3.9, null, null, 0, 'ping', 'tx', false, 'received', 5250),
  DemoRow(57, 33.6801546, -116.2371351, -11.8, 3.9, 6.75, -100, 0, 'ack', 'ack', true, null, null),
  DemoRow(67, 33.6801546, -116.2371351, -11.8, 3.9, null, null, 0, 'ping', 'tx', false, 'received', 4350),
  DemoRow(72, 33.6801546, -116.2371351, -11.8, 3.9, 7.25, -86, 0, 'ack', 'ack', true, null, null),
  DemoRow(73, 33.6801546, -116.2371351, -11.8, 3.9, 9.25, -93, 0, 'range_test', 'rx', true, null, null),
  DemoRow(82, 33.6800890, -116.2370518, -7.2, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4681),
  DemoRow(87, 33.6801298, -116.2370221, -13.2, 4.8, 9.5, -88, 0, 'ack', 'ack', true, null, null),
  DemoRow(89, 33.6801311, -116.2369643, -14.9, 4.9, 6.0, -81, 0, 'range_test', 'rx', true, null, null),
  DemoRow(97, 33.6804173, -116.2367952, -12.2, 4.8, null, null, 0, 'ping', 'tx', false, 'received', 4349),
  DemoRow(102, 33.6808209, -116.2366598, -13.1, 2.5, 9.0, -89, 0, 'ack', 'ack', true, null, null),
  DemoRow(112, 33.6815920, -116.2362507, -9.0, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 3660),
  DemoRow(116, 33.6817026, -116.2361821, -9.0, 5.0, 6.5, -102, 0, 'ack', 'ack', true, null, null),
  DemoRow(117, 33.6817482, -116.2361569, -9.0, 5.0, 5.75, -104, 0, 'range_test', 'rx', true, null, null),
  DemoRow(127, 33.6816721, -116.2351368, -8.1, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 3840),
  DemoRow(131, 33.6817064, -116.2346715, -6.3, 5.0, -5.25, -112, 0, 'ack', 'ack', true, null, null),
  DemoRow(133, 33.6817293, -116.2345112, -5.4, 5.0, -4.5, -111, 0, 'range_test', 'rx', true, null, null),
  DemoRow(142, 33.6819423, -116.2331733, 6.5, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 7471),
  DemoRow(150, 33.6820915, -116.2320733, 11.1, 5.0, -15.0, -115, 0, 'ack', 'ack', true, null, null),
  DemoRow(155, 33.6821551, -116.2311615, 14.4, 5.0, -17.25, -115, 0, 'range_test', 'rx', true, null, null),
  DemoRow(157, 33.6821069, -116.2308034, 15.6, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(172, 33.6812258, -116.2290638, 19.3, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(187, 33.6798029, -116.2277974, 7.7, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(202, 33.6802606, -116.2262181, 6.2, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(217, 33.6814165, -116.2247532, 11.4, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(232, 33.6825494, -116.2235020, 19.3, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(247, 33.6834383, -116.2214726, 22.0, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(262, 33.6843051, -116.2212135, 28.8, 39.3, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(277, 33.6829010, -116.2223311, 20.6, 4.7, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(292, 33.6821842, -116.2244427, 23.3, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(307, 33.6804711, -116.2258291, 13.2, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(322, 33.6798298, -116.2276145, 7.7, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 29402),
  DemoRow(337, 33.6809091, -116.2287129, 10.8, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 18152),
  DemoRow(352, 33.6821112, -116.2304965, 18.1, 5.0, -10.25, -115, 0, 'ack', 'ack', true, null, null),
  DemoRow(352, 33.6821112, -116.2304965, 18.1, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 6571),
  DemoRow(355, 33.6822015, -116.2310833, 16.9, 5.0, -12.75, -115, 0, 'ack', 'ack', true, null, null),
  DemoRow(359, 33.6821846, -116.2316459, 16.6, 5.0, -9.5, -114, 0, 'ack', 'ack', true, null, null),
  DemoRow(361, 33.6821679, -116.2318297, 16.9, 5.0, -6.0, -114, 0, 'range_test', 'rx', true, null, null),
  DemoRow(367, 33.6820221, -116.2329833, 15.0, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 3961),
  DemoRow(371, 33.6819267, -116.2336081, 12.9, 5.0, -4.75, -111, 0, 'ack', 'ack', true, null, null),
  DemoRow(373, 33.6818944, -116.2338221, 11.7, 5.0, -0.5, -111, 0, 'range_test', 'rx', true, null, null),
  DemoRow(382, 33.6817217, -116.2355183, 0.1, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4022),
  DemoRow(386, 33.6819009, -116.2362431, -6.0, 5.0, 4.25, -104, 0, 'ack', 'ack', true, null, null),
  DemoRow(397, 33.6829164, -116.2376918, -16.7, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 7201),
  DemoRow(404, 33.6834305, -116.2384298, -19.7, 5.0, 3.0, -108, 0, 'ack', 'ack', true, null, null),
  DemoRow(412, 33.6837358, -116.2385319, -20.0, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4592),
  DemoRow(417, 33.6841364, -116.2382115, -19.4, 5.0, 3.5, -107, 0, 'ack', 'ack', true, null, null),
  DemoRow(419, 33.6843309, -116.2380818, -19.1, 5.0, 0.5, -109, 0, 'range_test', 'rx', true, null, null),
  DemoRow(427, 33.6851740, -116.2375859, -18.8, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4441),
  DemoRow(432, 33.6856356, -116.2373265, -16.7, 5.0, -4.0, -111, 0, 'ack', 'ack', true, null, null),
  DemoRow(434, 33.6859598, -116.2371510, -16.1, 5.0, -5.0, -113, 0, 'range_test', 'rx', true, null, null),
  DemoRow(436, 33.6862917, -116.2369603, -15.4, 5.0, -9.25, -114, 0, 'position', 'rx', true, null, null),
  DemoRow(442, 33.6871385, -116.2364186, -15.7, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4682),
  DemoRow(447, 33.6877451, -116.2358311, -14.2, 5.0, -19.75, -115, 0, 'ack', 'ack', true, null, null),
  DemoRow(457, 33.6889582, -116.2344349, -11.8, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(472, 33.6902589, -116.2322377, -6.9, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(487, 33.6915140, -116.2295674, 1.0, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(502, 33.6925783, -116.2273320, 4.7, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(517, 33.6927080, -116.2271489, 5.0, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(532, 33.6918027, -116.2291066, 0.9, 4.7, null, null, 0, 'ping', 'tx', false, 'received', 29912),
  DemoRow(547, 33.6906433, -116.2315633, 1.3, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 16412),
  DemoRow(562, 33.6894845, -116.2338606, -4.8, 5.0, -15.5, -115, 0, 'ack', 'ack', true, null, null),
  DemoRow(562, 33.6894845, -116.2338606, -4.8, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 5972),
  DemoRow(564, 33.6893623, -116.2340330, -6.0, 5.0, -10.25, -115, 0, 'ack', 'ack', true, null, null),
  DemoRow(568, 33.6888067, -116.2346890, -6.3, 5.0, -15.75, -115, 0, 'ack', 'ack', true, null, null),
  DemoRow(577, 33.6876646, -116.2359939, -9.3, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 3632),
  DemoRow(581, 33.6872045, -116.2364307, -11.2, 5.0, -11.5, -114, 0, 'ack', 'ack', true, null, null),
  DemoRow(592, 33.6855110, -116.2374487, -15.1, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4201),
  DemoRow(596, 33.6847162, -116.2378834, -16.7, 5.0, 1.75, -107, 0, 'ack', 'ack', true, null, null),
  DemoRow(607, 33.6831701, -116.2392112, -19.4, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 3931),
  DemoRow(611, 33.6826964, -116.2397341, -20.0, 5.0, 0.5, -110, 0, 'ack', 'ack', true, null, null),
  DemoRow(621, 33.6814398, -116.2411103, -23.1, 5.0, 1.75, -108, 0, 'position', 'rx', true, null, null),
  DemoRow(622, 33.6812792, -116.2412857, -23.1, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 6122),
  DemoRow(628, 33.6804921, -116.2421498, -24.0, 5.0, -2.5, -112, 0, 'ack', 'ack', true, null, null),
  DemoRow(630, 33.6802079, -116.2424853, -23.4, 5.0, 1.5, -108, 0, 'range_test', 'rx', true, null, null),
  DemoRow(637, 33.6795149, -116.2435231, -24.0, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 6632),
  DemoRow(644, 33.6791446, -116.2446042, -26.7, 5.0, -7.5, -112, 0, 'ack', 'ack', true, null, null),
  DemoRow(652, 33.6787972, -116.2459016, -29.8, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4592),
  DemoRow(657, 33.6787371, -116.2461294, -29.8, 5.0, -5.75, -113, 0, 'ack', 'ack', true, null, null),
  DemoRow(667, 33.6777353, -116.2458332, -34.3, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(682, 33.6760339, -116.2445591, -33.1, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(697, 33.6748698, -116.2452550, -25.5, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(712, 33.6737687, -116.2471165, -8.4, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(717, 33.6733293, -116.2474812, 0.7, 5.0, -21.0, -113, 0, 'range_test', 'rx', true, null, null),
  DemoRow(727, 33.6720247, -116.2478398, 6.2, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 16502),
  DemoRow(742, 33.6702636, -116.2480446, 26.6, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(744, 33.6701769, -116.2481751, 27.8, 5.0, -20.25, -113, 0, 'ack', 'ack', true, null, null),
  DemoRow(757, 33.6694280, -116.2500935, 44.6, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(772, 33.6691193, -116.2518920, 60.1, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(787, 33.6678708, -116.2537669, 69.3, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(802, 33.6662950, -116.2536381, 59.5, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(817, 33.6643152, -116.2535008, 22.7, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(832, 33.6632466, -116.2516302, 0.7, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(847, 33.6633081, -116.2506169, -5.4, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(862, 33.6646547, -116.2478398, -11.8, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(877, 33.6653795, -116.2446812, -10.9, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(892, 33.6651430, -116.2437046, -15.1, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(907, 33.6635523, -116.2424382, -18.8, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(922, 33.6634874, -116.2421330, -18.2, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(937, 33.6655817, -116.2406529, -20.3, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(952, 33.6675043, -116.2385090, -17.9, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(967, 33.6692438, -116.2358006, -11.2, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(982, 33.6698637, -116.2344169, -8.7, 5.0, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(997, 33.6717729, -116.2351902, -10.9, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 14703),
  DemoRow(1012, 33.6739778, -116.2352665, -6.9, 5.0, -14.0, -113, 0, 'ack', 'ack', true, null, null),
  DemoRow(1012, 33.6739778, -116.2352665, -6.9, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4353),
  DemoRow(1017, 33.6746535, -116.2353570, -2.6, 5.0, -14.75, -112, 0, 'ack', 'ack', true, null, null),
  DemoRow(1018, 33.6747981, -116.2354425, -0.8, 5.0, -10.75, -111, 0, 'range_test', 'rx', true, null, null),
  DemoRow(1027, 33.6758012, -116.2364873, -3.9, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4353),
  DemoRow(1032, 33.6762438, -116.2367695, -7.8, 5.0, 2.0, -108, 0, 'ack', 'ack', true, null, null),
  DemoRow(1042, 33.6778192, -116.2369221, -9.3, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4653),
  DemoRow(1047, 33.6785250, -116.2369069, -6.0, 5.0, 8.0, -87, 0, 'ack', 'ack', true, null, null),
  DemoRow(1057, 33.6798639, -116.2368535, -6.6, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4082),
  DemoRow(1061, 33.6800596, -116.2368354, -6.9, 5.0, 8.5, -83, 0, 'ack', 'ack', true, null, null),
  DemoRow(1072, 33.6801119, -116.2370900, -8.1, 5.0, null, null, 0, 'ping', 'tx', false, 'received', 4202),
  DemoRow(1076, 33.6801440, -116.2371472, -12.5, 2.9, 7.25, -101, 0, 'ack', 'ack', true, null, null),
  DemoRow(1078, 33.6801440, -116.2371472, -12.5, 2.9, 8.0, -98, 0, 'range_test', 'rx', true, null, null),
  DemoRow(1081, 33.6801440, -116.2371472, -12.5, 2.9, 8.25, -92, 0, 'position', 'rx', true, null, null),
  DemoRow(1087, 33.6800547, -116.2371034, -12.3, 3.6, null, null, 0, 'ping', 'tx', false, 'received', 8283),
  DemoRow(1096, 33.6799461, -116.2371005, -11.6, 4.7, 10.5, -84, 0, 'ack', 'ack', true, null, null),
  DemoRow(1102, 33.6798551, -116.2371041, -12.0, 2.3, null, null, 0, 'ping', 'tx', false, 'timeout', null),
  DemoRow(1110, 33.6798133, -116.2371244, -12.0, 2.4, 10.75, -71, 0, 'range_test', 'rx', true, null, null),
  DemoRow(1117, 33.6798223, -116.2372551, -12.2, 2.5, null, null, 0, 'ping', 'tx', false, 'timeout', null),
];
