// Meshurement - maps LoRa mesh radio coverage.
// Copyright (C) 2026 Andy Brunker (Plateau Nerd)
// SPDX-License-Identifier: GPL-3.0-or-later
// Free software under the GNU GPL v3 or later, WITHOUT ANY WARRANTY; see LICENSE.

/// MeshCore companion-radio protocol constants.
///
/// Source of truth: meshcore-dev/MeshCore at commit
/// [meshCoreFirmwareSha] (firmware v1.18.0, FIRMWARE_VER_CODE 14).
/// Command/response/push codes are the `#define`s at the top of
/// examples/companion_radio/MyMesh.cpp (lines 9-140); sizes come from
/// src/MeshCore.h and src/helpers/BaseSerialInterface.h.
///
/// Framing over BLE: one GATT write / notification is exactly one frame,
/// no length prefix. Byte 0 is the code; all multi-byte integers are
/// little-endian.
library;

/// The MeshCore commit every layout in `lib/data/radio/meshcore/` was read
/// from.
const meshCoreFirmwareSha = '81dbae592ffad40b4212bc0b37e82b38da08f4bc';

/// Nordic UART Service used by MeshCore companions
/// (src/helpers/esp32/SerialBLEInterface.cpp:7-9@sha; the nRF52 build uses
/// the same NUS UUIDs).
class MeshCoreBle {
  MeshCoreBle._();

  static const serviceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E';

  /// App -> radio: write commands here.
  static const rxCharacteristicUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E';

  /// Radio -> app: subscribe for responses and pushes.
  static const txCharacteristicUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E';

  /// Default advertised-name prefix (examples/companion_radio/MyMesh.h:66).
  static const namePrefix = 'MeshCore-';
}

/// Sizes and limits.
class MeshCoreLimits {
  MeshCoreLimits._();

  /// Ed25519 public key (src/MeshCore.h:8).
  static const pubKeySize = 32;

  /// Bytes of the sender key in message frames.
  static const pubKeyPrefixSize = 6;

  /// Contact path buffer (src/MeshCore.h:22).
  static const maxPathSize = 64;

  /// Fixed name width in contact and channel frames (ContactInfo.name).
  static const nameSize = 32;

  /// Channel secret width in GET/SET_CHANNEL (only 128-bit keys).
  static const channelSecretSize = 16;

  /// Largest frame current firmware sends or accepts
  /// (BaseSerialInterface.h:5).
  static const maxFrameSize = 176;

  /// Older firmware used 172; commands kept within this fit every radio.
  static const legacyMaxFrameSize = 172;

  /// LoRa packet payload limit (src/MeshCore.h:20).
  static const maxPacketPayload = 184;

  /// Text limit of a DM or channel message (BaseChatMesh.h:8,
  /// 10 * CIPHER_BLOCK_SIZE). Channel messages also carry "name: ".
  static const maxTextLen = 160;

  /// `out_path_len` / `path_len` value meaning "no path" (flood) or, in
  /// received messages, "arrived direct".
  static const pathUnknown = 0xFF;

  /// The companion protocol version we tell the radio we understand in
  /// CMD_DEVICE_QUERY. 3+ makes the radio send the `_V3` message frames
  /// that include SNR (MyMesh.cpp:443, 561@sha); nothing else checks it.
  static const appProtocolVersion = 3;
}

/// Command codes, app -> radio (MyMesh.cpp:9-66@sha).
class MeshCoreCmd {
  MeshCoreCmd._();

  static const appStart = 1;
  static const sendTxtMsg = 2;
  static const sendChannelTxtMsg = 3;
  static const getContacts = 4;
  static const getDeviceTime = 5;
  static const setDeviceTime = 6;
  static const sendSelfAdvert = 7;
  static const setAdvertName = 8;
  static const addUpdateContact = 9;
  static const syncNextMessage = 10;
  static const setRadioParams = 11;
  static const setRadioTxPower = 12;
  static const resetPath = 13;
  static const setAdvertLatLon = 14;
  static const removeContact = 15;
  static const shareContact = 16;
  static const exportContact = 17;
  static const importContact = 18;
  static const reboot = 19;
  static const getBattAndStorage = 20;
  static const setTuningParams = 21;
  static const deviceQuery = 22;
  static const exportPrivateKey = 23;
  static const importPrivateKey = 24;
  static const sendRawData = 25;
  static const sendLogin = 26;
  static const sendStatusReq = 27;
  static const hasConnection = 28;
  static const logout = 29;
  static const getContactByKey = 30;
  static const getChannel = 31;
  static const setChannel = 32;
  static const signStart = 33;
  static const signData = 34;
  static const signFinish = 35;
  static const sendTracePath = 36;
  static const setDevicePin = 37;
  static const setOtherParams = 38;
  static const sendTelemetryReq = 39;
  static const getCustomVars = 40;
  static const setCustomVar = 41;
  static const getAdvertPath = 42;
  static const getTuningParams = 43;
  static const sendBinaryReq = 50;
  static const factoryReset = 51;
  static const sendPathDiscoveryReq = 52;
  static const setFloodScopeKey = 54;
  static const sendControlData = 55;
  static const getStats = 56;
  static const sendAnonReq = 57;
  static const setAutoaddConfig = 58;
  static const getAutoaddConfig = 59;
  static const getAllowedRepeatFreq = 60;
  static const setPathHashMode = 61;
  static const sendChannelData = 62;
  static const setDefaultFloodScope = 63;
  static const getDefaultFloodScope = 64;
  static const sendRawPacket = 65;
  static const runCliCommand = 66;
}

