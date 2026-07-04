import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/storage_provider.dart';
import '../services/download_service.dart';
import '../services/library_export_service.dart';
import '../services/sync_service.dart';
import '../models/work.dart';
import 'reader_screen.dart';
import 'settings_tab.dart' show libraryGridColumnsProvider, libraryViewModeProvider, LibraryViewMode;

/// Sort options for the library grid/list.
enum LibrarySort {
  recentlyAdded('Recently added'),
  titleAsc('Title (A–Z)'),
  lastRead('Last read'),
  wordCount('Word count'),
  favoritesFirst('Favorites first');

  final String label;
  const LibrarySort(this.label);
}

class LibraryTab extends ConsumerStatefulWidget {
  const LibraryTab({super.key});

  @override
  ConsumerState<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends ConsumerState<LibraryTab> {
  bool _isDownloading = false;
  String _downloadProgress = '';
  bool _isSyncing = false;

  // Search / sort / multi-select state.
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  LibrarySort _sortMode = LibrarySort.recentlyAdded;
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Filter the supplied works by the current search query, then sort them by
  /// the active sort mode. Pure transformation used for whatever category is
  /// being displayed.
  List<Work> _applySearchAndSort(List<Work> works) {
    final query = _searchQuery.trim().toLowerCase();
    var result = works;
    if (query.isNotEmpty) {
      result = works.where((w) {
        if (w.title.toLowerCase().contains(query)) return true;
        if (w.author.toLowerCase().contains(query)) return true;
        return w.tags.any((t) => t.toLowerCase().contains(query));
      }).toList();
    } else {
      result = List<Work>.from(works);
    }

    int byDateDesc(DateTime? a, DateTime? b) {
      if (a == null && b == null) return 0;
      if (a == null) return 1;
      if (b == null) return -1;
      return b.compareTo(a);
    }

    switch (_sortMode) {
      case LibrarySort.recentlyAdded:
        result.sort((a, b) => byDateDesc(a.userAddedDate, b.userAddedDate));
        break;
      case LibrarySort.titleAsc:
        result.sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case LibrarySort.lastRead:
        result.sort((a, b) => byDateDesc(
            a.readingProgress.lastReadAt ?? a.lastUserOpened,
            b.readingProgress.lastReadAt ?? b.lastUserOpened));
        break;
      case LibrarySort.wordCount:
        result.sort((a, b) => (b.wordsCount ?? 0).compareTo(a.wordsCount ?? 0));
        break;
      case LibrarySort.favoritesFirst:
        result.sort((a, b) {
          if (a.isFavorite == b.isFavorite) {
            return byDateDesc(a.userAddedDate, b.userAddedDate);
          }
          return a.isFavorite ? -1 : 1;
        });
        break;
    }
    return result;
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelect(String workId) {
    setState(() {
      if (_selectedIds.contains(workId)) {
        _selectedIds.remove(workId);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.add(workId);
      }
    });
  }

  List<Work> _selectedWorks(List<Work> all) =>
      all.where((w) => _selectedIds.contains(w.id)).toList();

  Future<void> _bulkDelete(List<Work> all) async {
    final selected = _selectedWorks(all);
    if (selected.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Works'),
        content: Text('Remove ${selected.length} work(s) from your library?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (confirm != true) return;
    final storage = ref.read(storageProvider);
    for (final w in selected) {
      await storage.deleteWork(w.id);
    }
    if (mounted) {
      _exitSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed ${selected.length} work(s)')),
      );
    }
  }

  Future<void> _bulkDownload(List<Work> all) async {
    final selected = _selectedWorks(all);
    if (selected.isEmpty) return;
    _exitSelection();
    await _downloadCategory('selection', selected);
  }

  Future<void> _bulkMove(List<Work> all) async {
    final selected = _selectedWorks(all);
    if (selected.isEmpty) return;
    final storage = ref.read(storageProvider);
    final allCats = List<String>.from(await storage.getCategories());
    final chosen = <String>{};
    final newCatCtrl = TextEditingController();

    if (!mounted) return;
    final apply = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Move ${selected.length} work(s) to…'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (allCats.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No categories yet. Add one below.'),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: allCats.map((c) {
                      return CheckboxListTile(
                        dense: true,
                        title: Text(c),
                        value: chosen.contains(c),
                        onChanged: (v) => setDialogState(() {
                          if (v == true) {
                            chosen.add(c);
                          } else {
                            chosen.remove(c);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newCatCtrl,
                        decoration: const InputDecoration(
                            labelText: 'New category', isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final name = newCatCtrl.text.trim();
                        if (name.isEmpty) return;
                        await storage.addCategory(name);
                        setDialogState(() {
                          allCats.add(name);
                          chosen.add(name);
                          newCatCtrl.clear();
                        });
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Move')),
          ],
        ),
      ),
    );
    newCatCtrl.dispose();
    if (apply != true) return;

    for (final w in selected) {
      await storage.setCategoriesForWork(w.id, Set<String>.from(chosen));
    }
    if (mounted) {
      _exitSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Moved ${selected.length} work(s) to ${chosen.isEmpty ? 'no category' : chosen.join(', ')}')),
      );
    }
  }

  Future<void> _syncCategory(String category, List<Work> works) async {
    if (_isSyncing || works.isEmpty) return;
    
    setState(() => _isSyncing = true);
    
    try {
      final syncService = SyncService();
      final updates = await syncService.performSync();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(updates.isEmpty 
                ? 'No updates found in $category' 
                : 'Found ${updates.length} update(s)'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }
  
  Future<void> _downloadWork(Work work) async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 'Downloading ${work.title}...';
    });
    
    try {
      final result = await DownloadService.downloadWork(work.id);

      if (result.isSuccess) {
        // Update work status in storage
        final storage = ref.read(storageProvider);
        final updatedWork = work.copyWith(
          isDownloaded: true,
          downloadedAt: DateTime.now(),
        );
        await storage.saveWork(updatedWork);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Downloaded "${work.title}"')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Download failed: ${result.error} — "${work.title}"'),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = '';
        });
      }
    }
  }
  
