/// Interim non-compact layout (TODO 2.0.0): outside the compact width
/// class the Control column is centred and capped at this width so the
/// dial and buttons don't stretch across a tablet. Task 3.11.1 replaces
/// the centred column with the two-pane layout; this constant goes with it.
const double kInterimColumnMaxWidth = 480;

/// Vertical rhythm of the Control column, tightened from the mockups'
/// declared values so the whole column fits the Galaxy S25 (360 × 780
/// logical at 3.0, status bar 34.3, nav bar 15 → 730.7 available)
/// without scrolling (2.0.21, owner request after the debug bar went).
/// Measured with the bundled fonts in `control_screen_fit_test`: the
/// mockup rhythm overshot by 18.3 dp (also ≈ 18 dp on the phone); these
/// take 30 dp out, leaving ≈ 12 dp of slack. Mockup → here:
/// header bottom 20/18 → 16/14, first section top 22 → 18, later
/// sections 26 → 20, dial 8/4 → 4/0, volume buttons top 18 → 14,
/// action row top 22 → 18. Settings keeps the mockup values.
const double kControlHeaderBottom = 16;
const double kControlHeaderBottomEyebrow = 14;
const double kControlSectionTopFirst = 18;
const double kControlSectionTop = 20;
const double kControlDialTop = 4;
const double kControlDialBottom = 0;
const double kControlVolumeButtonsTop = 14;
const double kControlActionRowTop = 18;
