# FicBatch v0.7.6

Iteration 9: a library you can slice, series that finally exist, updates
that fetch themselves, and an undo button for your whole library.

## ✨ New

- **Library filters** — chips under the search bar for Downloaded /
  Favorites / Has update / Completed / In progress, plus a tag picker
  (every tag in your library, most-used first, searchable). Filters stack
  with search and any category tab.
- **Series** — works now know their series: cards show "Series · Part N",
  and the new Series sort groups a series together in reading order.
  Existing works pick their series up on the next sync.
- **Auto-download updates** — when sync finds new chapters for a work in an
  auto-download category (or the global toggle is on), the fresh copy
  downloads itself; you just see it ready in Updates.
- **Backups** — the app keeps its last five library snapshots, taken
  automatically before imports, syncs and resets. Settings → Backups lists
  them with one-tap restore — and restoring backs up the current state
  first, so even a restore is undoable.
- **Cleaner reading** — the reader's floating buttons hide while you
  scroll and fade back when you stop.

**Notes:** notifications need Android 13+; folder sync asks for "All files
access"; iOS build requires iOS 14+.
