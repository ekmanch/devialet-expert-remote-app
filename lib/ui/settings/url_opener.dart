import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a URL in the external browser. Injected so widget tests can
/// record the call instead of launching anything; the only file that
/// imports `url_launcher`.
typedef UrlOpener = Future<bool> Function(Uri uri);

final urlOpenerProvider = Provider<UrlOpener>(
  (_) => (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);
