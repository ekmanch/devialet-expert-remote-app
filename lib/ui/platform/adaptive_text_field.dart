import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// The manual-IP field: `TextField` on Android, `CupertinoTextField` on
/// iOS, styled from the mockup (r14, 14×16 padding, mono 16, 1px divider
/// border that turns copper-dim on focus).
class AdaptiveTextField extends StatefulWidget {
  const AdaptiveTextField({
    super.key,
    required this.controller,
    required this.placeholder,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String placeholder;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AdaptiveTextField> createState() => _AdaptiveTextFieldState();
}

class _AdaptiveTextFieldState extends State<AdaptiveTextField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = AppTheme.of(context);
    final t = theme.tokens;
    final textStyle = theme.type.mono(size: 16, color: t.text);
    final hintStyle = theme.type.mono(size: 16, color: t.textFaint);
    final borderColor = _focus.hasFocus ? t.copperDim : t.divider;
    const radius = BorderRadius.all(Radius.circular(14));
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
    final formatters = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

    if (theme.style.isCupertino) {
      return CupertinoTextField(
        controller: widget.controller,
        focusNode: _focus,
        autofocus: widget.autofocus,
        placeholder: widget.placeholder,
        placeholderStyle: hintStyle,
        style: textStyle,
        padding: padding,
        keyboardType: TextInputType.number,
        inputFormatters: formatters,
        onSubmitted: widget.onSubmitted,
        cursorColor: t.copperBright,
        decoration: BoxDecoration(
          color: t.surface2,
          border: Border.all(color: borderColor),
          borderRadius: radius,
        ),
      );
    }
    return TextField(
      controller: widget.controller,
      focusNode: _focus,
      autofocus: widget.autofocus,
      style: textStyle,
      keyboardType: TextInputType.number,
      inputFormatters: formatters,
      onSubmitted: widget.onSubmitted,
      cursorColor: t.copperBright,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: t.surface2,
        contentPadding: padding,
        hintText: widget.placeholder,
        hintStyle: hintStyle,
        border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: t.divider)),
        enabledBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: t.divider)),
        focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: t.copperDim)),
      ),
    );
  }
}
