import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/app_state.dart';
import 'src/ui/home_screen.dart';
import 'src/ui/motion.dart';
import 'src/ui/reader_screen.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final state = await AppState.create();
  if (!isMobile && state.folders.isNotEmpty) unawaited(state.rescan());

  // Desktop: `pdf_reader_aloud book.pdf` (or "Open with") opens the file directly.
  final initialFile = args.where((a) => a.toLowerCase().endsWith('.pdf') && File(a).existsSync()).firstOrNull;
  runApp(PdfReaderAloudApp(state: state, initialFile: initialFile));
}

class PdfReaderAloudApp extends StatelessWidget {
  const PdfReaderAloudApp({super.key, required this.state, this.initialFile});

  final AppState state;
  final String? initialFile;

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F51B5);
    return MaterialApp(
      title: 'PDF Reader Aloud',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: seed, useMaterial3: true, pageTransitionsTheme: smoothPageTransitions),
      darkTheme: ThemeData(
        colorSchemeSeed: seed,
        brightness: Brightness.dark,
        useMaterial3: true,
        pageTransitionsTheme: smoothPageTransitions,
      ),
      home: _Launcher(state: state, initialFile: initialFile),
    );
  }
}

class _Launcher extends StatefulWidget {
  const _Launcher({required this.state, this.initialFile});
  final AppState state;
  final String? initialFile;

  @override
  State<_Launcher> createState() => _LauncherState();
}

class _LauncherState extends State<_Launcher> {
  @override
  void initState() {
    super.initState();
    final file = widget.initialFile;
    if (file != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final entry = await widget.state.openDocument(file);
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => ReaderScreen(state: widget.state, entry: entry),
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) => HomeScreen(state: widget.state);
}
