import 'package:flutter/widgets.dart';

/// Material 3 window width classes. Layout is chosen by the *window*, never
/// by device type (TODO.md, "Form factors"): a tablet can present a
/// phone-width window (Split View, Slide Over, Android split-screen) and
/// change it at runtime.
enum WindowWidthClass { compact, medium, expanded }

/// Material 3 window height classes. `compact` is a phone in landscape;
/// the Control column scrolls there rather than shrinking the dial.
enum WindowHeightClass { compact, medium, expanded }

@immutable
class WindowClass {
  const WindowClass({required this.width, required this.height});

  factory WindowClass.fromSize(Size logicalSize) => WindowClass(
    width: widthClassFor(logicalSize.width),
    height: heightClassFor(logicalSize.height),
  );

  /// Material 3 breakpoints (logical pixels / dp).
  static const double mediumMinWidth = 600;
  static const double expandedMinWidth = 840;
  static const double mediumMinHeight = 480;
  static const double expandedMinHeight = 900;

  static WindowWidthClass widthClassFor(double width) {
    if (width < mediumMinWidth) return WindowWidthClass.compact;
    if (width < expandedMinWidth) return WindowWidthClass.medium;
    return WindowWidthClass.expanded;
  }

  static WindowHeightClass heightClassFor(double height) {
    if (height < mediumMinHeight) return WindowHeightClass.compact;
    if (height < expandedMinHeight) return WindowHeightClass.medium;
    return WindowHeightClass.expanded;
  }

  final WindowWidthClass width;
  final WindowHeightClass height;

  @override
  bool operator ==(Object other) =>
      other is WindowClass && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'WindowClass(${width.name}, ${height.name})';
}

/// Installed once per app in `DevialetRemoteApp`'s `builder:` (inside the
/// app's `MediaQuery`, above the `Navigator`, so sheet routes see it too)
/// and rebuilt on every window resize. An `InheritedWidget` rather than a
/// Riverpod provider because the value is derived from `MediaQuery`.
class WindowClassScope extends InheritedWidget {
  const WindowClassScope({super.key, required this.value, required super.child});

  final WindowClass value;

  static WindowClass of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No WindowClassScope above this context');
    return scope!;
  }

  static WindowClass? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<WindowClassScope>()?.value;

  @override
  bool updateShouldNotify(WindowClassScope oldWidget) => value != oldWidget.value;
}
