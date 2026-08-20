import 'dart:convert';
import 'dart:typed_data';

import 'protocol_constants.dart';
import 'volume_codec.dart';

/// One of the fixed 30 source slots reported in a status broadcast.
class DevialetSourceInfo {
  const DevialetSourceInfo({required this.index, required this.isEnabled, required this.name});

  final int index;
  final bool isEnabled;
  final String name;
}

/// A parsed amp status broadcast. See `docs/protocol.md`, "Status packet
/// structure".
class DevialetStatus {
  const DevialetStatus({
    required this.deviceName,
    required this.isPoweredOn,
    required this.isMuted,
    required this.activeSourceIndex,
    required this.volumeDb,
    required this.sources,
  });

  final String deviceName;
  final bool isPoweredOn;
  final bool isMuted;

  /// 0-14, matches the index used for [DevialetSourceInfo.index] /
  /// select-source command mapping.
  final int activeSourceIndex;
  final double volumeDb;

  /// Always exactly 30 entries (indices 0-29), including disabled slots —
  /// matching the amp's fixed-size source table, not just the enabled ones.
  final List<DevialetSourceInfo> sources;

  static const int _sourceSlotCount = 30;
  static const int _deviceNameOffset = 19;
  static const int _deviceNameLength = 31;
  static const int _sourceSlotStride = 17;
  static const int _sourceFlagBaseOffset = 52;
  static const int _sourceNameBaseOffset = 53;
  static const int _sourceNameLength = 16;
  static const int _powerOffset = 562;
  static const int _powerBit = 0x80;
  static const int _sourceIndexOffset = 563;
  static const int _sourceIndexMask = 0x3C;
  static const int _muteOffset = 563;
  static const int _muteBit = 0x02;
  static const int _volumeOffset = 565;

  /// Returns `null` for undersized or malformed packets, matching the
  /// original app's "drop and keep listening" behavior — no crash, no
  /// retry, listener stays alive. See `docs/protocol.md`, "Edge cases
  /// handled in code".
  static DevialetStatus? tryParse(Uint8List data) {
    if (data.length < DevialetProtocol.minStatusPacketLength) return null;
    try {
      final deviceName = _decodeTrimmedUtf8(data, _deviceNameOffset, _deviceNameLength);

      final sources = <DevialetSourceInfo>[
        for (var i = 0; i < _sourceSlotCount; i++)
          DevialetSourceInfo(
            index: i,
            isEnabled: data[_sourceFlagBaseOffset + i * _sourceSlotStride] == 0x31, // ASCII '1'
            name: _decodeTrimmedUtf8(
              data,
              _sourceNameBaseOffset + i * _sourceSlotStride,
              _sourceNameLength,
            ),
          ),
      ];

      final isPoweredOn = (data[_powerOffset] & _powerBit) != 0;
      final activeSourceIndex = (data[_sourceIndexOffset] & _sourceIndexMask) >> 2;
      final isMuted = (data[_muteOffset] & _muteBit) != 0;
      final volumeDb = VolumeCodec.decodeStatusVolume(data[_volumeOffset]);

      return DevialetStatus(
        deviceName: deviceName,
        isPoweredOn: isPoweredOn,
        isMuted: isMuted,
        activeSourceIndex: activeSourceIndex,
        volumeDb: volumeDb,
        sources: sources,
      );
    } catch (_) {
      return null;
    }
  }

  static String _decodeTrimmedUtf8(Uint8List data, int offset, int length) {
    final slice = data.sublist(offset, offset + length);
    return utf8.decode(slice, allowMalformed: true).replaceAll('\x00', '').trim();
  }
}
