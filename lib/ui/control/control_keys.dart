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
  static const deviceDivider = ValueKey('control.deviceDivider');
  static const dialWrap = ValueKey('control.dialWrap');
  static const dial = ValueKey('control.dial');
  static const dialValue = ValueKey('control.dialValue');
  static const dialUnit = ValueKey('control.dialUnit');
  static const dialSourceLabel = ValueKey('control.dialSourceLabel');
  static const volMinus = ValueKey('control.volMinus');
  static const volPlus = ValueKey('control.volPlus');
  static const roundRow = ValueKey('control.roundRow');
  static const muteButton = ValueKey('control.mute');
  static const muteIcon = ValueKey('control.muteIcon');
  static const powerButton = ValueKey('control.power');
  static const powerIcon = ValueKey('control.powerIcon');
  static const sourceLabel = ValueKey('control.sourceLabel');
  static const sourceTrigger = ValueKey('control.sourceTrigger');
  static const sourceName = ValueKey('control.sourceName');
  static const sourceRows = ValueKey('control.sourceRows');
  static ValueKey<String> sourceCard(int index) => ValueKey('control.sourceCard.$index');
  static const column = ValueKey('control.column');
  static const sheetBack = ValueKey('control.sheetBack');
  static ValueKey<String> ampRow(String ip) => ValueKey('control.ampRow.$ip');
  static const ampNoneRow = ValueKey('control.ampRow.none');
  static const ampList = ValueKey('control.ampList');
  static const ampManualRow = ValueKey('control.ampManualRow');
  static const ampGroupLabel = ValueKey('control.ampGroupLabel');
}
