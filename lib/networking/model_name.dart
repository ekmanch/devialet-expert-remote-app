/// mDNS hostname → display-ready make/model (Task 3.9.5; `docs/protocol.md`
/// "mDNS model-name resolution"; KDE `crates/protocol/src/model_name.rs`,
/// itself a port of the Kotlin app's `AmpModelNameResolver.parseModelName`).
///
/// Devialet's Spotify Connect hosts look like
/// `Expert140Pro-K48A00904ZE1V.local` (measured on the real amp,
/// 2026-09-24): the model, digits and suffix run together before the
/// first `-`, the serial after it. This is a general boundary transform,
/// **not** a per-model lookup table: a space goes in at every ASCII
/// letter→digit and digit→UPPERCASE boundary (digit→lowercase is *not*
/// one, so a hypothetical `2go` stays `2go`), then "Devialet " is
/// prefixed. Returns null when nothing precedes the first `-`.
///
/// One deliberate delta from the KDE / Kotlin originals: a trailing
/// `.local.` / `.local` is stripped first (case-insensitively), so a
/// hyphen-less host can never yield "Devialet Something.local.". The
/// originals never met one; the rule is written down so it is not a
/// surprise.
String? parseModelName(String mdnsHostname) {
  var host = mdnsHostname.trim();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  if (host.toLowerCase().endsWith('.local')) host = host.substring(0, host.length - '.local'.length);
  final raw = host.split('-').first.trim();
  if (raw.isEmpty) return null;
  final spaced = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    final c = raw.codeUnitAt(i);
    if (i > 0) {
      final prev = raw.codeUnitAt(i - 1);
      final boundary = (_isAsciiLetter(prev) && _isAsciiDigit(c)) || (_isAsciiDigit(prev) && _isAsciiUpper(c));
      if (boundary) spaced.write(' ');
    }
    spaced.writeCharCode(c);
  }
  return 'Devialet $spaced';
}

bool _isAsciiDigit(int c) => c >= 0x30 && c <= 0x39;
bool _isAsciiUpper(int c) => c >= 0x41 && c <= 0x5A;
bool _isAsciiLetter(int c) => _isAsciiUpper(c) || (c >= 0x61 && c <= 0x7A);
