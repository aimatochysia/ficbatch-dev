import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;

import '../providers/storage_provider.dart';
import '../providers/navigation_provider.dart';
import '../models/work.dart';
import '../models/reading_progress.dart';
import 'browse/browse_navigation.dart';
import 'browse/browse_search.dart';
import 'browse/ao3_extractors.dart';
import 'browse/browse_toolbar.dart';
import 'browse/inject_listing_buttons.dart';
import 'reader_screen.dart';

class BrowseTab extends ConsumerStatefulWidget {
  const BrowseTab({super.key});
  @override
  ConsumerState<BrowseTab> createState() => _BrowseTabState();
}

class _BrowseTabState extends ConsumerState<BrowseTab> {
  WebViewController? _controller;
  win.WebviewController? _winController;
  final TextEditingController _urlController = TextEditingController();
  bool _isLoading = true;
  final bool _isWindows = Platform.isWindows;
  bool _readyToShow = false;
  final String _searchType = 'query';
  String _currentUrl = '';
  Brightness? _lastBrightness;
  String? _pendingThemeMode;
  bool _pageReady = false;
  bool _coverVisible = false;
  bool _menuBlockerActive = false;
  Timer? _loadWatchdog;
  bool _winInitialLoadComplete = false; // Track if initial page load is complete
  bool get _winInited => _winController != null && _winController!.value.isInitialized;
  static const int _browseTabIndex = 3;
  bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  List<String> _getSavedWorkIds() {
    final storage = ref.read(storageProvider);
    return storage.getAllWorks().map((w) => w.id).toList();
  }

