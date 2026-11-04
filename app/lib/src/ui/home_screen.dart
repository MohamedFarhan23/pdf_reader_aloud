import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../library/stores.dart';
import '../tts/voice_catalog.dart';
import 'reader_screen.dart';
import 'voices_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.state});

  final AppState state;

  Future<void> _pickPdf(BuildContext context) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      dialogTitle: 'Open a PDF',
    );
    final file = files.firstOrNull;
    if (file?.path == null || !context.mounted) return;
    final entry = await state.openDocument(file!.path!, name: file.name);
    if (context.mounted) _openReader(context, entry);
  }

  void _openReader(BuildContext context, LibraryEntry entry) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ReaderScreen(state: state, entry: entry)));
  }

  void _openVoices(BuildContext context) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VoicesScreen(state: state)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final library = state.library;
        return Scaffold(
          appBar: AppBar(
            title: const Text('PDF Reader Aloud'),
            actions: [
              IconButton(
                tooltip: 'Voices',
                icon: const Icon(Icons.record_voice_over_outlined),
                onPressed: () => _openVoices(context),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _pickPdf(context),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Open PDF'),
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  if (!state.hasAnyVoice) _VoiceSetupCard(state: state, onMore: () => _openVoices(context)),
                  if (library.isEmpty)
                    const _EmptyLibrary()
                  else ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                      child: Text('Recent', style: Theme.of(context).textTheme.titleSmall),
                    ),
                    for (final entry in library)
                      _LibraryTile(
                        entry: entry,
                        onOpen: () => _openReader(context, entry),
                        onRemove: () => state.removeDocument(entry),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.entry, required this.onOpen, required this.onRemove});

  final LibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final pages = entry.pageCount > 0 ? 'Page ${entry.position.page} of ${entry.pageCount}' : 'Not started';
    return Card.filled(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined),
        title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('$pages · ${_ago(entry.lastOpened)}'),
        onTap: onOpen,
        trailing: PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (_) => onRemove(),
          itemBuilder: (_) => const [PopupMenuItem(value: 'remove', child: Text('Remove from library'))],
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays == 1) return 'yesterday';
    return '${d.inDays} days ago';
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 64),
      child: Column(
        children: [
          Icon(Icons.menu_book_outlined, size: 64, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text('Open a PDF to start listening', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Your recent documents and reading progress appear here.',
              style: theme.textTheme.bodyMedium, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// First-run card: a voice has to be downloaded once before reading.
class _VoiceSetupCard extends StatelessWidget {
  const _VoiceSetupCard({required this.state, required this.onMore});

  final AppState state;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final model = kokoroModel;
    final progress = state.models.progressOf(model);
    final error = state.models.errorOf(model);
    return Card(
      color: theme.colorScheme.primaryContainer,
      margin: const EdgeInsets.only(top: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Download a voice to get started', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Voices run entirely on this device, so reading works offline and your documents stay private. '
              'Kokoro is about ${model.downloadMb} MB.',
            ),
            const SizedBox(height: 12),
            if (progress != null) ...[
              LinearProgressIndicator(value: progress.fraction),
              const SizedBox(height: 4),
              Text(progress.fraction == null
                  ? '${progress.phase}…'
                  : '${progress.phase} ${(progress.fraction! * 100).round()}%'),
            ] else
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.download),
                    label: const Text('Download Kokoro'),
                    onPressed: () async {
                      await state.models.download(model);
                      if (state.models.isInstalled(model)) state.onModelInstalled(model);
                    },
                  ),
                  TextButton(onPressed: onMore, child: const Text('Other voices')),
                ],
              ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