  Future<void> _downloadCategory(String category, List<Work> works) async {
    if (works.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No works to download in this category')),
      );
      return;
    }
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download Category'),
        content: Text('Download ${works.length} work(s) from "$category"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    setState(() {
      _isDownloading = true;
      _downloadProgress = 'Starting download...';
    });
    
    try {
      int downloaded = 0;
      int failed = 0;
      String? lastError;
      final throttleRaw = ref
          .read(storageProvider)
          .settingsBox
          .get('download_throttle_ms', defaultValue: 1000);
      final throttleMs = throttleRaw is int ? throttleRaw : 1000;

      for (int i = 0; i < works.length; i++) {
        final work = works[i];
        
        if (mounted) {
          setState(() {
            _downloadProgress = 'Downloading ${i + 1}/${works.length}: ${work.title}';
          });
        }
        
        final result = await DownloadService.downloadWork(work.id);

        if (result.isSuccess) {
          downloaded++;
          // Update work status
          final storage = ref.read(storageProvider);
          final updatedWork = work.copyWith(
            isDownloaded: true,
            downloadedAt: DateTime.now(),
          );
          await storage.saveWork(updatedWork);
        } else {
          failed++;
          lastError = result.error;
          // Rate-limited: hammering on is counterproductive — stop the batch.
          if ((result.error ?? '').contains('429')) {
            failed += works.length - i - 1;
            break;
          }
        }

        // Throttle downloads (configurable base in Settings → Downloads,
        // plus random jitter to stay gentle on AO3)
        if (i < works.length - 1) {
          await Future.delayed(DownloadService.jitteredDelay(throttleMs));
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Downloaded $downloaded work(s)${failed > 0 ? ', $failed failed (${lastError ?? 'unknown'})' : ''}'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = '';
        });
      }
    }
  }

  Future<void> _showCategoryOptionsDialog(String category, List<Work> works) async {
    final storage = ref.read(storageProvider);
    final exportService = LibraryExportService(storage);
    final isAutoDownload = await exportService.isCategoryAutoDownload(category);
    
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Category: $category'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download All'),
                subtitle: Text('${works.length} work(s)'),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadCategory(category, works);
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.sync),
                title: const Text('Auto-Download'),
                subtitle: const Text('Download new/updated works'),
                value: isAutoDownload,
                onChanged: (value) async {
                  await exportService.setCategoryAutoDownload(category, value);
                  setDialogState(() {});
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editCategoriesForWork(BuildContext context, String workId) async {
    final storage = ref.read(storageProvider);
    final allCats = List<String>.from(await storage.getCategories());
    final selected = Set<String>.from(await storage.getCategoriesForWork(workId));
    if (!context.mounted) return;
    final newCatCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Categories'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (allCats.isEmpty)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('No categories yet. Add one below.'),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: allCats.map((c) {
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
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: newCatCtrl,
                        decoration: const InputDecoration(
                          labelText: 'New category',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        final name = newCatCtrl.text.trim();
                        if (name.isEmpty) return;
                        await storage.addCategory(name);
                        setState(() {
                          allCats.add(name);
                          selected.add(name);
                          newCatCtrl.clear();
                        });
                      },
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                await storage.setCategoriesForWork(workId, selected);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    newCatCtrl.dispose();
  }

  Future<void> _showAddCategoryDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Category'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Category Name',
            hintText: 'Enter category name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final storage = ref.read(storageProvider);
      await storage.addCategory(result);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Added category "$result"')),
        );
      }
    }
    controller.dispose();
  }

  Future<void> _showManageCategoriesDialog(BuildContext context) async {
    final storage = ref.read(storageProvider);
    final cats = await storage.getCategories();

    if (cats.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No categories to manage')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Manage Categories'),
          content: SizedBox(
            width: 400,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: cats.length,
              itemBuilder: (context, index) {
                final cat = cats[index];
                return ListTile(
                  title: Text(cat),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () async {
                          final controller = TextEditingController(text: cat);
                          final newName = await showDialog<String>(
                            context: context,
                            builder: (ctx2) => AlertDialog(
                              title: const Text('Rename Category'),
                              content: TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                  labelText: 'New Name',
                                ),
                                autofocus: true,
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx2),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx2, controller.text.trim()),
                                  child: const Text('Rename'),
                                ),
                              ],
                            ),
                          );
                          controller.dispose();

                          if (newName != null && newName.isNotEmpty && newName != cat) {
                            await storage.renameCategory(cat, newName);
                            setState(() {
                              cats[index] = newName;
                            });
                          }
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete),
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx2) => AlertDialog(
                              title: const Text('Delete Category'),
                              content: Text('Delete category "$cat"? Works will not be deleted.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx2, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx2, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );

                          if (confirm == true) {
                            await storage.deleteCategory(cat);
                            setState(() {
                              cats.removeAt(index);
                            });
                          }
                        },
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSortCategoriesDialog(BuildContext context) async {
    final storage = ref.read(storageProvider);
    var cats = List<String>.from(await storage.getCategories());

    if (cats.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No categories to sort')),
        );
      }
      return;
    }
    if (!context.mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Sort Categories'),
          content: SizedBox(
            width: 400,
            child: ReorderableListView.builder(
              shrinkWrap: true,
              itemCount: cats.length,
              // onReorderItem (3.41+) pre-adjusts newIndex for the removal.
              onReorderItem: (oldIndex, newIndex) {
                setState(() {
                  final item = cats.removeAt(oldIndex);
                  cats.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final cat = cats[index];
                return ListTile(
                  key: ValueKey(cat),
                  leading: const Icon(Icons.drag_handle),
                  title: Text(cat),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                // Save the new order
                await storage.settingsBox.put('categories_list', cats);
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Categories reordered')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final worksAsync = ref.watch(workListProvider);
    final catsAsync = ref.watch(categoriesProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: catsAsync.when(
          data: (cats) {
            final tabs = <String>['All', ...cats];
            return DefaultTabController(
              length: tabs.length,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_selectionMode)
                    _buildSelectionBar(
                      worksAsync.maybeWhen(
                        data: (w) => w,
                        orElse: () => const <Work>[],
                      ),
                    )
                  else
                    Row(
                      children: [
                        const Text('Library',
                            style: TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) async {
                            if (value == 'add') {
                              await _showAddCategoryDialog(context);
                            } else if (value == 'manage') {
                              await _showManageCategoriesDialog(context);
                            } else if (value == 'sort') {
                              await _showSortCategoriesDialog(context);
                            } else if (value == 'select') {
                              setState(() => _selectionMode = true);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'select',
                              child: Row(children: [
                                Icon(Icons.checklist),
                                SizedBox(width: 8),
                                Text('Select Works'),
                              ]),
                            ),
                            const PopupMenuItem(
                              value: 'add',
                              child: Row(children: [
                                Icon(Icons.add),
                                SizedBox(width: 8),
                                Text('Add Category'),
                              ]),
                            ),
                            const PopupMenuItem(
                              value: 'manage',
                              child: Row(children: [
                                Icon(Icons.edit),
                                SizedBox(width: 8),
                                Text('Manage Categories'),
                              ]),
                            ),
                            const PopupMenuItem(
                              value: 'sort',
                              child: Row(children: [
                                Icon(Icons.sort),
                                SizedBox(width: 8),
                                Text('Sort Categories'),
                              ]),
                            ),
                          ],
                        ),
                      ],
                    ),
                  // Search + sort row
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              isDense: true,
                              prefixIcon: const Icon(Icons.search, size: 20),
                              hintText: 'Search title, author or tag',
                              border: const OutlineInputBorder(),
                              suffixIcon: _searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      icon: const Icon(Icons.clear, size: 18),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                    ),
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<LibrarySort>(
                          icon: const Icon(Icons.sort),
                          tooltip: 'Sort: ${_sortMode.label}',
                          initialValue: _sortMode,
                          onSelected: (m) => setState(() => _sortMode = m),
                          itemBuilder: (context) => LibrarySort.values
                              .map((m) => PopupMenuItem(
                                    value: m,
                                    child: Row(
                                      children: [
                                        Icon(
                                          m == _sortMode
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_unchecked,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(m.label),
                                      ],
                                    ),
                                  ))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  // Download progress indicator
                  if (_isDownloading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(_downloadProgress, style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  TabBar(
                    isScrollable: true,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 12),
                    tabs: tabs.map((c) {
                      // Wrap each tab in a GestureDetector for long-press download
                      return GestureDetector(
                        onLongPress: c == 'All' ? null : () {
                          // Get works for this category and show download dialog
                          _showCategoryLongPressMenu(context, c);
                        },
                        child: Tab(text: c),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TabBarView(
                      children: tabs.map((cat) {
                        return worksAsync.when(
                          loading: () => const Center(child: CircularProgressIndicator()),
                          error: (e, _) => Center(child: Text('Error: $e')),
                          data: (allWorks) {
                            if (cat == 'All') {
                              return _buildCategoryContent(cat, allWorks, allWorks);
                            }
                            final idsAsync = ref.watch(categoryWorksProvider(cat));
                            return idsAsync.when(
                              loading: () => const Center(child: CircularProgressIndicator()),
                              error: (e, _) => Center(child: Text('Error: $e')),
                              data: (ids) {
                                final filtered = allWorks.where((w) => ids.contains(w.id)).toList();
                                return _buildCategoryContent(cat, filtered, allWorks);
                              },
                            );
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
        ),
      ),
    );
  }
  
  Future<void> _showCategoryLongPressMenu(BuildContext context, String category) async {
    // Get works for this category
    final storage = ref.read(storageProvider);
    final ids = await storage.getWorkIdsForCategory(category);
    final allWorks = storage.getAllWorks();
    final works = allWorks.where((w) => ids.contains(w.id)).toList();
    
    if (!context.mounted) return;
    
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.download),
              title: Text('Download All (${works.length})'),
              subtitle: Text('Download all works in "$category"'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadCategory(category, works);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Category Options'),
              onTap: () {
                Navigator.pop(ctx);
                _showCategoryOptionsDialog(category, works);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Top bar shown while in multi-select mode. [all] is the full set of works
  /// available for bulk operations / select-all.
  Widget _buildSelectionBar(List<Work> all) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Cancel selection',
          onPressed: _exitSelection,
        ),
        Text('${_selectedIds.length} selected',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Select all',
          onPressed: () =>
              setState(() => _selectedIds.addAll(all.map((w) => w.id))),
        ),
        IconButton(
          icon: const Icon(Icons.drive_file_move_outline),
          tooltip: 'Move to category',
          onPressed: _selectedIds.isEmpty ? null : () => _bulkMove(all),
        ),
        IconButton(
          icon: const Icon(Icons.download),
          tooltip: 'Download selected',
          onPressed: _selectedIds.isEmpty || _isDownloading
              ? null
              : () => _bulkDownload(all),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Remove selected',
          onPressed: _selectedIds.isEmpty ? null : () => _bulkDelete(all),
        ),
      ],
    );
  }

  Widget _buildCategoryContent(String category, List<Work> works, List<Work> allWorks) {
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final visible = _applySearchAndSort(works);

    Widget buildGrid() {
      return Column(
        children: [
          // Category action bar (only for specific categories, not 'All')
          if (category != 'All')
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isDownloading ? null : () => _downloadCategory(category, works),
                    icon: const Icon(Icons.download, size: 16),
                    label: Text('Download All (${works.length})'),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _isSyncing ? null : () => _syncCategory(category, works),
                    icon: _isSyncing 
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    tooltip: 'Sync updates',
                  ),
                  IconButton(
                    onPressed: () => _showCategoryOptionsDialog(category, works),
                    icon: const Icon(Icons.settings),
                    tooltip: 'Category Options',
                  ),
                ],
              ),
            ),
          if (visible.isEmpty)
            Expanded(
              child: Center(
                child: Text(
                  _searchQuery.isNotEmpty
                      ? 'No works match "$_searchQuery"'
                      : 'No works here yet',
                  style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color),
                ),
              ),
            )
          else
            Expanded(child: _grid(visible)),
        ],
      );
    }

    // Wrap with RefreshIndicator for mobile
    if (isMobile) {
      return RefreshIndicator(
        onRefresh: () => _syncCategory(category, works),
        child: buildGrid(),
      );
    }
    
    return buildGrid();
  }

  Widget _grid(List works) {
    // Get the grid columns setting
    final settingsColumns = ref.watch(libraryGridColumnsProvider);
    final viewMode = ref.watch(libraryViewModeProvider);
    
    return LayoutBuilder(
      builder: (context, constraints) {
        // Responsive grid: use user setting, but fewer columns on smaller screens
        final isCompact = constraints.maxWidth < 600;
        // On compact screens, use minimum of 2 or the setting (max 3 for compact)
        // On larger screens, use the user's setting
        final crossAxisCount = isCompact 
            ? (settingsColumns > 3 ? 2 : settingsColumns).clamp(1, 3)
            : settingsColumns;
        final childAspectRatio = isCompact ? 0.8 : 0.7;
        
        // Use list view mode
        if (viewMode == LibraryViewMode.list) {
          return ListView.builder(
            itemCount: works.length,
            itemBuilder: (context, i) => _buildWorkListItem(context, works[i], isCompact),
          );
        }
        
        // Grid view mode (default)
        return GridView.builder(
          itemCount: works.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, i) => _buildWorkGridItem(context, works[i], isCompact),
        );
      },
    );
  }
  
  /// Show context menu for long-press on work card
  Future<void> _showWorkContextMenu(BuildContext context, Work work) async {
    await showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                work.isFavorite ? Icons.star : Icons.star_border,
                color: work.isFavorite ? Colors.amber : null,
              ),
              title: Text(work.isFavorite
                  ? 'Remove from Favorites'
                  : 'Add to Favorites'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleFavorite(work);
              },
            ),
            ListTile(
              leading: Icon(
                work.isDownloaded ? Icons.download_done : Icons.download,
                color: work.isDownloaded ? Colors.green : null,
              ),
              title: Text(work.isDownloaded ? 'Re-download' : 'Download'),
              subtitle: work.isDownloaded 
                  ? const Text('Work is already downloaded') 
                  : const Text('Download for offline reading'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadWork(work);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: const Text('Edit Categories'),
              onTap: () {
                Navigator.pop(ctx);
                _editCategoriesForWork(context, work.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove from Library'),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx2) => AlertDialog(
                    title: const Text('Remove Work'),
                    content: Text('Remove "${work.title}" from your library?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx2, true),
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && context.mounted) {
                  final storage = ref.read(storageProvider);
                  await storage.deleteWork(work.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Removed "${work.title}"')),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }
  
  /// Toggle a work's favorite flag and persist it.
  Future<void> _toggleFavorite(Work w) async {
    final storage = ref.read(storageProvider);
    await storage.saveWork(w.copyWith(isFavorite: !w.isFavorite));
  }

  /// Open a work in the reader, recording the access in history first.
  Future<void> _openWork(Work w) async {
    final storage = ref.read(storageProvider);
    await storage.addToHistory(workId: w.id, title: w.title, author: w.author);
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ReaderScreen(work: w)),
      );
    }
  }

  /// Build a work card for grid view
  Widget _buildWorkGridItem(BuildContext context, Work w, bool isCompact) {
    final selected = _selectionMode && _selectedIds.contains(w.id);
    return Card(
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: () => _selectionMode ? _toggleSelect(w.id) : _openWork(w),
        // Long press shows the per-work context menu, or toggles selection
        // while in multi-select mode.
        onLongPress: () => _selectionMode
            ? _toggleSelect(w.id)
            : _showWorkContextMenu(context, w),
        child: Padding(
          padding: EdgeInsets.all(isCompact ? 6.0 : 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (_selectionMode)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(
                        selected ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      w.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: isCompact ? 13 : 14,
                      ),
                    ),
                  ),
                  // Favorite toggle (always visible)
                  GestureDetector(
                    onTap: () => _toggleFavorite(w),
                    child: Icon(
                      w.isFavorite ? Icons.star : Icons.star_border,
                      size: 16,
                      color: w.isFavorite ? Colors.amber : null,
                    ),
                  ),
                  // Download indicator (always visible)
                  if (w.isDownloaded)
                    const Padding(
                      padding: EdgeInsets.only(left: 2),
                      child: Icon(Icons.download_done,
                          size: 16, color: Colors.green),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'by ${w.author}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: isCompact ? 11 : 12),
              ),
              const SizedBox(height: 4),
              if ((w.summary ?? '').isNotEmpty)
                Text(
                  w.summary!,
                  maxLines: isCompact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: isCompact ? 10 : 12),
                ),
              const Spacer(),
              // Action buttons on larger screens
              if (!isCompact)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Download button
                    IconButton(
                      onPressed: _isDownloading ? null : () => _downloadWork(w),
                      icon: Icon(
                        w.isDownloaded ? Icons.download_done : Icons.download,
                        color: w.isDownloaded ? Colors.green : null,
                      ),
                      tooltip: w.isDownloaded ? 'Downloaded' : 'Download',
                    ),
                    IconButton(
                      onPressed: () => _editCategoriesForWork(context, w.id),
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Edit Categories',
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// Build a work item for list view
  Widget _buildWorkListItem(BuildContext context, Work w, bool isCompact) {
    final selected = _selectionMode && _selectedIds.contains(w.id);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      color: selected ? Theme.of(context).colorScheme.primaryContainer : null,
      child: InkWell(
        onTap: () => _selectionMode ? _toggleSelect(w.id) : _openWork(w),
        onLongPress: () => _selectionMode
            ? _toggleSelect(w.id)
            : _showWorkContextMenu(context, w),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              if (_selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(
                    selected ? Icons.check_circle : Icons.circle_outlined,
                    size: 20,
                    color:
                        selected ? Theme.of(context).colorScheme.primary : null,
                  ),
                ),
              // Download status indicator
              if (w.isDownloaded)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.download_done, size: 18, color: Colors.green),
                ),
              // Work info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      w.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'by ${w.author}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodySmall?.color),
                    ),
                  ],
                ),
              ),
              // Word count
              if (w.wordsCount != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(
                    '${w.wordsCount} words',
                    style: TextStyle(fontSize: 11, color: Theme.of(context).textTheme.bodySmall?.color),
                  ),
                ),
              // Favorite toggle
              if (!_selectionMode)
                IconButton(
                  onPressed: () => _toggleFavorite(w),
                  icon: Icon(
                    w.isFavorite ? Icons.star : Icons.star_border,
                    size: 20,
                    color: w.isFavorite ? Colors.amber : null,
                  ),
                  padding: const EdgeInsets.only(left: 4),
                  constraints: const BoxConstraints(),
                  tooltip: w.isFavorite ? 'Unfavorite' : 'Favorite',
                ),
              // More options button (hidden while selecting)
              if (!_selectionMode)
                IconButton(
                  onPressed: () => _showWorkContextMenu(context, w),
                  icon: const Icon(Icons.more_vert, size: 20),
                  padding: const EdgeInsets.only(left: 4),
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
