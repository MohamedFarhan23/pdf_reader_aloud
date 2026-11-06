import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app_state.dart';
import '../library/folder_scanner.dart';
import '../library/stores.dart';
import 'motion.dart';

enum _Sort {
  name('Name', Icons.sort_by_alpha, 'A to Z', 'Z to A'),
  recent('Recently read', Icons.history, 'Most recent first', 'Least recent first'),
  modified('Date modified', Icons.event, 'Newest first', 'Oldest first'),
  size('File size', Icons.data_usage, 'Largest first', 'Smallest first');

  const _Sort(this.label, this.icon, this.natural, this.reversed);
  final String label;
  final IconData icon;

  /// Description of the default order, and of the flipped one.
  final String natural;
  final String reversed;
}

/// Every PDF in the user's chosen folders, as a grid or list with thumbnails
/// (like a video library), plus search, sorting and folder management.
class PdfLibraryView extends StatefulWidget {
  const PdfLibraryView({super.key, required this.state, required this.onOpen});

  final AppState state;
  final void Function(String path, String name) onOpen;

  @override
  State<PdfLibraryView> createState() => _PdfLibraryViewState();
}

const double _controlHeight = 40;

class _PdfLibraryViewState extends State<PdfLibraryView> {
  String _query = '';
  _Sort _sort = _Sort.name;
  bool _flipped = false;
  final Set<String> _entered = {}; // cards that already played their entrance

  AppState get state => widget.state;

  Future<void> _addFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: 'Choose a folder with PDFs');
    if (dir != null) await state.addFolder(dir);
  }

  List<FoundPdf> _visible() {
    final q = _query.trim().toLowerCase();
    final list = state.foundPdfs.where((f) => q.isEmpty || f.title.toLowerCase().contains(q)).toList();
    int byName(FoundPdf a, FoundPdf b) => a.title.toLowerCase().compareTo(b.title.toLowerCase());
    switch (_sort) {
      case _Sort.name:
        list.sort(byName);
      case _Sort.modified:
        list.sort((a, b) => b.modified.compareTo(a.modified));
      case _Sort.size:
        list.sort((a, b) => b.size.compareTo(a.size));
      case _Sort.recent:
        DateTime? opened(FoundPdf f) => state.entryFor(f.path)?.lastOpened;
        list.sort((a, b) {
          final x = opened(a), y = opened(b);
          if (x == null && y == null) return byName(a, b);
          if (x == null) return 1;
          if (y == null) return -1;
          return y.compareTo(x);
        });
    }
    return _flipped ? list.reversed.toList() : list;
  }

  /// Staggered fade-and-lift the first time a card appears (never again when scrolled back).
  Widget _entrance(int index, FoundPdf pdf, Widget child) {
    final first = _entered.add(pdf.path);
    return FadeSlideIn(
      key: ValueKey(pdf.path),
      animate: first,
      delay: Duration(milliseconds: 30 * (index < 16 ? index : 16)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = state.folders;
    if (folders.isEmpty) return _NoFolders(onAdd: _addFolder);
    final items = _visible();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Your PDFs', style: theme.textTheme.titleMedium),
              Text(
                state.scanning
                    ? 'Scanning… ${state.foundPdfs.length} found, ${state.foldersScanned} folders checked'
                    : '${state.foundPdfs.length} found',
                style: theme.textTheme.bodySmall,
              ),
              if (state.scanning) ...[
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                OutlinedButton.icon(
                  onPressed: state.stopScan,
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop scan'),
                ),
              ],
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 260,
              height: _controlHeight,
              child: TextField(
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search PDFs',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            MenuAnchor(
              menuChildren: [
                for (final option in _Sort.values)
                  MenuItemButton(
                    leadingIcon: Icon(option.icon, size: 18),
                    trailingIcon: option == _sort ? const Icon(Icons.check, size: 18) : null,
                    onPressed: () => setState(() {
                      if (option != _sort) _flipped = false;
                      _sort = option;
                    }),
                    child: Text(option.label),
                  ),
              ],
              builder: (context, controller, _) => SizedBox(
                height: _controlHeight,
                child: OutlinedButton.icon(
                  onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                  icon: Icon(_sort.icon, size: 18),
                  label: Text('Sort: ${_sort.label}'),
                ),
              ),
            ),
            IconButton.outlined(
              tooltip: _flipped ? _sort.reversed : _sort.natural,
              onPressed: () => setState(() => _flipped = !_flipped),
              icon: Icon(_flipped ? Icons.arrow_upward : Icons.arrow_downward, size: 18),
            ),
            SegmentedButton<bool>(
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, icon: Icon(Icons.grid_view), tooltip: 'Grid'),
                ButtonSegment(value: false, icon: Icon(Icons.view_list), tooltip: 'List'),
              ],
              selected: {state.gridView},
              onSelectionChanged: (s) => state.setGridView(s.first),
            ),
            IconButton.outlined(
              tooltip: 'Scan folders again',
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: state.scanning ? null : state.rescan,
            ),
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  leadingIcon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  onPressed: _addFolder,
                  child: const Text('Add folder…'),
                ),
                if (folders.isNotEmpty) const Divider(height: 8),
                for (final f in folders)
                  Tooltip(
                    message: f,
                    child: MenuItemButton(
                      leadingIcon: const Icon(Icons.delete_outline, size: 18),
                      onPressed: () => state.removeFolder(f),
                      child: Text('Remove ${p.basename(f)}'),
                    ),
                  ),
              ],
              builder: (context, controller, _) => SizedBox(
                height: _controlHeight,
                child: OutlinedButton.icon(
                  onPressed: () => controller.isOpen ? controller.close() : controller.open(),
                  icon: const Icon(Icons.folder_open_outlined, size: 18),
                  label: Text('Folders (${folders.length})'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (items.isEmpty && !state.scanning)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(child: Text(_query.isEmpty ? 'No PDFs found in your folders.' : 'No PDFs match "$_query".')),
          )
        else if (state.gridView)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200,
              mainAxisExtent: 330,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _entrance(i, items[i], _PdfCard(state: state, pdf: items[i], onOpen: widget.onOpen)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (_, i) => _entrance(i, items[i], _PdfRow(state: state, pdf: items[i], onOpen: widget.onOpen)),
          ),
      ],
    );
  }
}

