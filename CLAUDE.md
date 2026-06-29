# CLAUDE.md

Guidance for Claude (and humans) working in this repository.

---

## 1. Project overview

**FicBatch** is a cross‑platform (Android, iOS, Windows, macOS, Linux, Web)
Flutter app that acts as a specialized **Archive of Our Own (AO3)** browser and
reader. Core value: browse/clean AO3, build a local library, download works for
offline reading, sync to detect new chapters, and track reading progress.

- Package name: `ficbatch`
- State management: **Riverpod** (`flutter_riverpod`)
- Local storage: **Hive** (typed boxes for `Work`) + **SharedPreferences** /
  a Hive `settings_box` (untyped) for everything else (categories, history,
  updates, app settings).
- Networking: `http` + `html` parser for AO3 scraping; `webview_flutter`
  (mobile) and `webview_windows` (desktop) for the embedded browser/reader.
- Background work: `workmanager` (mobile) / an in‑app `Timer` (Windows) +
  `flutter_local_notifications`.

## 2. Repository layout

```
lib/
  main.dart                      # App entry, MaterialApp, bottom-nav scaffold (6 tabs)
  models/
    work.dart / .g.dart          # Hive typeId 1 — the central Work entity
    reading_progress.dart/.g     # Hive typeId 0 — per-work reading position
    history_entry.dart/.g        # Hive typeId 2 — NOT registered; used only as a JSON helper
  providers/
    storage_provider.dart        # storageProvider (overridden in main), workListProvider, categoriesProvider
    theme_provider.dart          # ThemeMode (light/dark only)
    navigation_provider.dart     # bottom-nav index
    browse_provider.dart         # reader-mode JS injected into the AO3 webview
  repositories/
    work_repository.dart         # addFromUrl(...) — partially superseded by services
  services/
    ao3_service.dart             # AO3 metadata fetch + HTML cleaning  (INCOMPLETE — see findings)
    storage_service.dart         # Hive/prefs facade: works, categories, history, export
    download_service.dart        # download work HTML to app docs dir
    batch_import_service.dart    # parse many URLs/IDs and import
    library_export_service.dart  # JSON export/import (versioned), auto-download flags
    sync_service.dart            # update detection, notifications, workmanager dispatcher
    work_saver.dart              # EMPTY 0-byte FILE (dead)
  tabs/
    home_tab.dart                # dashboard: streak/check-in/usage timer + batch import
    library_tab.dart             # categories as tabs, grid/list, per-work context menu
    updates_tab.dart             # detected work updates
    browse_tab.dart              # embedded AO3 webview + add-to-library
    history_tab.dart             # reading history grouped by day
    settings_tab.dart            # settings + sync/export/import + Windows sync manager
    reader_screen.dart           # the reader (online/offline, autosave, chapter nav)
    browse/                      # browse webview helpers (toolbar, search, extractors, injectors)
  widgets/
    advanced_search.dart         # AO3 advanced search form (used by browse)
    work_card.dart               # UNUSED dead widget
test/
  widget_test.dart               # BROKEN — still the default counter template
.github/workflows/               # build/release pipelines (no analyze/test gate)
```

## 3. Build, run, test

