import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;
import 'dart:convert';

/// The injector JS lives in assets/js/listing_buttons.js so it can be tested
/// headlessly (tools/js-tests) against AO3 HTML fixtures. The Dart side only
/// substitutes the saved-work-id list and executes it in the webview.
String? _cachedTemplate;

const String _savedIdsPlaceholder = '__FB_SAVED_IDS__';

Future<String> _loadTemplate() async {
  return _cachedTemplate ??=
      await rootBundle.loadString('assets/js/listing_buttons.js');
}

Future<void> injectListingButtons({
  required bool isWindows,
  required win.WebviewController? winController,
  required WebViewController? controller,
  void Function(String message)? dartDebugPrint,
  List<String> savedWorkIds = const [],
}) async {
  try {
    final template = await _loadTemplate();
    // replaceAll: the token must never survive, even if it appears more than
    // once (a comment mentioning it once shadowed the real one — caught by
    // the js-tests).
    final js =
        template.replaceAll(_savedIdsPlaceholder, jsonEncode(savedWorkIds));

    dartDebugPrint?.call('[BrowseTab] Executing injectListingButtons JS...');
    if (isWindows && winController != null) {
      await winController.executeScript(js);
    } else if (controller != null) {
      await controller.runJavaScript(js);
    }
    dartDebugPrint?.call('[BrowseTab] injectListingButtons executed (OK)');
  } catch (e) {
    dartDebugPrint?.call('⚠️ inject listing buttons failed: $e');
  }
}