  void _clearQueryInput() {
    if (!mounted) return;
    setState(() => _urlController.clear());
  }

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    
    final b = Theme.of(context).brightness;
    if (_lastBrightness != b) {
      _lastBrightness = b;
      final mode = b == Brightness.dark ? 'dark' : 'light';
      if (_isWindows) {
        final ready = _winController != null && _winController!.value.isInitialized && _pageReady;
        if (ready) {
          _injectThemeStyle();
        } else {
          _pendingThemeMode = mode;
        }
      } else {
        final ready = _controller != null && _pageReady;
        if (ready) {
          _injectThemeStyle();
        } else {
          _pendingThemeMode = mode;
        }
      }
      final ready = _isWindows
          ? (_winController != null && _winController!.value.isInitialized && _pageReady)
          : (_controller != null && _pageReady);
      if (ready) {
        _injectEarlyStyle();
      }
      _pulseCover();
    }
  }

  Future<void> _initWebView() async {
    setState(() => _isLoading = true);
    _armLoadWatchdog(timeout: const Duration(seconds: 15));
    try {
      if (_isWindows) {
        _winController = win.WebviewController();
        await _winController!.initialize();
        await _winController!.setBackgroundColor(Colors.transparent);
        await _winController!.setPopupWindowPolicy(win.WebviewPopupWindowPolicy.deny);
        _winController!.webMessage.listen((event) {
          try {
            final s = event?.toString() ?? '';
            if (s.isNotEmpty) _handleInjectedMessage(s);
          } catch (_) {}
        });
        // Listen for URL changes to intercept work page navigation
        _winController!.historyChanged.listen((event) async {
          await _handleWindowsUrlChange();
        });
        _winController!.loadingState.listen((state) async {
          final loading = state == win.LoadingState.loading;
          if (mounted) {
            setState(() {
              _isLoading = loading;
              _readyToShow = !loading ? _readyToShow : false;
              _pageReady = !loading;
              if (loading) _coverVisible = true;
            });
          }
          if (loading) _armLoadWatchdog();
          if (!loading) {
            // Reveal the page as soon as the fast style injections are done;
            // heavier enhancements (buttons, diagnostics) run after reveal so
            // a slow or failing injection can never keep the screen blank.
            try {
              await _injectEarlyStyle();
              await _injectThemeStyle();
            } catch (e) {
              debugPrint('⚠️ Windows style injection failed: $e');
            } finally {
              await _updateCurrentUrl();
              _reveal();
              _winInitialLoadComplete = true;
            }
            try {
              await _applyScrollSpeed();
              await injectListingButtons(
                isWindows: _isWindows,
                winController: _winController,
                controller: _controller,
                dartDebugPrint: debugPrint,
                savedWorkIds: _getSavedWorkIds(),
              );
              Future.delayed(const Duration(milliseconds: 800), () async {
                if (!mounted) return;
                await injectListingButtons(
                  isWindows: _isWindows,
                  winController: _winController,
                  controller: _controller,
                  dartDebugPrint: debugPrint,
                  savedWorkIds: _getSavedWorkIds(),
                );
              });
              if (_pendingThemeMode != null) {
                _pendingThemeMode = null;
                await _injectThemeStyle();
              }
            } catch (e) {
              debugPrint('⚠️ Windows post-reveal injection failed: $e');
            }
          }
        });
        await _winController!.loadUrl('https://archiveofourown.org/');
      } else {
        final c = WebViewController();
        setState(() => _controller = c);
        c
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..addJavaScriptChannel('FB', onMessageReceived: (m) {
            final s = m.message;
            if (s.isNotEmpty) _handleInjectedMessage(s);
          })
          ..setNavigationDelegate(
            NavigationDelegate(
              onNavigationRequest: (request) async {
                // Intercept work page navigation to open reader
                final url = request.url;
                final workIdMatch = RegExp(r'/works/(\d+)(?:/chapters/\d+)?(?:[/?#]|$)').firstMatch(url);
                if (workIdMatch != null && !url.contains('view_full_work')) {
                  final workId = workIdMatch.group(1)!;
                  final storage = ref.read(storageProvider);
                  
                  // Check if work is in library, otherwise create a temporary Work
                  // The reader will load the actual work data from AO3
                  final Work workToOpen = storage.getWork(workId) ?? Work(
                    id: workId,
                    title: 'Work #$workId',
                    author: 'Unknown',
                    tags: [],
                    userAddedDate: DateTime.now(),
                    readingProgress: ReadingProgress.empty(),
                  );
                  
                  // Add to history
                  await storage.addToHistory(
                    workId: workToOpen.id,
                    title: workToOpen.title,
                    author: workToOpen.author,
                  );
                  if (!mounted) return NavigationDecision.prevent;

                  // Open reader for all works
                  final returnUrl = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ReaderScreen(work: workToOpen),
                    ),
                  );
                  
                  // If reader returned a URL, navigate to it
                  if (returnUrl != null && returnUrl.isNotEmpty) {
                    if (_isWindows) {
                      await _winController?.loadUrl(returnUrl);
                    } else {
                      await _controller?.loadRequest(Uri.parse(returnUrl));
                    }
                  }
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              },
              onPageStarted: (_) async {
                setState(() {
                  _isLoading = true;
                  _readyToShow = false;
                  _pageReady = false;
                });
                _armLoadWatchdog();
                _pulseCover();
                try {
                  await _injectEarlyStyle();
                  await _injectThemeStyle();
                } catch (e) {
                  debugPrint('⚠️ Early style injection failed: $e');
                }
              },
              onPageFinished: (url) async {
                // Reveal as soon as the theme style is in (the early style was
                // already injected at onPageStarted); enhancements follow.
                _pageReady = true;
                try {
                  await _injectThemeStyle();
                } catch (e) {
                  debugPrint('⚠️ Mobile theme injection failed: $e');
                } finally {
                  if (mounted) {
                    setState(() => _currentUrl = url);
                  }
                  _reveal();
                }
                try {
                  await _applyScrollSpeed();
                  await injectListingButtons(
                    isWindows: _isWindows,
                    winController: _winController,
                    controller: _controller,
                    dartDebugPrint: debugPrint,
                    savedWorkIds: _getSavedWorkIds(),
                  );
                  Future.delayed(const Duration(milliseconds: 800), () async {
                    if (!mounted) return;
                    await injectListingButtons(
                      isWindows: _isWindows,
                      winController: _winController,
                      controller: _controller,
                      dartDebugPrint: debugPrint,
                      savedWorkIds: _getSavedWorkIds(),
                    );
                  });
                  if (_pendingThemeMode != null) {
                    _pendingThemeMode = null;
                    await _injectThemeStyle();
                  }
                } catch (e) {
                  debugPrint('⚠️ Mobile post-reveal injection failed: $e');
                }
              },
            ),
          )
          ..loadRequest(Uri.parse('https://archiveofourown.org/'));
      }
    } catch (e) {
      debugPrint('WebView init failed: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _injectThemeStyle() async {
    if (!mounted) return;
    
    // Use cached brightness if available, otherwise try to get it safely
    Brightness? brightness = _lastBrightness;
    if (brightness == null) {
      try {
        brightness = Theme.of(context).brightness;
      } catch (e) {
        // If Theme.of(context) fails, use light as default
        debugPrint('⚠️ Could not get theme brightness, using light mode: $e');
        brightness = Brightness.light;
      }
    }
    
    final isDark = brightness == Brightness.dark;
    final mode = isDark ? 'dark' : 'light';
    final js = _buildDarkReaderBootstrapJs(mode);
    debugPrint(
      '[BrowseTab] Injecting dark mode "$mode" on ${_isWindows ? 'Windows' : 'Mobile'}',
    );
    try {
      if (_isWindows && _winController != null) {
        await _winController!.executeScript(js);
      } else if (_controller != null) {
        await _controller!.runJavaScript(js);
      }
      debugPrint('[BrowseTab] Injection script executed for mode "$mode".');
    } catch (e) {
      debugPrint('⚠️ Theme injection failed: $e');
    }
  }

  String _buildDarkReaderBootstrapJs(String mode) {
    return '''
(function () {
  try {
    var MODE = '$mode' === 'dark' ? 'dark' : 'light';
    var CDN = 'https://cdn.jsdelivr.net/npm/darkreader@4.9.58/darkreader.min.js';
    var SCRIPT_ID = '__fb_darkreader_script';
    var pendingMode = MODE;

    function applyMode(mode) {
      try {
        if (mode === 'dark') {
          try { if (window.DarkReader && DarkReader.setFetchMethod) DarkReader.setFetchMethod(window.fetch.bind(window)); } catch(_) {}
          var theme = { brightness: 100, contrast: 100, sepia: 0 };
          var fixes = {
            invert: [],
            ignoreInlineStyle: [],
            ignoreImageAnalysis: [],
            css: `
/* Dark mode: nav/action links are plain text, no boxed background
   (user preference — link text should not carry a background color). */
.pagination a, .pagination .current, .actions a, .navigation.actions a,
.listbox .actions a, .listbox .heading .actions a, .listbox.group ul li a,
ul.actions li a, ol.actions li a, .secondary .actions a, .filters .group .actions a {
  background: none !important; color: #e8e6e3 !important;
  border: none !important; box-shadow: none !important;
}
input, select, textarea, button {
  background-color: #262a2b !important; color: #e8e6e3 !important; border: 1px solid #3a3e41 !important;
}
a.tag, .tag { background-color: #2b3134 !important; color: #e8e6e3 !important; }
`
          };
          DarkReader.enable(theme, fixes);
          try { document.documentElement.style.colorScheme = 'dark'; } catch(_) {}
        } else {
          if (window.DarkReader && DarkReader.isEnabled && DarkReader.isEnabled()) {
            DarkReader.disable();
          }
          try { document.documentElement.style.colorScheme = 'light'; } catch(_) {}
        }
      } catch (e) {
        console.log('[FB-DarkReader] applyMode error', e);
      }
    }

    if (!window.__fb_setTheme) {
      window.__fb_setTheme = function(m) {
        pendingMode = (m === 'dark') ? 'dark' : 'light';
        if (window.DarkReader) applyMode(pendingMode);
      };
    } else {
      pendingMode = MODE;
    }

    if (window.DarkReader) {
      applyMode(pendingMode);
    } else {
      var s = document.getElementById(SCRIPT_ID);
      if (!s) {
        s = document.createElement('script');
        s.id = SCRIPT_ID;
        s.src = CDN;
        s.async = true;
        s.onload = function() {
          try { if (DarkReader && DarkReader.setFetchMethod) DarkReader.setFetchMethod(window.fetch.bind(window)); } catch(_) {}
          applyMode(pendingMode);
        };
        s.onerror = function(e) { console.log('[FB-DarkReader] script load error', e); };
        (document.head || document.documentElement).appendChild(s);
      } else {
        s.addEventListener('load', function(){ applyMode(pendingMode); }, { once: true });
      }
    }

    if (window.__fb_setTheme) window.__fb_setTheme(MODE);
  } catch (e) {
    console.log('[FB-DarkReader] bootstrap error', e);
  }
})();
''';
  }

  Future<void> _injectEarlyStyle() async {
    if (!mounted) return;
    
    // Use cached brightness if available, otherwise try to get it safely
    Brightness? brightness = _lastBrightness;
    if (brightness == null) {
      try {
        brightness = Theme.of(context).brightness;
      } catch (e) {
        // If Theme.of(context) fails, use light as default
        debugPrint('⚠️ Could not get theme brightness for early style, using light mode: $e');
        brightness = Brightness.light;
      }
    }
    
    final isDark = brightness == Brightness.dark;
    const jsRemove = r"""
      (function(){
        try { document.getElementById('fb-early-dark-style')?.remove(); } catch(_) {}
      })();
    """;
    const jsDark = r"""
      (function(){
        try {
          const prev = document.getElementById('fb-early-dark-style');
          if (prev) prev.remove();
          const s = document.createElement('style');
          s.id = 'fb-early-dark-style';
          s.textContent = `
            html, body { background-color: #121212 !important; color: #e0e0e0 !important; }
            * { background-color: transparent !important; color: inherit !important; }
            /* In dark mode, nav/action links must not get a boxed background */
            ul.navigation.actions a, .navigation.actions a {
              background: none !important;
              border-color: transparent !important;
              box-shadow: none !important;
            }
          `;
          (document.documentElement || document.body).prepend(s);
          console.log('[FB-Dark] early style injected');
        } catch(e) { console.log('[FB-Dark] early style error', e); }
      })();
    """;
    try {
      if (_isWindows && _winController != null) {
        await _winController!.executeScript(isDark ? jsDark : jsRemove);
      } else if (_controller != null) {
        await _controller!.runJavaScript(isDark ? jsDark : jsRemove);
      }
    } catch (e) {
      debugPrint('⚠️ Early style injection failed: $e');
    }
  }

  Future<void> _applyScrollSpeed() async {
    if (!_isDesktop) return;
    
    // Load scroll speed from reader settings
    final storage = ref.read(storageProvider);
    final prefs = await storage.settingsBox.get('reader_settings');
    
    double scrollSpeed = 1.0;
    if (prefs != null) {
      try {
        final prefsMap = prefs is Map<String, dynamic> 
            ? prefs 
            : Map<String, dynamic>.from(prefs as Map);
        scrollSpeed = (prefsMap['scrollSpeed'] ?? 1.0).toDouble();
      } catch (e) {
        debugPrint('⚠️ Failed to load scroll speed setting: $e');
        scrollSpeed = 1.0;
      }
    }

    final js = '''
      (function() {
        // Remove any existing scroll speed handler
        if (window.__fbScrollSpeedHandler) {
          document.removeEventListener('wheel', window.__fbScrollSpeedHandler);
        }
        
        // Create new handler with current speed
        window.__fbScrollSpeedHandler = function(e) {
          if (e.ctrlKey || e.metaKey) return; // Don't interfere with zoom
          
          e.preventDefault();
          const speed = $scrollSpeed;
          const delta = e.deltaY * speed;
          
          window.scrollBy({
            top: delta,
            behavior: 'auto'
          });
        };
        
        // Add the handler
        document.addEventListener('wheel', window.__fbScrollSpeedHandler, { passive: false });
      })();
    ''';

    try {
      if (_isWindows && _winController != null) {
        await _winController!.executeScript(js);
      } else if (_controller != null) {
        await _controller!.runJavaScript(js);
      }
    } catch (e) {
      debugPrint('⚠️ Scroll speed injection failed: $e');
    }
  }

  void _pulseCover({Duration duration = const Duration(milliseconds: 200)}) {
    if (!mounted) return;
    setState(() => _coverVisible = true);
    Future.delayed(duration, () {
      if (!mounted) return;
      setState(() => _coverVisible = false);
    });
  }

  /// While a toolbar popup menu is open (and briefly after it closes), block
  /// pointer events from reaching the webview: with a physical mouse on
  /// Android, clicks on menu items leak through the platform view and
  /// navigate the page underneath.
  void _handleMenuOpenChanged(bool open) {
    if (open) {
      setState(() => _menuBlockerActive = true);
    } else {
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) setState(() => _menuBlockerActive = false);
      });
    }
  }

  /// Make the webview visible and clear every loading overlay. Centralized so
  /// no code path can leave the screen blank.
  void _reveal() {
    _loadWatchdog?.cancel();
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _readyToShow = true;
      _coverVisible = false;
    });
  }

  /// Failsafe: if a page load (or its style injection) hangs, force-reveal
  /// after [timeout] so the user is never stuck on a blank screen.
  void _armLoadWatchdog({Duration timeout = const Duration(seconds: 10)}) {
    _loadWatchdog?.cancel();
    _loadWatchdog = Timer(timeout, () {
      if (mounted && !_readyToShow) {
        debugPrint('[BrowseTab] Load watchdog fired — forcing reveal');
        _reveal();
      }
    });
  }

  void _performSearch() {
    performQuickSearch(
      searchType: _searchType,
      urlController: _urlController,
      isWindows: _isWindows,
      winController: _winController,
      controller: _controller,
      onUrlChange: (u) => setState(() => _currentUrl = u),
    );
  }

  Future<T?> _getJson<T>(String jsValueExpr) async {
    final wrapped = 'JSON.stringify(($jsValueExpr))';
    try {
      if (_isWindows && _winController != null) {
        final raw = await _winController!.executeScript(wrapped);
        final s = raw is List
            ? (raw.isNotEmpty ? raw.first?.toString() ?? '' : '')
            : (raw?.toString() ?? '');
        final decoded =
            _tryJsonDecode<T>(s) ?? _tryJsonDecode<T>(_stripQuotes(s));
        return decoded;
      } else if (_controller != null) {
        final result = await _controller!.runJavaScriptReturningResult(wrapped);
        final str = _asDartString(result);
        final decoded =
            _tryJsonDecode<T>(str) ?? _tryJsonDecode<T>(_stripQuotes(str));
        return decoded;
      }
    } catch (e) {
      debugPrint('⚠️ _getJson failed: $e');
    }
    return null;
  }

  String _asDartString(Object? val) {
    if (val == null) return '';
    if (val is String) return val;
    return val.toString();
  }

  T? _tryJsonDecode<T>(String s) {
    try {
      return jsonDecode(s) as T;
    } catch (_) {
      try {
        final stripped = _stripQuotes(s);
        return jsonDecode(stripped) as T;
      } catch (_) {
        return null;
      }
    }
  }

  String _stripQuotes(String s) {
    final t = s.trim();
    if (t.length >= 2 &&
        ((t.startsWith('"') && t.endsWith('"')) ||
            (t.startsWith("'") && t.endsWith("'")))) {
      return t.substring(1, t.length - 1).replaceAll(r'\"', '"');
    }
    return t;
  }

  Future<Work?> _extractWorkFromPage() async {
    final url = _isWindows
        ? await _getWindowsCurrentUrl()
        : await _controller?.currentUrl();
    if (url == null) return null;
    final workId = _extractWorkId(url);
    if (workId == null) return null;

    final meta = await fetchAo3MetaCombined(_getJson);
    if (meta == null) return null;

    return buildWorkFromMeta(workId, meta);
  }

  Future<void> _confirmAndSaveToLibrary() async {
    try {
      final work = await _extractWorkFromPage();
      if (work == null) {
        _showSnackBar('Not a valid AO3 work page.');
        return;
      }

      final storage = ref.read(storageProvider);
      final cats = await storage.getCategories();

      if (cats.isEmpty) {
        if (storage.getWork(work.id) != null) {
          if (context.mounted) {
            _showSnackBar('“${work.title}” is already in your library.');
          }
          return;
        }
        await storage.saveWork(work);
        if (context.mounted) {
          _showSnackBar('Saved “${work.title}” to library (default).');
        }
        return;
      }

      // Get existing categories for this work (if already saved)
      final existingCategories = await storage.getCategoriesForWork(work.id);
      if (!mounted) return;
      final selected = Set<String>.from(existingCategories);
      final newCats = await showDialog<Set<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(existingCategories.isEmpty ? 'Select categories' : 'Update categories'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: cats.map((c) {
                  final checked = selected.contains(c);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(c),
                    value: checked,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          selected.add(c);
                        } else {
                          selected.remove(c);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, Set<String>.from(selected)),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );

      if (newCats == null || newCats.isEmpty) return;

      // Duplicate-in-category notice: nothing actually changed.
      if (existingCategories.isNotEmpty &&
          newCats.length == existingCategories.length &&
          newCats.containsAll(existingCategories)) {
        if (context.mounted) {
          _showSnackBar(
              '“${work.title}” is already in ${newCats.join(', ')}.');
        }
        return;
      }

      await storage.saveWork(work);
      await storage.setCategoriesForWork(work.id, newCats);
      if (context.mounted) {
        _showSnackBar('Saved “${work.title}” to ${newCats.join(', ')}.');
      }
    } catch (e, st) {
      debugPrint('Save confirm failed: $e\n$st');
      _showSnackBar('Failed to extract AO3 metadata.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to navigation changes - must be in build method for Riverpod
    ref.listen<int>(navigationProvider, (prev, next) {
      final wasBrowse = (prev ?? _browseTabIndex) == _browseTabIndex;
      final isBrowse = next == _browseTabIndex;
      if (wasBrowse != isBrowse) {
        _clearQueryInput();
      }
    });
    
    final storage = ref.read(storageProvider);

    Future<void> onHome() => goHome(
      isWindows: _isWindows,
      winController: _winController,
      controller: _controller,
      onUrlChange: (u) => setState(() => _currentUrl = u),
      clearInput: _clearQueryInput,
    );
    Future<void> onBack() => goBack(
      isWindows: _isWindows,
      winController: _winController,
      controller: _controller,
      clearInput: _clearQueryInput,
    );
    Future<void> onForward() => goForward(
      isWindows: _isWindows,
      winController: _winController,
      controller: _controller,
      clearInput: _clearQueryInput,
    );
    Future<void> onRefresh() => refreshPage(
      isWindows: _isWindows,
      winController: _winController,
      controller: _controller,
    );

    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: BrowseToolbar(
              urlController: _urlController,
              onHome: onHome,
              onBack: onBack,
              onForward: onForward,
              onRefresh: onRefresh,
              onQuickSearch: _performSearch,
              onAdvancedSearch: () => openAdvancedSearch(
                context: context,
                storage: storage,
                isWindows: _isWindows,
                winController: _winController,
                controller: _controller,
                onUrlChange: (u) => setState(() => _currentUrl = u),
              ),
              onSaveCurrentSearch: () => saveCurrentSearch(
                context: context,
                storage: storage,
                getCurrentUrl: _getCurrentUrl,
                currentUrl: _currentUrl,
                setCurrentUrl: (u) => setState(() => _currentUrl = u),
              ),
              onLoadSavedSearch: () async {
                final saved = await storage.getSavedSearches();
                if (!context.mounted) return;
                await showSavedSearchDialog(
                  context: context,
                  saved: saved,
                  storage: storage,
                  isWindows: _isWindows,
                  winController: _winController,
                  controller: _controller,
                  setCurrentUrl: (u) => setState(() => _currentUrl = u),
                );
              },
              onSaveToLibrary: _confirmAndSaveToLibrary,
              onMenuOpenChanged: _handleMenuOpenChanged,
            ),
          ),
          if (_isLoading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: Stack(
              children: [
                AnimatedOpacity(
                  opacity: _readyToShow ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: SizedBox.expand(
                    child: _isWindows
                        ? (_winInited
                              ? win.Webview(_winController!)
                              : const SizedBox.shrink())
                        : (_controller != null
                              ? WebViewWidget(controller: _controller!)
                              : const SizedBox.shrink()),
                  ),
                ),
                if (!_readyToShow)
                  Container(
                    color: Theme.of(context).colorScheme.surface,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                IgnorePointer(
                  ignoring: !_coverVisible,
                  child: AnimatedOpacity(
                    opacity: _coverVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 120),
                    child: Container(
                      color: Theme.of(context).colorScheme.surface,
                      // Never show a plain blank cover — always indicate work.
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
                ),
                // Invisible click shield while a toolbar popup is open, so
                // mouse clicks on menu items can't leak into the webview.
                if (_menuBlockerActive)
                  Positioned.fill(
                    child: Container(color: Colors.transparent),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _extractWorkId(String url) {
    final match = RegExp(r'/works/(\d+)').firstMatch(url);
    return match?.group(1);
  }

  Future<String?> _getWindowsCurrentUrl() async {
    if (_winController == null) return null;
    try {
      final direct = await _winController!.executeScript(
        'window.location.href',
      );
      if (direct is List && direct.isNotEmpty) {
        return direct.first.toString().trim();
      }
      if (direct is String && direct.isNotEmpty) {
        return _stripQuotes(direct).trim();
      }
    } catch (_) {}

    try {
      final json = await _winController!.executeScript(
        'JSON.stringify(window.location.href)',
      );
      if (json is List && json.isNotEmpty) {
        final s = json.first.toString();
        final decoded = _tryJsonDecode<String>(s) ?? _stripQuotes(s);
        return decoded.trim();
      }
      if (json is String && json.isNotEmpty) {
        final decoded = _tryJsonDecode<String>(json) ?? _stripQuotes(json);
        return decoded.trim();
      }
    } catch (_) {}

    return null;
  }

  Future<String?> _getCurrentUrl() async {
    return _isWindows
        ? await _getWindowsCurrentUrl()
        : await _controller?.currentUrl();
  }

  Future<void> _updateCurrentUrl() async {
    final url = await _getCurrentUrl();
    if (!mounted) return;
    setState(() {
      _currentUrl = (url ?? '').trim();
    });
  }

  /// Handle URL changes in Windows webview to intercept work page navigation
  Future<void> _handleWindowsUrlChange() async {
    if (!mounted || _winController == null) return;
    
    // Don't intercept until initial page load is complete
    if (!_winInitialLoadComplete) return;
    
    final url = await _getWindowsCurrentUrl();
    if (url == null) return;
    
    // Check if this is a work page (but not already viewing full work)
    final workIdMatch = RegExp(r'/works/(\d+)(?:/chapters/\d+)?(?:[/?#]|$)').firstMatch(url);
    if (workIdMatch != null && !url.contains('view_full_work')) {
      final workId = workIdMatch.group(1)!;
      final storage = ref.read(storageProvider);
      
      // Check if work is in library, otherwise create a temporary Work
      // The reader will load the actual work data from AO3
      final Work workToOpen = storage.getWork(workId) ?? Work(
        id: workId,
        title: 'Work #$workId',
        author: 'Unknown',
        tags: [],
        userAddedDate: DateTime.now(),
        readingProgress: ReadingProgress.empty(),
      );
      
      // Add to history
      await storage.addToHistory(
        workId: workToOpen.id,
        title: workToOpen.title,
        author: workToOpen.author,
      );
      
      // Go back to prevent staying on the work page
      try {
        await _winController!.goBack();
      } catch (_) {
        // If goBack fails, navigate to home
        await _winController!.loadUrl('https://archiveofourown.org/');
      }
      if (!mounted) return;

      // Open reader for the work
      final returnUrl = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (context) => ReaderScreen(work: workToOpen),
        ),
      );
      
      // If reader returned a URL, navigate to it
      if (returnUrl != null && returnUrl.isNotEmpty) {
        await _winController?.loadUrl(returnUrl);
      }
    }
  }

  void _handleInjectedMessage(String s) async {
    try {
      final obj = jsonDecode(s) as Map<String, dynamic>;
      final type = obj['type'] as String? ?? '';
      if (type == 'saveWorkFromListing') {
        final workId = obj['workId']?.toString() ?? '';
        final meta = Map<String, dynamic>.from(obj['meta'] ?? {});
        if (workId.isEmpty || meta.isEmpty) return;
        await _handleSaveFromListing(workId, meta);
      } else if (type == 'saveWorkError') {
        final id = obj['workId']?.toString() ?? '';
        final err = obj['error']?.toString() ?? 'Unknown error';
        if (mounted) _showSnackBar('Failed to save $id: $err');
      } else if (type == 'injectorLog') {
        final level = obj['level']?.toString() ?? 'info';
        final msg = obj['msg']?.toString() ?? '';
        final ctx = obj['ctx']?.toString() ?? '';
        debugPrint('[BrowseTab][injector][$level] $msg${ctx.isNotEmpty ? ' | $ctx' : ''}');
      }
    } catch (e) {
      debugPrint('Injected message parse error: $e');
    }
  }

  /// Notify the webview that a save was confirmed (user selected categories and pressed Save)
  Future<void> _confirmSaveInWebview(String workId) async {
    final js = 'if (window.__fb_confirmSave) window.__fb_confirmSave("$workId");';
    try {
      if (_isWindows && _winController != null) {
        await _winController!.executeScript(js);
      } else if (_controller != null) {
        await _controller!.runJavaScript(js);
      }
    } catch (e) {
      debugPrint('Failed to confirm save in webview: $e');
    }
  }

  /// Notify the webview that a save was cancelled (user dismissed dialog)
  Future<void> _cancelSaveInWebview(String workId) async {
    final js = 'if (window.__fb_cancelSave) window.__fb_cancelSave("$workId");';
    try {
      if (_isWindows && _winController != null) {
        await _winController!.executeScript(js);
      } else if (_controller != null) {
        await _controller!.runJavaScript(js);
      }
    } catch (e) {
      debugPrint('Failed to cancel save in webview: $e');
    }
  }

  Future<void> _handleSaveFromListing(
    String workId,
    Map<String, dynamic> meta,
  ) async {
    try {
      final work = buildWorkFromMeta(workId, meta);
      final storage = ref.read(storageProvider);
      final cats = await storage.getCategories();

      if (cats.isEmpty) {
        if (storage.getWork(workId) != null) {
          await _confirmSaveInWebview(workId);
          if (mounted) {
            _showSnackBar('“${work.title}” is already in your library.');
          }
          return;
        }
        await storage.saveWork(work);
        if (mounted) _showSnackBar('Saved “${work.title}” (default).');
        await _confirmSaveInWebview(workId);
        return;
      }

      // Get existing categories for this work (if already saved)
      final existingCategories = await storage.getCategoriesForWork(workId);
      if (!mounted) return;
      final selected = Set<String>.from(existingCategories);
      final chosen = await showDialog<Set<String>>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: Text(existingCategories.isEmpty ? 'Select categories' : 'Update categories'),
            content: SizedBox(
              width: 420,
              child: ListView(
                shrinkWrap: true,
                children: cats.map((c) {
                  final checked = selected.contains(c);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(c),
                    value: checked,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          selected.add(c);
                        } else {
                          selected.remove(c);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: selected.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, Set<String>.from(selected)),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      );

      if (chosen == null || chosen.isEmpty) {
        // User cancelled - reset the button in webview
        await _cancelSaveInWebview(workId);
        return;
      }

      // Duplicate-in-category notice: nothing actually changed.
      if (existingCategories.isNotEmpty &&
          chosen.length == existingCategories.length &&
          chosen.containsAll(existingCategories)) {
        await _confirmSaveInWebview(workId);
        if (mounted) {
          _showSnackBar('“${work.title}” is already in ${chosen.join(', ')}.');
        }
        return;
      }

      await storage.saveWork(work);
      await storage.setCategoriesForWork(work.id, chosen);
      await _confirmSaveInWebview(workId);
      if (mounted) {
        _showSnackBar('Saved “${work.title}” to ${chosen.join(', ')}.');
      }
    } catch (e) {
      debugPrint('Save from listing failed: $e');
      await _cancelSaveInWebview(workId);
      if (mounted) _showSnackBar('Failed to save from listing.');
    }
  }
}
