import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/config/app_info.dart';

void main() {
  test('kAppVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml has a semver version line');
    expect(kAppVersion, match!.group(1));
  });
}