class _NoFolders extends StatelessWidget {
  const _NoFolders({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Card.filled(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.folder_copy_outlined, size: 48, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('Build your PDF library', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'Choose a folder (for example Documents or Downloads) and every PDF inside it is listed here with a preview.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add folder'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Reading progress (0..1) for a PDF the user has opened before, else null.
double? _progressOf(LibraryEntry? e) {
  if (e == null || e.pageCount <= 0) return null;
  return ((e.position.page - 1) / e.pageCount).clamp(0.0, 1.0);
}

String _size(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.state, required this.pdf});

  final AppState state;
  final FoundPdf pdf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(child: Icon(Icons.picture_as_pdf_outlined, color: theme.colorScheme.outline, size: 36)),
    );
    return FutureBuilder<File?>(
      future: state.thumbnails.thumbnailFor(pdf),
      builder: (_, snap) {
        final file = snap.data;
        if (file == null) return placeholder;
        // The preview fades in over the placeholder once it has decoded.
        return Stack(
          fit: StackFit.expand,
          children: [
            placeholder,
            Image.file(
              file,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
              frameBuilder: (_, image, frame, sync) => AnimatedOpacity(
                opacity: frame == null && !sync ? 0 : 1,
                duration: const Duration(milliseconds: 420),
                curve: smoothCurve,
                child: image,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PdfCard extends StatelessWidget {
  const _PdfCard({required this.state, required this.pdf, required this.onOpen});

  final AppState state;
  final FoundPdf pdf;
  final void Function(String path, String name) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = _progressOf(state.entryFor(pdf.path));
    return HoverLift(
      child: Card.filled(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: () => onOpen(pdf.path, p.basename(pdf.path)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Thumb(state: state, pdf: pdf),
              ),
              if (progress != null) _ProgressLine(progress),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pdf.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      '${pdf.folder} · ${_size(pdf.size)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PdfRow extends StatelessWidget {
  const _PdfRow({required this.state, required this.pdf, required this.onOpen});

  final AppState state;
  final FoundPdf pdf;
  final void Function(String path, String name) onOpen;

  @override
  Widget build(BuildContext context) {
    final entry = state.entryFor(pdf.path);
    final progress = _progressOf(entry);
    final read = entry != null && entry.pageCount > 0 ? ' · page ${entry.position.page} of ${entry.pageCount}' : '';
    return Card.filled(
      margin: const EdgeInsets.symmetric(vertical: 3),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => onOpen(pdf.path, p.basename(pdf.path)),
        child: SizedBox(
          height: 84,
          child: Row(
            children: [
              SizedBox(
                width: 62,
                height: 84,
                child: _Thumb(state: state, pdf: pdf),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pdf.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text('${pdf.folder} · ${_size(pdf.size)}$read', maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (progress != null) ...[const SizedBox(height: 6), _ProgressLine(progress)],
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin reading-progress bar that grows to its value when it appears.
class _ProgressLine extends StatelessWidget {
  const _ProgressLine(this.value);

  final double value;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value),
    duration: const Duration(milliseconds: 700),
    curve: smoothCurve,
    builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 3),
  );
}
