import 'package:flutter/widgets.dart';

/// Stable keys for widget tests (state × variant tables, label-width
/// invariance, resize survival). Not used for logic.
abstract final class ControlKeys {
  static const header = ValueKey('control.header');
  static const wordmark = ValueKey('control.wordmark');
  static const wordmarkSheen = ValueKey('control.wordmarkSheen');
  static const gearButton = ValueKey('control.gear');
  static const deviceCard = ValueKey('control.deviceCard');
  static const deviceDot = ValueKey('control.deviceDot');
  static const deviceName = ValueKey('control.deviceName');
  static const deviceSub = ValueKey('control.deviceSub');
  static const dialWrap = ValueKey('control.dialWrap');
  static const dial = ValueKey('control.dial');
  static const dialValue = ValueKey('control.dialValue');
  static const dialUnit = ValueKey('control.dialUnit');
  static const dialSourceLabel = ValueKey('control.dialSourceLabel');
  static const volMinus = ValueKey('control.volMinus');
  static const volPlus = ValueKey('control.volPlus');
  static const actionRow = ValueKey('control.actionRow');
  static const muteButton = ValueKey('control.mute');
  static const muteLabel = ValueKey('control.muteLabel');
  static const muteIcon = ValueKey('control.muteIcon');
  static const powerButton = ValueKey('control.power');
  static const powerLabel = ValueKey('control.powerLabel');
  static const powerIcon = ValueKey('control.powerIcon');
  static const sourceTrigger = ValueKey('control.sourceTrigger');
  static const sourceName = ValueKey('control.sourceName');
  static const sourceRows = ValueKey('control.sourceRows');
  static ValueKey<String> sourceCard(int index) => ValueKey('control.sourceCard.$index');
  static const column = ValueKey('control.column');
  static const debugBar = ValueKey('debug.bar');
  static const debugPrev = ValueKey('debug.prev');
  static const debugNext = ValueKey('debug.next');
  static const debugNet = ValueKey('debug.net');
  static const debugPrefsOff = ValueKey('debug.prefsOff');
}