/// Response codes, radio -> app, each a reply to a command
/// (MyMesh.cpp:75-103@sha).
class MeshCoreResp {
  MeshCoreResp._();

  static const ok = 0;
  static const err = 1;
  static const contactsStart = 2;
  static const contact = 3;
  static const endOfContacts = 4;
  static const selfInfo = 5;
  static const sent = 6;
  static const contactMsgRecv = 7;
  static const channelMsgRecv = 8;
  static const currTime = 9;
  static const noMoreMessages = 10;
  static const exportContact = 11;
  static const battAndStorage = 12;
  static const deviceInfo = 13;
  static const privateKey = 14;
  static const disabled = 15;
  static const contactMsgRecvV3 = 16;
  static const channelMsgRecvV3 = 17;
  static const channelInfo = 18;
  static const signStart = 19;
  static const signature = 20;
  static const customVars = 21;
  static const advertPath = 22;
  static const tuningParams = 23;
  static const stats = 24;
  static const autoaddConfig = 25;
  static const allowedRepeatFreq = 26;
  static const channelDataRecv = 27;
  static const defaultFloodScope = 28;
  static const cliReply = 29;
}

/// Push codes, sent by the radio at any time (MyMesh.cpp:117-133@sha).
/// All have the top bit set.
class MeshCorePush {
  MeshCorePush._();

  static const advert = 0x80;
  static const pathUpdated = 0x81;
  static const sendConfirmed = 0x82;
  static const msgWaiting = 0x83;
  static const rawData = 0x84;
  static const loginSuccess = 0x85;
  static const loginFail = 0x86;
  static const statusResponse = 0x87;
  static const logRxData = 0x88;
  static const traceData = 0x89;
  static const newAdvert = 0x8A;
  static const telemetryResponse = 0x8B;
  static const binaryResponse = 0x8C;
  static const pathDiscoveryResponse = 0x8D;
  static const controlData = 0x8E;
  static const contactDeleted = 0x8F;
  static const contactsFull = 0x90;
}

/// Error codes carried in byte 1 of [MeshCoreResp.err]
/// (MyMesh.cpp:135-140@sha).
class MeshCoreErr {
  MeshCoreErr._();

  static const unsupportedCmd = 1;
  static const notFound = 2;
  static const tableFull = 3;
  static const badState = 4;
  static const fileIoError = 5;
  static const illegalArg = 6;

  /// Human name for logs.
  static String name(int? code) => switch (code) {
        unsupportedCmd => 'UNSUPPORTED_CMD',
        notFound => 'NOT_FOUND',
        tableFull => 'TABLE_FULL',
        badState => 'BAD_STATE',
        fileIoError => 'FILE_IO_ERROR',
        illegalArg => 'ILLEGAL_ARG',
        null => 'NONE',
        _ => 'ERR_$code',
      };
}

/// Text message types (src/helpers/TxtDataHelpers.h:6-9@sha).
class MeshCoreTxtType {
  MeshCoreTxtType._();

  static const plain = 0;
  static const cliData = 1;

  /// Plain text signed by the sender: received frames carry a 4-byte
  /// sender-key prefix between the timestamp and the text.
  static const signedPlain = 2;
  static const cliCommand = 3;
}

/// Group datagram types (TxtDataHelpers.h:11-12@sha).
class MeshCoreDataType {
  MeshCoreDataType._();

  /// Rejected by CMD_SEND_CHANNEL_DATA.
  static const reserved = 0x0000;

  /// Developer namespace for experiments.
  static const dev = 0xFFFF;
}

/// Advert/contact types (src/helpers/AdvertDataHelpers.h:7-11@sha).
class MeshCoreAdvType {
  MeshCoreAdvType._();

  static const none = 0;
  static const chat = 1;
  static const repeater = 2;
  static const room = 3;
  static const sensor = 4;
}

/// Contact flag bits (src/helpers/ContactInfo.h:29-33@sha).
class MeshCoreContactFlags {
  MeshCoreContactFlags._();

  static const favourite = 0x01;
  static const telemetryBase = 0x02;
  static const telemetryLocation = 0x04;
  static const telemetryEnvironment = 0x08;
  static const remoteCli = 0x10;
}

/// CMD_GET_STATS sub-types (MyMesh.cpp:70-72@sha).
class MeshCoreStatsType {
  MeshCoreStatsType._();

  static const core = 0;
  static const radio = 1;
  static const packets = 2;
}

/// Request types for binary requests to repeaters
/// (examples/companion_radio/MyMesh.h:74-76@sha).
class MeshCoreReqType {
  MeshCoreReqType._();

  static const getStatus = 0x01;
  static const keepAlive = 0x02;
  static const getTelemetryData = 0x03;
}

/// On-air packet header fields (src/Packet.h:8-17@sha), for decoding the raw
/// bytes in PUSH_CODE_LOG_RX_DATA.
class MeshCoreRouteType {
  MeshCoreRouteType._();

  static const transportFlood = 0x00;
  static const flood = 0x01;
  static const direct = 0x02;
  static const transportDirect = 0x03;
}

/// On-air payload types (src/Packet.h:19-32@sha).
class MeshCorePayloadType {
  MeshCorePayloadType._();

  static const req = 0x00;
  static const response = 0x01;
  static const txtMsg = 0x02;
  static const ack = 0x03;
  static const advert = 0x04;
  static const grpTxt = 0x05;
  static const grpData = 0x06;
  static const anonReq = 0x07;
  static const path = 0x08;
  static const trace = 0x09;
  static const multipart = 0x0A;
  static const control = 0x0B;
  static const rawCustom = 0x0F;
}
