import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Push transition per variant (Material vs UINavigationController-style).
Route<T> adaptivePageRoute<T>(BuildContext context, WidgetBuilder builder) {
  if (AppTheme.of(context).style.isCupertino) {
    return CupertinoPageRoute<T>(builder: builder);
  }
  return MaterialPageRoute<T>(builder: builder);
}
