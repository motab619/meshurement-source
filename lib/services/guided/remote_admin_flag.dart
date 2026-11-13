// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

import 'package:shared_preferences/shared_preferences.dart';

/// Whether the base holds our mobile radio's admin key (design §5: the
/// grant Radio Setup's base flow makes over Bluetooth).
///
/// Radio Setup records the grant as the node number of the mobile radio it
/// was made for under [baseRemoteAdminNodeKey]; the key is per radio, so a
/// different mobile radio means no grant. The engine reads it here so the
/// guided test does not depend on where `RadioRoles` ends up keeping it.
const baseRemoteAdminNodeKey = 'base_remote_admin_node';

/// The mobile node number the base's remote-admin grant was made for, or
/// null when the base was never given a key.
int? remoteAdminMobileNode(SharedPreferences prefs) =>
    prefs.getInt(baseRemoteAdminNodeKey);

/// True when [mobileNodeNum] (the radio in hand) is the one the base trusts.
bool remoteAdminGranted(SharedPreferences prefs, int? mobileNodeNum) =>
    mobileNodeNum != null && remoteAdminMobileNode(prefs) == mobileNodeNum;
