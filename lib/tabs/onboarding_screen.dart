import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/storage_provider.dart';

/// Minimal first-run welcome screen: one page covering the core features,
/// dismissed with "Get Started". Shown once (tracked by the
/// `onboarding_complete` settings key) and replayable from Settings.
class OnboardingScreen extends ConsumerWidget {
  /// Called after the user taps "Get Started" and the flag is persisted.
  final VoidCallback onDone;

  const OnboardingScreen({super.key, required this.onDone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(Icons.auto_stories, size: 64, color: colorScheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome to FicBatch',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your AO3 browser, library and offline reader.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 32),
                  _feature(
                    context,
                    Icons.library_books,
                    'Library',
                    'Organize works into categories, search, sort and favorite them.',
                  ),
                  _feature(
                    context,
                    Icons.language,
                    'Browse & save',
                    'Browse AO3 in the Browse tab and add works to your library with one tap.',
                  ),
                  _feature(
                    context,
                    Icons.chrome_reader_mode,
                    'Read',
                    'A distraction-free reader that remembers your chapter and position.',
                  ),
                  _feature(
                    context,
                    Icons.download,
                    'Download',
                    'Save works for offline reading — singly, per category, or automatically.',
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed: () async {
                      final storage = ref.read(storageProvider);
                      await storage.settingsBox.put('onboarding_complete', true);
                      onDone();
                    },
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Get Started'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _feature(
      BuildContext context, IconData icon, String title, String body) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 28, color: theme.colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
