import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'control_layout.dart';

/// The Control column as a single layout pass (alternate v47c "filled"):
/// `[top] [dial] [roundRow] … spare … [bottom]`, with [bottom] pinned to
/// the bottom edge and the dial grown into the spare height by the
/// `fitDial()` rule in `control_layout.dart`.
///
/// Why a render object and not `Column`/`Flexible`: the dial's *widgets*
/// need the fitted size (readout fonts scale with it), which only a
/// `LayoutBuilder` in the dial slot can deliver — and a `LayoutBuilder`
/// refuses intrinsic-size queries, which `SliverFillRemaining`,
/// `IntrinsicHeight` and a `Column` with flex children all make. This box
/// answers intrinsics itself from the three measured slots plus the
/// dial's base size and never asks the dial child; the dial is laid out
/// exactly once per pass, under tight constraints, so its `LayoutBuilder`
/// is its own relayout boundary (a drag frame rebuilds only the dial).
///
/// Height = `max(natural, constraints.minHeight)`: the screen passes the
/// viewport height as the minimum, so the column fills it when it can and
/// grows past it (and scrolls) when it cannot — short phones, large text.
class FilledControlLayout extends MultiChildRenderObjectWidget {
  FilledControlLayout({
    super.key,
    required Widget top,
    required Widget dial,
    required Widget roundRow,
    required Widget bottom,
  }) : super(children: [top, dial, roundRow, bottom]);

  @override
  RenderObject createRenderObject(BuildContext context) => RenderFilledControlLayout();

  /// The `fitDial()` rule, exposed for tests: [spare] is the spacer's
  /// height with the dial at [kControlDialBase] (≥ [kControlFillMinGap]).
  static double dialSizeFor({required double width, required double spare}) {
    final cap = math.max(kControlDialBase, math.min(kControlDialWidthFraction * width, kControlDialMax));
    return (kControlDialBase + spare - kControlFillKeepGap).clamp(kControlDialBase, cap);
  }

  /// The column's height with the dial at its base size.
  static double naturalHeight({required double top, required double roundRow, required double bottom}) =>
      top +
      kControlDialTop +
      kControlDialBase +
      kControlDialBottom +
      kControlVolumeButtonsTop +
      roundRow +
      kControlFillMinGap +
      bottom;
}

class _FillParentData extends ContainerBoxParentData<RenderBox> {}

class RenderFilledControlLayout extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _FillParentData>, RenderBoxContainerDefaultsMixin<RenderBox, _FillParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FillParentData) child.parentData = _FillParentData();
  }

  RenderBox get _top => firstChild!;
  RenderBox get _dial => childAfter(_top)!;
  RenderBox get _roundRow => childAfter(_dial)!;
  RenderBox get _bottom => lastChild!;

  /// The dial size chosen by the last layout (tests read it).
  double get dialSize => _dialSize;
  double _dialSize = kControlDialBase;

  double _widthFor(BoxConstraints constraints) {
    if (constraints.maxWidth.isFinite) return constraints.maxWidth;
    return [
      _top.getMaxIntrinsicWidth(double.infinity),
      _roundRow.getMaxIntrinsicWidth(double.infinity),
      _bottom.getMaxIntrinsicWidth(double.infinity),
      kControlDialBase,
    ].reduce(math.max);
  }

  @override
  void performLayout() {
    final w = _widthFor(constraints);
    final tight = BoxConstraints.tightFor(width: w);
    _top.layout(tight, parentUsesSize: true);
    _roundRow.layout(tight, parentUsesSize: true);
    _bottom.layout(tight, parentUsesSize: true);
    final t = _top.size.height;
    final r = _roundRow.size.height;
    final b = _bottom.size.height;

    final natural = FilledControlLayout.naturalHeight(top: t, roundRow: r, bottom: b);
    final height = constraints.constrainHeight(math.max(natural, constraints.minHeight));
    final spare = height - natural + kControlFillMinGap;
    final dial = FilledControlLayout.dialSizeFor(width: w, spare: spare);
    final k = dial / kControlDialBase;
    _dialSize = dial;

    // Exactly once, tight: the slot's LayoutBuilder reads `maxWidth`.
    _dial.layout(BoxConstraints.tight(Size.square(dial)));

    final dialTop = t + kControlDialTop;
    final rowTop = dialTop + dial + kControlDialBottom + kControlVolumeButtonsTop * k;
    final bottomTop = height - b;
    assert(
      bottomTop - (rowTop + r) >= kControlFillMinGap - 0.001,
      'the gap above Source fell below its minimum: ${bottomTop - (rowTop + r)}',
    );
    _place(_top, Offset.zero);
    _place(_dial, Offset((w - dial) / 2, dialTop));
    _place(_roundRow, Offset(0, rowTop));
    _place(_bottom, Offset(0, bottomTop));
    size = Size(w, height);
  }

  void _place(RenderBox child, Offset offset) => (child.parentData! as _FillParentData).offset = offset;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final w = _widthFor(constraints);
    final tight = BoxConstraints.tightFor(width: w);
    final natural = FilledControlLayout.naturalHeight(
      top: _top.getDryLayout(tight).height,
      roundRow: _roundRow.getDryLayout(tight).height,
      bottom: _bottom.getDryLayout(tight).height,
    );
    return Size(w, constraints.constrainHeight(math.max(natural, constraints.minHeight)));
  }

  double _intrinsicHeight(double width) => FilledControlLayout.naturalHeight(
    top: _top.getMaxIntrinsicHeight(width),
    roundRow: _roundRow.getMaxIntrinsicHeight(width),
    bottom: _bottom.getMaxIntrinsicHeight(width),
  );

  @override
  double computeMinIntrinsicHeight(double width) => _intrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _intrinsicHeight(width);

  double _intrinsicWidth(double Function(RenderBox) of) =>
      [of(_top), of(_roundRow), of(_bottom), kControlDialBase].reduce(math.max);

  @override
  double computeMinIntrinsicWidth(double height) => _intrinsicWidth((c) => c.getMinIntrinsicWidth(height));

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsicWidth((c) => c.getMaxIntrinsicWidth(height));

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);
}
