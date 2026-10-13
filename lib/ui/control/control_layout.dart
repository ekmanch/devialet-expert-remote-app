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
/// action row top 22 → 18. Settings keeps the mockup values. (The action
/// row went with the alternate layout — power lives on the amp card and
/// mute in the round row — so its constant went too.)
const double kControlHeaderBottom = 16;
const double kControlHeaderBottomEyebrow = 14;
const double kControlSectionTopFirst = 18;
const double kControlSectionTop = 20;
const double kControlDialTop = 4;
const double kControlDialBottom = 0;
const double kControlVolumeButtonsTop = 14;

/// The round − · mute · + row under the dial (alternate v47c: `#volButtons
/// .rb` 66 px, gap 34, 26 px icons at stroke 1.8, sized for a 360 dp
/// phone). Declared and rendered agree in the mockup — no text inside.
const double kRoundButtonSize = 66;
const double kRoundButtonGap = 34;
const double kRoundButtonIcon = 26;

/// The "filled" Control layout (alternate v47c, `fitDial()`): Source is
/// pinned to the bottom, the spare height sits between the round row and
/// the Source label (never under everything), and the dial grows into it.
/// Measured with the dial at [kControlDialBase], the spacer's height is
/// `spare`; then `size = clamp(base + spare − keepGap, base, min(0.88 ×
/// content width, max))`. The 24 dp keep-gap is what stays above Source
/// after the growth (the round row's 14·k margin eats part of it); the
/// 8 dp minimum is the spacer's `min-height`, so a screen shorter than the
/// natural column scrolls instead of squeezing. Mockup numbers, rendered
/// = declared (no text involved); the S25 result is pinned in
/// `control_screen_fit_test`.
const double kControlDialBase = 220;
const double kControlDialMax = 300;
const double kControlDialWidthFraction = 0.88;
const double kControlFillMinGap = 8;
const double kControlFillKeepGap = 24;
