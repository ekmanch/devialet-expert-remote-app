import 'package:flutter_test/flutter_test.dart';

import 'package:devialet_expert_remote_app/ui/control/source_glyphs.dart';

void main() {
  test('mockup glyphs by live name; AirPlay is matched before Air', () {
    expect(sourceGlyphFor('Optical 1'), '\u25c9');
    expect(sourceGlyphFor('UPnP'), '\u25eb');
    expect(sourceGlyphFor('Roon Ready'), '\u25cd');
    expect(sourceGlyphFor('AirPlay'), '\u25c8');
    expect(sourceGlyphFor('Spotify'), '\u25d0');
    expect(sourceGlyphFor('AIR'), '\u25c7');
    expect(sourceGlyphFor('Chromecast Audio'), '\u25c9');
    expect(sourceGlyphFor(null), '\u2013');
  });

  test('v36 kind labels by live name; unknown names get none', () {
    expect(sourceKindFor('Optical 1'), 'Digital in');
    expect(sourceKindFor('UPnP'), 'Network');
    expect(sourceKindFor('Roon Ready'), 'Roon');
    expect(sourceKindFor('AirPlay'), 'Apple AirPlay');
    expect(sourceKindFor('Spotify'), 'Spotify Connect');
    expect(sourceKindFor('AIR'), 'Devialet AIR');
    expect(sourceKindFor('Chromecast Audio'), isNull);
  });

  test('painted kind by live name; AirPlay before Air; unknown falls back to optical', () {
    expect(sourceGlyphKindFor('Optical 1'), SourceGlyphKind.optical);
    expect(sourceGlyphKindFor('UPnP'), SourceGlyphKind.upnp);
    expect(sourceGlyphKindFor('Roon Ready'), SourceGlyphKind.roon);
    expect(sourceGlyphKindFor('AirPlay'), SourceGlyphKind.airplay);
    expect(sourceGlyphKindFor('spotify connect'), SourceGlyphKind.spotify);
    expect(sourceGlyphKindFor('AIR'), SourceGlyphKind.air);
    expect(sourceGlyphKindFor('Chromecast Audio'), SourceGlyphKind.optical);
    expect(sourceGlyphKindFor(null), SourceGlyphKind.none);
  });
}
