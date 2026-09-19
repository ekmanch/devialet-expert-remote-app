/// The mockups' Unicode source glyphs, keyed on the *live* name (names are
/// per-unit, so this is a best-effort visual, never protocol logic).
/// Coverage on device is a Task 2.0.13 check; if any renders as tofu,
/// replace with painted icons in `stroke_icons.dart`.
String sourceGlyphFor(String? name) {
  if (name == null) return '–';
  final n = name.toLowerCase();
  if (n.contains('optical')) return '◉'; // ◉
  if (n.contains('upnp')) return '◫'; // ◫
  if (n.contains('roon')) return '◍'; // ◍
  if (n.contains('airplay')) return '◈'; // ◈
  if (n.contains('spotify')) return '◐'; // ◐
  if (n.contains('air')) return '◇'; // ◇
  return '◉';
}
