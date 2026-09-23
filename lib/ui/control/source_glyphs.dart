/// The mockups' Unicode source glyphs, keyed on the *live* name (names are
/// per-unit, so this is a best-effort visual, never protocol logic).
/// Coverage on device is a Task 2.0.13 check; if any renders as tofu,
/// replace with painted icons in `stroke_icons.dart`. Spotify's glyph is
/// the text fallback only: `SourceGlyph` paints it (see [isSpotifySource]).
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

/// The source sheet's mono "kind" label (v36), best-effort from the live
/// name like the glyph; `null` for a name the mockup doesn't cover, so
/// the row shows no label rather than a guess.
String? sourceKindFor(String name) {
  final n = name.toLowerCase();
  if (n.contains('optical')) return 'Digital in';
  if (n.contains('upnp')) return 'Network';
  if (n.contains('roon')) return 'Roon';
  if (n.contains('airplay')) return 'Apple AirPlay';
  if (n.contains('spotify')) return 'Spotify Connect';
  if (n.contains('air')) return 'Devialet AIR';
  return null;
}

/// The ◐ character renders far smaller than the other glyphs in most
/// fonts, so Spotify is drawn as a painted half-filled ring instead.
bool isSpotifySource(String? name) => name != null && name.toLowerCase().contains('spotify');
