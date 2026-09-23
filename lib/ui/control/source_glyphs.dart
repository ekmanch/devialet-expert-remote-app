/// Which painted glyph a source gets, keyed on the *live* name (names are
/// per-unit, so this is a best-effort visual, never protocol logic).
///
/// Every glyph is painted (`SourceGlyph`), never a Unicode character: the
/// mockups' ◉ ◫ ◍ ◈ ◐ ◇ come out of the phone's font at wildly different
/// sizes (2026-09-23 S25: ◉ ◍ ◈ tiny, ◇ large), so the six are drawn in
/// one 20-unit box and always match (checklist 15/18).
enum SourceGlyphKind { optical, upnp, roon, airplay, spotify, air, none }

SourceGlyphKind sourceGlyphKindFor(String? name) {
  if (name == null) return SourceGlyphKind.none;
  final n = name.toLowerCase();
  if (n.contains('optical')) return SourceGlyphKind.optical;
  if (n.contains('upnp')) return SourceGlyphKind.upnp;
  if (n.contains('roon')) return SourceGlyphKind.roon;
  if (n.contains('airplay')) return SourceGlyphKind.airplay; // before 'air'
  if (n.contains('spotify')) return SourceGlyphKind.spotify;
  if (n.contains('air')) return SourceGlyphKind.air;
  return SourceGlyphKind.optical;
}

/// The mockup character each painted glyph stands in for (documentation
/// and the glyph table's tests only — nothing renders these).
String sourceGlyphFor(String? name) => switch (sourceGlyphKindFor(name)) {
  SourceGlyphKind.optical => '◉',
  SourceGlyphKind.upnp => '◫',
  SourceGlyphKind.roon => '◍',
  SourceGlyphKind.airplay => '◈',
  SourceGlyphKind.spotify => '◐',
  SourceGlyphKind.air => '◇',
  SourceGlyphKind.none => '–',
};

/// The name as shown: the amp's own text, except that the word "Air"
/// (Devialet's Asynchronous Intelligent Route — an acronym) is always
/// "AIR", as Devialet's own documentation sometimes has it and the owner
/// prefers (2026-09-23). Word-bounded, so "AirPlay" is untouched. The raw
/// name stays the protocol/matching key everywhere else.
String sourceDisplayName(String name) => name.replaceAllMapped(_air, (_) => 'AIR');
final RegExp _air = RegExp(r'\bair\b', caseSensitive: false);

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
