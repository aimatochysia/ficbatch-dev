# CLAUDE.md

Guidance for Claude (and humans) working in this repository.

---

## 1. Project overview

**FicBatch** is a cross‑platform (Android, iOS, Windows, macOS, Linux)
Flutter app that acts as a specialized **Archive of Our Own (AO3)** browser and
reader. (Web support was removed in iteration 4.5 — the app's value is the
local library/offline reading, which a browser tab can't provide.) Core value: browse/clean AO3, build a local library, download works for
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
  hive_registrar.g.dart          # generated adapter-registration extension
  models/
    work.dart / .g.dart          # Hive typeId 1 — the central Work entity
    reading_progress.dart/.g     # Hive typeId 0 — per-work reading position
  providers/
    storage_provider.dart        # storageProvider + syncFolderProvider (overridden in main), work/category streams
    theme_provider.dart          # ThemeMode (system/light/dark) + AppColorTheme seeds
    navigation_provider.dart     # bottom-nav index
  services/
    ao3_service.dart             # AO3 metadata fetch (full) + HTML cleaning
    storage_service.dart         # Hive/prefs facade: works, categories, history
    download_service.dart        # DownloadResult downloads, folder config, jitter
    batch_import_service.dart    # parse many URLs/IDs and import
    library_export_service.dart  # JSON export/import v2 (works+history), merge logic
    sync_service.dart            # update detection, notifications, workmanager dispatcher
    sync_folder_service.dart     # cross-device sync via a watched folder
    lan_sync_service.dart        # auto-sync between devices on one LAN (UDP+TCP)
    update_service.dart          # GitHub latest-release check (in-app updates)
    backup_service.dart          # rolling library snapshots (5) + restore
  tabs/
    home_tab.dart                # dashboard: streak/check-in/usage timer + batch import
    library_tab.dart             # categories as tabs, grid/list, per-work context menu
    updates_tab.dart             # detected work updates
    browse_tab.dart              # embedded AO3 webview + add-to-library
    history_tab.dart             # reading history grouped by day
    settings_tab.dart            # settings + sync/export/import + Windows sync manager
    reader_screen.dart           # the reader (online/offline, autosave, repair, themes)
    onboarding_screen.dart       # first-run welcome (replayable from Settings)
    browse/                      # browse webview helpers (toolbar, search, extractors, injector loader)
  widgets/
    advanced_search.dart         # AO3 advanced search form (used by browse)
assets/js/listing_buttons.js     # the injected listing-save script (tested in tools/js-tests)
test/                            # unit + widget + Hive round-trip tests
tools/js-tests/                  # Node+jsdom DOM tests for the injector (CI job)
.github/workflows/               # ci.yml (auto), artifacts + releases (manual dispatch)
```

## 3. Build, run, test

> **Flutter on Claude Code on the web:** a SessionStart hook
> (`.claude/hooks/session-start.sh`) auto-installs Flutter **3.44.4** (Dart
> 3.12.2, matching `sdk: ^3.12.0`) to `/opt/flutter` and runs `flutter pub
> get` at session start, so `flutter analyze` / `flutter test` /
> `build_runner` work in remote sessions. The download happens at most once
> per cached container image. On a dev machine use a local Flutter 3.44.x.

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # regenerate *.g.dart after model changes
flutter analyze
flutter test
flutter run -d <device>
flutter build apk --release            # Android
flutter build windows --release        # Windows
```

- Storage uses **hive_ce** (the maintained community fork of hive; drop-in
  compatible with existing hive 2.x boxes — migrated in iteration 4 because
  `hive_generator` capped analyzer <7 and hung on Dart 3.12). Adapters are
  registered in `StorageService.init()` (typeIds 0 and 1 only). **If you
  add/modify a `@HiveType`, re-run build_runner and register the adapter in
  BOTH `storage_service.dart` and the background isolate in
  `sync_service.dart`** (a generated `lib/hive_registrar.g.dart` extension is
  also available).
- All CI/build workflows pin Flutter `3.44.4`. `ci.yml` (analyze + test +
  js-dom-tests) runs on every push; `iteration-artifacts.yml`,
  `flutter_build.yml` (full release; takes a `release_tag` input) and
  `build-flutter-android.yml` are manual `workflow_dispatch` **by user
  request — never trigger builds/releases without being asked**.
- **Versioning is automated per build run**: every `flutter_build.yml` /
  `iteration-artifacts.yml` run bumps `pubspec.yaml` locally (patch and build
  number +1, e.g. `0.7.1+5` → `0.7.2+6`); a `release_tag` of `auto` becomes
  `v<bumped version>`, an explicit `vX.Y.Z` tag drives the version instead.
  The release job verifies **all five** platform files exist and are
  non-empty, and only then commits the bump back to the source branch — so
  the repo version always equals the last complete release, and a partial
  release can be re-run reusing the same version/tag. Don't hand-bump the
  version for a release anymore.
- `retag.yml` is a maintenance utility that points a tag at a commit by
  round-tripping through the releases API (GITHUB_TOKEN can't touch tag refs
  whose target changes workflow files vs main). Trigger it by editing
  `.github/retag.json` and pushing; `flutter_build.yml` now passes
  `target_commitish` so release tags land on the built commit, not main.

## 4. Conventions

- Riverpod providers live in `providers/` or are co-located with the feature
  (e.g. `readerModeProvider`, `libraryGridColumnsProvider` live in
  `settings_tab.dart`).
- `storageProvider` is a `Provider` that throws until overridden in `main.dart`
  with a constructed `StorageService` — always access storage through it.
- The untyped `settings_box` is the catch-all key/value store. Keys currently in
  use include: `categories_list`, `categories_map`, `history`, `work_updates`,
  `reader_mode`, `reader_settings`, `library_grid_columns`,
  `library_view_mode`, `auto_sync_*`, `sync_interval`,
  `sync_network_preference`, `last_sync_time`, `auto_download_categories`,
  `auto_download_global`, `download_dir`, `download_throttle_ms`,
  `default_category`, `app_usage_seconds`, `check_in_streak`, `last_check_in`,
  `sync_folder_*`, `lan_sync_*` (enabled/code/device_name/last_run/last_peer),
  `update_check_enabled`, `last_auto_backup`.
- Prefer `debugPrint` over `print`.
- Match the surrounding Material 3 widget style; most lists are
  `ListView`/`GridView` with `Card` items.

---

## 5. Review findings (state as of this review)

> **Iterations 1 + 2 (Phase 0, 1 and 2) are implemented** on
> `claude/flutter-review-roadmap-160ll5`. The findings below describe the
> *original* state; see §7 for exactly what shipped. Done so far: Phase 0
> items 1–5, 7–11, 20; Phase 1 items 14–16 + System theme; Phase 2 items 6,
> 13, 17, 19, 23 (folder picker, downloads settings, native import/export,
> Android notifications, sync hardening, `withOpacity` sweep). A local
> Flutter SDK + SessionStart hook now make `flutter analyze`/`test` run in
> web sessions. Remaining open items live in §7 Phase 3–4 and `question_3.md`.

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

Phase 0 — **done (iteration 1)**
- [x] Replace broken `test/widget_test.dart` (now real unit tests for parsing/serialization/summaries)
- [x] Complete `Ao3Service` metadata extraction + add User-Agent
- [x] Unify history writers (single `StorageService.addToHistory`, records chapter info)
- [x] Remove `work_saver.dart`, unused `work_card.dart`, and dead `HistoryEntry`
- [x] Reconcile `StorageService` vs `LibraryExportService` export paths (removed the old one)
- [x] Add `flutter analyze` + `flutter test` CI workflow (`.github/workflows/ci.yml`)
- [x] Bonus: keep works on empty category (no silent delete); `print` → `debugPrint`

Phase 1 — **done (iteration 1)**
- [x] Library search bar
- [x] Library sort menu (recently added / title / last read / word count / favorites first)
- [x] Library multi-select bulk actions (move / download / remove + select-all)
- [x] Favorites star toggle + "Favorites first" sort
- [x] Reader settings dialog (font size / line height / font family / sepia / chapter-jump) wired into the reader and Settings
- [x] Theme System mode end-to-end

Phase 2 — **done (iteration 2)**
- [x] Download folder picker + re-pick (desktop; mobile keeps the sandboxed app dir) via `file_picker`, with migration
- [x] Downloads settings section (global auto-download toggle, throttle selector, clear-all)
- [x] Native file export/import (save/open dialogs; paste box kept as hidden fallback)
- [x] Android 13+ notification permission + manifest (`POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `WAKE_LOCK`) via `permission_handler`
- [x] Robust sync date parsing — `SyncService` now uses `Ao3Service` and refreshes the full metadata baseline

Phase 3 — **done (iteration 3)**
- [x] Onboarding flow (minimal welcome screen, `onboarding_complete` flag, replay in Settings)
- [x] Duplicate-in-category notice (both browse save paths; batch import reports via summary)
- [x] Fix deprecations (`withOpacity` → `withValues`) — done in iteration 2
- [x] Reset app data (typed confirm) / Clear reading history in Settings
- [x] Bonus: browse webview reveal-early + spinner + load watchdog (fixes slow/blank screen);
      auto-build artifacts workflow (`iteration-artifacts.yml`); version bump 1.1.0+2

Phase 4 — **done (iteration 4)**
- [x] Unit tests for core logic (parsing/serialization/summaries/history merge)
- [x] Widget tests started (onboarding) + on-disk Hive round-trip test
- [x] JS injection testing: injector extracted to `assets/js/listing_buttons.js`,
      tested headlessly via `tools/js-tests` (Node + jsdom, portrait & landscape) in CI
- [x] CI version cleanup + dependency modernization — Flutter 3.44.4/Dart 3.12,
      http 1.x, webview_flutter 4.14, notifications 19, `xml` dropped, analyzer
      workaround removed, **hive → hive_ce** (old hive_generator can't run on Dart 3.12)
- [x] Flutter SDK + SessionStart hook so analyze/test run in web sessions
- [x] Cross-device sync v1: **sync-folder mode** (`SyncFolderService`, export format v2
      with history) — see `docs/research/pears_p2p_sync.md` (incl. the Rust/iroh addendum)
- [x] Release prep: v1.2.0+3, `RELEASE_NOTES.md` wired into `flutter_build.yml`

Iteration 5 — **done**
- [x] Android sync folder (all-files access + picker; hourly periodic sync for debug)
- [x] Placeholder-metadata repair (reader saves base on stored record; repair on
      open + during sync; root cause: browse quick-open placeholders)
- [x] Mouse click-through shield for browse popup menus (Android + mouse)
- [x] Randomized AO3 request jitter everywhere + 429 abort in bulk downloads
- [x] Hide required-tags inner text; dark mode nav links lose boxed backgrounds
- [x] App color themes (7 M3 seeds) + reading themes (sepia/night/gray/paper)
- [x] History live-updates + reader writes history on close; download errors
      surfaced with reasons (DownloadResult)
- [x] Artifact builds manual-only; releases only on user request; v1.3.0+4

Iteration 6 — **done**
- [x] Dead-code sweep (~500 lines: work_repository, browse_provider,
      ao3_list_injector, unused providers/members, superseded browse_tab methods)
- [x] RadioGroup migration (last deprecated API) + 22 automated lint fixes
      (12 `use_build_context_synchronously` infos remain)
- [x] Widget tests for History/Updates/Library tabs (real Hive store,
      writes via tester.runAsync)
- [x] Release v0.7.1 (tag input added to flutter_build.yml; version 0.7.1+5)

Iteration 7 — **done**
- [x] Sync-folder verdict: works — hourly cadence kept
- [x] LAN auto-sync v1 (`LanSyncService`: UDP discovery + TCP export-v2
      exchange, pairing code, Settings section, iOS local-network plist,
      socket tests)
- [x] Text-anchored bookmarks: mid-screen anchor capture (mobile + Windows),
      manual bookmark FAB with instant save, normalized-text restore
      centered on screen (online/offline alignment)
- [x] Back-press exit confirmation on mobile (PopScope at nav root)
- [x] 5 new app color themes (Sakura/Mint/Indigo/Coral/Olive)
- [x] Last 12 `use_build_context_synchronously` lints — `flutter analyze`
      fully clean
- [x] Release v0.7.3 (auto-versioned 0.7.3+7)

Iteration 8 — **done**
- [x] Red bookmark dot in the left margin + jump-to-bookmark FAB (shared
      anchor-matching JS helper)
- [x] LAN sync v2: live nearby-device list in Settings (tap to sync) +
      downloaded-work file transfer in the handshake (25/pass, numeric-id
      validated, back-compatible with v0.7.3 peers); persistent per-socket
      line reader
- [x] In-app update check on all platforms (`UpdateService` +
      `showUpdatePrompt`; launch check toggleable via `update_check_enabled`,
      manual check in Settings; package_info_plus)
- [x] Windows installer: New Folder button (Inno `BrowseForFolder` override)
- [x] Release v0.7.5 (explicit tag; auto-versioned 0.7.5+8)

Iteration 9 — **done** (picked from the ideation catalog in chat)
- [x] Library filter chips (Downloaded/Favorites/Has update/Completed/
      In progress + searchable tag picker; AND-combined with search)
- [x] Series support end-to-end (parser incl. the package:html compound-
      selector workaround, Work Hive fields 21–23, batch import + sync
      fill-in, card display + Series sort; parser & round-trip tests)
- [x] Auto-download on detected updates (global toggle or auto-download
      categories; 429 backs off; works in the background isolate)
- [x] Rolling backups (`BackupService`, 5 snapshots, auto before imports/
      resets — merge-imports throttled 6h; Settings list + restore)
- [x] Reader floating buttons auto-hide while scrolling
- Held per user: Home continue-reading card, reading statuses, EPUB export,
  restricted-works cookies

Iteration 10 candidates (see `question_10.md`)
- [ ] User's testing feedback (filters, series, backups, auto-download)

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
