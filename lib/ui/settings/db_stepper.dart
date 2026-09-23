import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../platform/adaptive_pressable.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../widgets/dimmed_group.dart';
import 'stepper_repeat.dart';

class DbStepperKeys {
  DbStepperKeys(String base)
    : minus = ValueKey('$base.minus'),
      plus = ValueKey('$base.plus'),
      value = ValueKey('$base.value'),
      entry = ValueKey('$base.entry');

  final ValueKey<String> minus;
  final ValueKey<String> plus;
  final ValueKey<String> value;
  final ValueKey<String> entry;
}

/// A whole-dB stepper (TODO 3.4.3): a tap moves exactly 1 dB, a hold
/// repeats with acceleration, a tap on the value opens direct numeric
/// entry. Controlled: the caller owns [value] and gets every accepted
/// step through [onChanged], already clamped to [min]..[max].
///
/// At a bound the blocked button alone dims to 0.4 and refuses (TODO
/// 3.4.4, KDE): floor/ceiling pass each other's value as the bound, so the
/// 1 dB gap is enforced here with no extra validation.
class DbStepper extends StatefulWidget {
  const DbStepper({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.keys,
  });

  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  final DbStepperKeys keys;

  @override
  State<DbStepper> createState() => _DbStepperState();
}

class _DbStepperState extends State<DbStepper> {
  late final StepperRepeatController _repeat = StepperRepeatController(onTick: _tick);
  int _direction = 0;

  /// Accumulates during a hold so 45 ms ticks don't depend on the parent
  /// having rebuilt in between; resynced from [DbStepper.value] otherwise.
  int _held = 0;

  bool _editing = false;
  bool _revert = false;
  final TextEditingController _entry = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && _editing) _commit();
    });
  }

  @override
  void didUpdateWidget(DbStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_repeat.isActive) _held = widget.value;
  }

  @override
  void dispose() {
    _repeat.dispose();
    _entry.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _tick() {
    final next = (_held + _direction).clamp(widget.min, widget.max);
    if (next == _held) return false;
    _held = next;
    widget.onChanged(next);
    return true;
  }

  void _press(int direction, bool down) {
    if (down) {
      _direction = direction;
      _held = widget.value;
      _repeat.start();
    } else {
      _repeat.stop();
    }
  }

  void _beginEdit() {
    final magnitude = widget.value.abs().toString();
    _entry
      ..text = magnitude
      ..selection = TextSelection(baseOffset: 0, extentOffset: magnitude.length);
    _revert = false;
    setState(() => _editing = true);
  }

  /// Mockup rules: digits only, magnitude → negative (the app supplies the
  /// minus), empty or Escape → previous value, clamped to the bounds.
  void _commit() {
    if (!_editing) return;
    final digits = _entry.text.replaceAll(RegExp('[^0-9]'), '');
    final int next;
    if (_revert || digits.isEmpty) {
      next = widget.value;
    } else {
      final magnitude = int.parse(digits);
      next = (magnitude == 0 ? 0 : -magnitude).clamp(widget.min, widget.max);
    }
    setState(() => _editing = false);
    if (next != widget.value) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    return Row(
      children: [
        _button(theme, '\u2212', widget.keys.minus, -1, blocked: widget.value <= widget.min),
        const SizedBox(width: 10),
        Expanded(child: _editing ? _entryField(theme) : _valueLabel(theme)),
        const SizedBox(width: 10),
        _button(theme, '+', widget.keys.plus, 1, blocked: widget.value >= widget.max),
      ],
    );
  }

  Widget _button(AppTheme theme, String glyph, Key key, int direction, {required bool blocked}) {
    final t = theme.tokens;
    final button = AdaptivePressable(
      key: key,
      onTap: () {},
      borderRadius: BorderRadius.circular(12),
      pressedScale: 0.92,
      onPressedChanged: (down) => _press(direction, down),
      builder: (context, pressed) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed && theme.style.isCupertino ? t.surface2 : t.surface3,
          border: Border.all(color: t.divider),
          borderRadius: BorderRadius.circular(12),
          boxShadow: t.cardShadow,
        ),
        child: Text(glyph, style: theme.type.display(size: 17, color: t.text)),
      ),
    );
    return blocked ? DimmedGroup(dimmed: true, child: button) : button;
  }

  /// v28/v29: the value is plain text in both themes (the accent moved to
  /// the section headings); the tap-to-type underline is `textDim`.
  Widget _valueLabel(AppTheme theme) {
    final t = theme.tokens;
    return AdaptivePressable(
      key: widget.keys.value,
      onTap: _beginEdit,
      borderRadius: BorderRadius.circular(8),
      pressedScale: 1,
      builder: (context, pressed) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          // The mockup hints "tap to type" with a dashed underline while
          // pressed; a solid hairline stands in (Flutter has no dashed border).
          border: Border(bottom: BorderSide(color: pressed ? t.textDim : const Color(0x00000000))),
        ),
        child: Text(
          formatWholeDb(widget.value),
          style: theme.type.mono(size: 15, weight: FontWeight.w600, color: t.text),
        ),
      ),
    );
  }

  Widget _entryField(AppTheme theme) {
    final t = theme.tokens;
    final style = theme.type.mono(size: 15, weight: FontWeight.w600, color: t.text);
    final formatters = [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)];
    final Widget field;
    if (theme.style.isCupertino) {
      field = CupertinoTextField(
        key: widget.keys.entry,
        controller: _entry,
        focusNode: _focus,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: formatters,
        style: style,
        cursorColor: t.text,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: t.textDim, width: 1.5))),
        onSubmitted: (_) => _commit(),
      );
    } else {
      field = TextField(
        key: widget.keys.entry,
        controller: _entry,
        focusNode: _focus,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: formatters,
        style: style,
        cursorColor: t.text,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: UnderlineInputBorder(borderSide: BorderSide(color: t.textDim, width: 1.5)),
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.textDim, width: 1.5)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: t.textDim, width: 1.5)),
        ),
        onSubmitted: (_) => _commit(),
      );
    }
    return Focus(
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _revert = true;
          _focus.unfocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: field,
    );
  }
}
