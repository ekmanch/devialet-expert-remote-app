import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/networking/model_name.dart';

/// The KDE / Kotlin transform without the `.local` strip — the only delta
/// this port added — to prove the strip is what the hyphen-less cases test
/// (checklist 20).
String? parseModelNameNoStrip(String host) {
  final raw = host.split('-').first.trim();
  if (raw.isEmpty) return null;
  final b = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final c = raw[i];
    if (i > 0) {
      final p = raw[i - 1];
      final letter = RegExp(r'[A-Za-z]').hasMatch(p);
      final digit = RegExp(r'\d').hasMatch(p);
      if ((letter && RegExp(r'\d').hasMatch(c)) || (digit && RegExp(r'[A-Z]').hasMatch(c))) b.write(' ');
    }
    b.write(c);
  }
  return 'Devialet $b';
}

void main() {
  group('parseModelName (docs/protocol.md, KDE model_name.rs)', () {
    const cases = <String, String?>{
      // The one real case, measured on 192.168.0.22 on 2026-09-24.
      'Expert140Pro-K48A00904ZE1V.local.': 'Devialet Expert 140 Pro',
      'Expert140Pro-K48A00904ZE1V.local': 'Devialet Expert 140 Pro',
      'Expert140Pro-1234.local.': 'Devialet Expert 140 Pro',
      '2go': 'Devialet 2go',
      'Phantom2Reactor900-serial.local.': 'Devialet Phantom 2 Reactor 900',
      'Konnect-serial.local.': 'Devialet Konnect',
      '900Something-serial.local.': 'Devialet 900 Something',
      '-serial.local.': null,
      '': null,
      '   ': null,
      'NoHyphenHost': 'Devialet NoHyphenHost',
      'NoHyphenHost.local.': 'Devialet NoHyphenHost',
      'NoHyphenHost.LOCAL': 'Devialet NoHyphenHost',
      // Boundaries are ASCII-exact (letter→digit yes, digit→lowercase no).
      'expert140pro-x.LOCAL.': 'Devialet expert 140pro',
    };
    for (final entry in cases.entries) {
      test('"${entry.key}" → ${entry.value}', () => expect(parseModelName(entry.key), entry.value));
    }

    test('the serial never changes the result', () {
      expect(parseModelName('Expert140Pro-1234.local.'), parseModelName('Expert140Pro-9999999.local.'));
    });

    test('proof the strip is what the hyphen-less cases catch: the literal port keeps ".local."', () {
      expect(parseModelNameNoStrip('NoHyphenHost.local.'), 'Devialet NoHyphenHost.local.');
      expect(parseModelNameNoStrip('Expert140Pro-K48A00904ZE1V.local.'), 'Devialet Expert 140 Pro', reason: 'identical where a hyphen exists');
    });
  });
}
