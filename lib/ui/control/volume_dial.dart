import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'control_keys.dart';
import 'volume_dial_math.dart';

/// The 220px volume ring: full track circle plus a gradient arc from the
/// dial's start angle, and a rotary drag on the ring band. [minDb] /
/// [maxDb] are parameters (the floor/ceiling settings later), never
/// constants (TODO 2.0.4). [child] is the centre readout and is not a
/// drag target.
class VolumeDial extends StatefulWidget {
  const VolumeDial({
    super.key,
    required this.minDb,
    required this.maxDb,
    required this.valueDb,
    required this.enabled,
    required this.onChanged,
    required this.onChangeEnd,
    required this.child,
    this.showArc = true,
    this.size = 220,
    this.trackWidth = 10,
    this.trackRadius = 96,
    this.innerHitSlop = 28,
    this.stepDb = 0.5,
  });

  final double minDb;
  final double maxDb;
  final double valueDb;
  final bool enabled;

  /// Live, on every pan update, already clamped to the range and
  /// quantized to [stepDb].
  final ValueChanged<double>? onChanged;

  /// On release — the value to send (Task 3.6.x).
  final ValueChanged<double>? onChangeEnd;
  final Widget child;
  final bool showArc;
  final double size;
  final double trackWidth;
  final double trackRadius;

  /// How far *inside* the track's inner edge a drag may start.
  final double innerHitSlop;
  final double stepDb;

  @override
  State<VolumeDial> createState() => VolumeDialState();
}

class VolumeDialState extends State<VolumeDial> {
  double? _lastDb;

  double get _innerRadius => widget.trackRadius - widget.trackWidth / 2 - widget.innerHitSlop;

  void _emit(double fraction) {
    final db = quantizeDb(dbForFraction(fraction, widget.minDb, widget.maxDb), widget.stepDb)
        .clamp(widget.minDb, widget.maxDb);
    if (db == _lastDb) return;
    _lastDb = db;
    widget.onChanged?.call(db);
  }

  void _onPanStart(DragStartDetails d) {
    if (!widget.enabled) return;
    final f = dialFractionForPointer(d.localPosition, Size.square(widget.size), snapInDeadZone: true);
    if (f != null) _emit(f);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!widget.enabled) return;
    final f = dialFractionForPointer(d.localPosition, Size.square(widget.size), snapInDeadZone: false);
    if (f != null) _emit(f);
  }

  void _onPanEnd() {
    final db = _lastDb;
    _lastDb = null;
    if (db != null) widget.onChangeEnd?.call(db);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppTheme.of(context).tokens;
    final fraction = dialFraction(widget.valueDb, widget.minDb, widget.maxDb);
    return Semantics(
      slider: true,
      enabled: widget.enabled,
      label: 'Volume',
      value: widget.valueDb.toStringAsFixed(1),
      child: RawGestureDetector(
        key: ControlKeys.dial,
        behavior: HitTestBehavior.deferToChild,
        gestures: <Type, GestureRecognizerFactory>{
          _EagerPanGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_EagerPanGestureRecognizer>(
                _EagerPanGestureRecognizer.new,
                (recognizer) {
                  recognizer
                    ..onStart = widget.enabled ? _onPanStart : null
                    ..onUpdate = widget.enabled ? _onPanUpdate : null
                    ..onEnd = widget.enabled ? (_) => _onPanEnd() : null
                    ..onCancel = widget.enabled ? _onPanEnd : null;
                },
              ),
        },
        child: _RingHitBox(
          innerRadius: _innerRadius,
          outerRadius: widget.size / 2,
          child: CustomPaint(
            painter: _DialRingPainter(
              trackColor: t.dialTrack,
              gradientColors: t.dialGradientColors,
              gradientStops: t.dialGradientStops,
              fraction: widget.showArc ? fraction : 0,
              strokeWidth: widget.trackWidth,
              radius: widget.trackRadius,
            ),
            child: SizedBox.square(dimension: widget.size, child: Center(child: widget.child)),
          ),
        ),
      ),
    );
  }
}

/// A touch on the ring band is unambiguously a dial gesture, so claim the
/// pointer at once instead of racing the enclosing scroll view (whose
/// vertical-drag recognizer would otherwise win a mostly-vertical drag).
class _EagerPanGestureRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

/// Hit-tests only the ring band; the readout children never receive
/// pointer events, so a press on the centre starts no drag.
class _RingHitBox extends SingleChildRenderObjectWidget {
  const _RingHitBox({required this.innerRadius, required this.outerRadius, required super.child});

  final double innerRadius;
  final double outerRadius;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderRingHitBox(innerRadius, outerRadius);

  @override
  void updateRenderObject(BuildContext context, _RenderRingHitBox renderObject) {
    renderObject
      ..innerRadius = innerRadius
      ..outerRadius = outerRadius;
  }
}

class _RenderRingHitBox extends RenderProxyBox {
  _RenderRingHitBox(this._innerRadius, this._outerRadius);

  double _innerRadius;
  set innerRadius(double v) => _innerRadius = v;
  double _outerRadius;
  set outerRadius(double v) => _outerRadius = v;

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => false;

  @override
  bool hitTestSelf(Offset position) =>
      dialHitTest(position, size, innerRadius: _innerRadius, outerRadius: _outerRadius);
}

class _DialRingPainter extends CustomPainter {
  const _DialRingPainter({
    required this.trackColor,
    required this.gradientColors,
    required this.gradientStops,
    required this.fraction,
    required this.strokeWidth,
    required this.radius,
  });

  final Color trackColor;
  final List<Color> gradientColors;
  final List<double>? gradientStops;
  final double fraction;
  final double strokeWidth;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..color = trackColor,
    );
    // Round caps would paint a dot at zero, so skip the arc entirely —
    // the mockup clears the path the same way.
    if (fraction <= 0) return;
    final gradientRect = (Offset.zero & size).deflate(size.shortestSide * 14 / 220);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: gradientColors,
        stops: gradientStops,
      ).createShader(gradientRect);
    canvas.drawArc(
      rect,
      kDialStartAngleDeg * math.pi / 180,
      kDialMaxSweepDeg * fraction * math.pi / 180,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_DialRingPainter old) =>
      old.fraction != fraction ||
      old.trackColor != trackColor ||
      old.gradientColors != gradientColors ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}

/// The dial's centre: value (34 mono, copper), unit (12 mono, kept in
/// layout when hidden so nothing shifts) and the active source label
/// (10.5 display, uppercase).
class DialReadout extends StatelessWidget {
  const DialReadout({
    super.key,
    required this.valueText,
    required this.unitVisible,
    required this.sourceLabel,
  });

  final String valueText;
  final bool unitVisible;
  final String sourceLabel;

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          valueText,
          key: ControlKeys.dialValue,
          style: theme.type
              .mono(size: 34, weight: FontWeight.w500, letterSpacingEm: -0.01, color: t.copperBright, height: 1)
              .copyWith(shadows: t.isDark ? [Shadow(color: t.accentTint(0.35), blurRadius: 18)] : null),
        ),
        Visibility(
          visible: unitVisible,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: Text('dB', key: ControlKeys.dialUnit, style: theme.type.mono(size: 12, letterSpacingEm: 0.05, color: t.textDim)),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            sourceLabel.toUpperCase(),
            key: ControlKeys.dialSourceLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.type.display(size: 10.5, letterSpacingEm: 0.2, color: t.textFaint),
          ),
        ),
      ],
    );
  }
}