> A Flutter SDK is **not** installed in the review sandbox; the commands below
> are the canonical ones for a dev machine / CI.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # regenerate *.g.dart after model changes
flutter analyze
flutter test
flutter run -d <device>
flutter build apk --release            # Android
flutter build windows --release        # Windows
```

- Hive adapters are registered in `StorageService.init()` (typeIds 0 and 1
  only). **If you add/modify a `@HiveType`, re-run build_runner and register
  the adapter in BOTH `storage_service.dart` and the background isolate in
  `sync_service.dart`.**
- CI uses Flutter `3.32.0` (`flutter_build.yml`) and `3.38.3`
  (`build-flutter-android.yml`); both are `workflow_dispatch` only.

## 4. Conventions

- Riverpod providers live in `providers/` or are co-located with the feature
  (e.g. `readerModeProvider`, `libraryGridColumnsProvider` live in
  `settings_tab.dart`).
- `storageProvider` is a `Provider` that throws until overridden in `main.dart`
  with a constructed `StorageService` — always access storage through it.
- The untyped `settings_box` is the catch-all key/value store. Keys currently in
  use include: `categories_list`, `categories_map`, `history`, `work_updates`,
  `reader_mode`, `library_grid_columns`, `library_view_mode`, `auto_sync_*`,
  `sync_interval`, `sync_network_preference`, `last_sync_time`,
  `auto_download_categories`, `default_category`, `app_usage_seconds`,
  `check_in_streak`, `last_check_in`.
- Prefer `debugPrint` over `print`.
- Match the surrounding Material 3 widget style; most lists are
  `ListView`/`GridView` with `Card` items.

---

## 5. Review findings (state as of this review)

Grouped by severity. File references are `path:line`.

### 5.1 Bugs / correctness

1. **Broken test** — `test/widget_test.dart` is still the Flutter counter
   template referencing `MyApp` and a `+` button; the real root widget is
   `Ao3ReaderApp` (`main.dart:59`). `flutter test` will not compile.
2. **AO3 metadata extraction is incomplete** — `Ao3Service.fetchWorkMetadata`
   (`ao3_service.dart:10`) returns only `title`, `author`, `rawHtml`. But
   `BatchImportService._fetchWorkFromAo3` (`batch_import_service.dart:152`) and
   `WorkRepository.addFromUrl` (`work_repository.dart:19`) read `meta['tags']`,
   `meta['wordsCount']`, `meta['updatedAt']`, `meta['summary']`, etc. Those are
   always `null`, so imported works have **no tags, word counts, dates, stats,
   or summary** — which also weakens sync (no baseline `updatedAt`) and library
   display.
3. **`Ao3Service` sends no `User-Agent`** (`ao3_service.dart:12`). AO3 throttles
   anonymous/unidentified clients; the other services set a UA. Metadata fetches
   may be rejected.
4. **Two divergent history writers to the same `'history'` key** —
   `StorageService.addToHistory` (`storage_service.dart:257`, cap 500, schema
   `workId/title/author/accessedAt`) vs `ReaderScreen._addToHistory`
   (`reader_screen.dart:1200`, cap 100, writes `HistoryEntry.toJson` with
   chapter fields). Inconsistent caps/schema; the chapter info is never shown.
5. **Removing a work from its last category silently deletes it** —
   `StorageService.setCategoriesForWork` calls `deleteWork` when the category
   set becomes empty (`storage_service.dart:209`). Surprising and undocumented
   in the UI.
6. **Fragile sync date parsing** — `_checkWorkForUpdates` relies on
   `dd.status`/`dd.published` text being a clean ISO date
   (`sync_service.dart:279`). AO3 often renders labels/ranges, so
   `DateTime.tryParse` returns `null` and the check silently no-ops.
7. **No "System" theme** — README and `USER_SCENARIO.md` promise System/Light/
   Dark, but `ThemeNotifier` only stores light/dark (`theme_provider.dart:16`)
   and Settings offers two options (`settings_tab.dart:576`).

### 5.2 Dead / duplicated code

8. `lib/services/work_saver.dart` is an empty 0-byte file.
9. `lib/widgets/work_card.dart` (`WorkCard`) is never referenced.
10. `HistoryEntryAdapter` (Hive typeId 2) is generated but never registered;
    history is persisted as JSON maps, so the adapter is dead.
11. `StorageService.exportToJson/importFromJson/exportToOpds`
    (`storage_service.dart:56`) duplicate `LibraryExportService`. Two export
    paths; OPDS export is not surfaced anywhere.

### 5.3 Missing features (promised in README / USER_SCENARIO.md)

12. **Onboarding** (scenario 1): no 3-step guide, no initial folder pick, no
    permission flow.
13. **User-selectable / re-pickable download folder** (scenario 14): downloads
    are hardcoded to the app documents dir (`download_service.dart:12`); no
    `file_picker`. Export/import require pasting JSON or typing a path
    (`settings_tab.dart:384`).
14. **Library search / sort / multi-select** (scenario 4): the Library tab has
    no search bar, no sort (title / last read / favorites), and no multi-select
    bulk move/download/delete. Only a grid/list toggle (in Settings).
15. **Favorites UI** (scenario 5): `Work.isFavorite` exists but there is no star
    toggle, no "Favorites First" sort, no pinning anywhere in the UI.
16. **Reader settings** (scenario 13): "Font & Reader Settings" is a
    "coming soon" snackbar (`settings_tab.dart:826`). No line height, reading
    theme/sepia, font family, or chapter-jump toggle surfaced in Settings.
17. **Downloads settings**: no global auto-download toggle, throttle-delay
    selector, "Clear all downloads" (service exists at
    `download_service.dart:143` but is unwired), or re-pick folder.
18. **Data settings**: no "Reset app data" or "Clear download history".
19. **Android 13+ notifications**: `AndroidManifest.xml` lacks
    `POST_NOTIFICATIONS`; there is no runtime permission request; workmanager
    lacks `RECEIVE_BOOT_COMPLETED`. Update notifications likely never appear on
    modern Android.

### 5.4 Engineering / infra

20. **No quality gate in CI** — workflows only build/release on
    `workflow_dispatch`; there is no `flutter analyze` / `flutter test` on PRs.
21. **No real tests** beyond the broken template. Pure logic
    (`BatchImportService.parseWorkIds`, `Work`/`ReadingProgress` JSON round-trip,
    `ImportResult.toSummary`) is trivially unit-testable.
22. **Dependency friction** — `http: ^0.13.5` is old; analyzer is pinned with a
    CI "downgrade workaround" (`build-flutter-android.yml`).
23. **Deprecations** — widespread `Color.withOpacity` (deprecated for
    `withValues`) and `print` in `migrateHive` (`storage_service.dart:348`)
    will spam `flutter analyze` on newer SDKs.
24. **`CURRENT_ERRORS.md` is an empty placeholder.**
25. **Background isolate divergence** — `sync_service.callbackDispatcher`
    re-opens Hive boxes directly and never runs `StorageService.init()`/
    `migrateHive`, so migrations/prefs aren't applied in background.

---

## 6. Roadmap

Phased by priority. Each phase is independently shippable.

### Phase 0 — Correctness & hygiene (do first)
- Fix or replace `test/widget_test.dart` so the suite compiles.
- Complete `Ao3Service.fetchWorkMetadata` to extract tags, summary, word/chapter
  counts, kudos/hits/comments, and published/updated dates; add a `User-Agent`.
- Unify the two history writers into a single `StorageService` method with one
  schema and cap.
- Delete dead files (`work_saver.dart`, `work_card.dart` if unused) and reconcile
  the duplicate export paths.
- Add a CI workflow that runs `flutter analyze` + `flutter test` on push/PR.

### Phase 1 — Core reading & library UX
- Library tab: search bar, sort menu (title / last read / favorites), and
  multi-select bulk actions (move / download / delete).
- Favorites: star toggle on cards + "Favorites First" sort.
- Reader settings dialog (font size, line height, reading theme incl. sepia,
  font family, chapter-jump toggle) wired into `reader_screen` and persisted.
- Theme: add System mode end-to-end.

### Phase 2 — Downloads, storage & sync robustness
- `file_picker`-based folder selection + re-pick, with reference migration.
- Downloads settings (auto-download toggle, throttle selector, clear-all).
- Native file-based export/import (replace the JSON paste box).
- Android 13+ notification permission + manifest fixes; verify workmanager
  reschedules after reboot.
- Harden sync date parsing against real AO3 markup.

### Phase 3 — Onboarding & polish
- First-run onboarding (purpose, features, folder pick, permissions).
- Duplicate-in-category notice on add-to-library.
- "Reset app data" / "Clear download history" in Settings.
- Resolve `withOpacity`/`print` deprecations.

### Phase 4 — Testing & infra hardening
- Unit tests for parsing/serialization/import-merge logic.
- Widget tests for the main tabs.
- Consolidate CI Flutter versions; drop the analyzer downgrade workaround;
  modernize `http`.

---

## 7. TODO checklist

Phase 0
- [ ] Replace broken `test/widget_test.dart`
- [ ] Complete `Ao3Service` metadata extraction + add User-Agent
- [ ] Unify history writers
- [ ] Remove `work_saver.dart` and unused `work_card.dart`
- [ ] Reconcile `StorageService` vs `LibraryExportService` export paths
- [ ] Add `flutter analyze` + `flutter test` CI workflow

Phase 1
- [ ] Library search bar
- [ ] Library sort menu
- [ ] Library multi-select bulk actions
- [ ] Favorites star toggle + sort
- [ ] Reader settings dialog (font/line-height/theme/font-family/chapter-jump)
- [ ] Theme System mode

Phase 2
- [ ] Download folder picker + re-pick
- [ ] Downloads settings section
- [ ] Native file export/import
- [ ] Android 13+ notification permission + manifest
- [ ] Robust sync date parsing

Phase 3
- [ ] Onboarding flow
- [ ] Duplicate-in-category notice
- [ ] Reset app data / clear download history
- [ ] Fix deprecations

Phase 4
- [ ] Unit tests for core logic
- [ ] Widget tests for tabs
- [ ] CI version cleanup + dependency modernization

---

## 8. Iterative question workflow

This repo uses a question-driven iteration loop:

1. Each iteration, the active questions live in `question_N.md` (currently
   `question_1.md`). **The user edits that file** to set priorities and answer
   open decisions.
2. On the user's next commit, Claude reads the edited `question_N.md`,
   **implements** the agreed work, then **renames the file to
   `question_N_done.md`**.
3. `*_done.md` files are **closed** — do not re-read or re-open them in future
   iterations.
4. After finishing, Claude creates the next `question_{N+1}.md` with the next
   round of decisions and updates the TODO checklist above.

> When implementing, keep this file's findings/roadmap/TODOs in sync with what
> actually ships.
