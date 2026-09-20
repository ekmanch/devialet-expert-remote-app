import 'package:flutter/widgets.dart';

import '../../domain/settings/app_settings.dart';
import 'db_stepper.dart';

/// Stable keys for the Settings widget tests. Named apart from the
/// domain's `SettingsKeys` (storage keys).
abstract final class SettingsUiKeys {
  static const screen = ValueKey('settings.screen');
  static const backButton = ValueKey('settings.back');
  static const title = ValueKey('settings.title');
  static const persistenceNote = ValueKey('settings.persistenceNote');
  static const themeRow = ValueKey('settings.themeRow');
  static const themeTrailing = ValueKey('settings.themeTrailing');
  static const versionRow = ValueKey('settings.versionRow');
  static const versionValue = ValueKey('settings.versionValue');
  static const githubRow = ValueKey('settings.githubRow');
  static const footer = ValueKey('settings.footer');
  static final startupStepper = DbStepperKeys('settings.startup');
  static final floorStepper = DbStepperKeys('settings.floor');
  static final ceilingStepper = DbStepperKeys('settings.ceiling');

  static ValueKey<String> stepOption(VolumeStepDb step) => ValueKey('settings.step.${step.name}');
  static ValueKey<String> themeOption(AppThemeMode mode) => ValueKey('settings.theme.${mode.name}');
}
