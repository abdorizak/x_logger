import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:x_logger/x_logger.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'x_logger example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const LogDemoPage(),
    );
  }
}

class LogDemoPage extends StatefulWidget {
  const LogDemoPage({super.key});

  @override
  State<LogDemoPage> createState() => _LogDemoPageState();
}

class _LogDemoPageState extends State<LogDemoPage> {
  // Configure ONCE. `_appLog` owns the outputs (one console, one file, one
  // stream); the children below just add a name and reuse those resources.
  late final XLogger _appLog;
  late final XLogger _quranLog;
  late final XLogger _audioLog;

  // Captured events, re-rendered live with whichever printer is selected.
  final List<LogEvent> _events = <LogEvent>[];
  final ScrollController _scroll = ScrollController();
  bool _json = false;
  int _counter = 0;

  // Compact text with the per-level emoji (no ANSI — the UI applies color).
  static const LogPrinter _textPrinter = SimplePrinter(
    LoggerConfig(showEmoji: true, timeFormatter: TimeFormats.clock),
  );

  // Pretty (indented) JSON.
  static const LogPrinter _jsonPrinter = JsonPrinter();

  @override
  void initState() {
    super.initState();
    _appLog = XLogger(
      name: 'WACYI',
      filter: const LevelFilter(LogLevel.debug),
      outputs: <LogOutput>[
        ConsoleOutput(
          printer: const SimplePrinter(
            LoggerConfig(
              showEmoji: true,
              colorize: true,
              timeFormatter: TimeFormats.clock,
            ),
          ),
        ),
        FileOutput(
          fileName: 'app.log',
          printer: const SimplePrinter(
            LoggerConfig(showEmoji: true, timeFormatter: TimeFormats.clock),
          ),
        ),
        StreamOutput(),
      ],
    );

    _quranLog = _appLog.child('QuranReader');
    _audioLog = _appLog.child('AudioPlayer');

    _appLog.stream?.listen((entry) {
      if (!mounted) return;
      setState(() => _events.add(entry.event));
      _scrollToBottom();
    });

    _appLog.info('app started');
  }

  @override
  void dispose() {
    _appLog.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _debug() => _appLog.debug('cache warmed', fields: {'entries': 128});

  void _info() {
    final n = _counter++;
    _quranLog.info('ayah rendered', fields: {'surah': 2, 'ayah': n});
  }

  void _warning() =>
      _audioLog.warning('buffering', fields: {'bufferMs': 1200, 'retries': 1});

  void _error() {
    try {
      throw StateError('audio session interrupted');
    } catch (e, s) {
      _audioLog.error('playback stopped', error: e, stackTrace: s);
    }
  }

  void _jsonPayload() {
    _quranLog.info(
      'search request',
      fields: {
        'query': 'mercy',
        'filters': {
          'surah': [1, 2, 18],
          'translation': 'en.sahih',
          'exact': false,
        },
        'page': 1,
      },
    );
  }

  Future<void> _export() async {
    await _appLog.flush();
    final file = await _appLog.getLogFile();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    if (file == null) {
      messenger.showSnackBar(const SnackBar(content: Text('No log file yet')));
      return;
    }

    try {
      await Share.shareXFiles(
        <XFile>[XFile(file.path, mimeType: 'text/plain')],
        subject: 'x_logger export',
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Exported to: ${file.path}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('x_logger example'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Clear',
            onPressed: () => setState(_events.clear),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonal(
                  onPressed: _debug,
                  child: const Text('🐛 Debug'),
                ),
                FilledButton.tonal(
                  onPressed: _info,
                  child: const Text('💡 Info'),
                ),
                FilledButton.tonal(
                  onPressed: _warning,
                  child: const Text('⚠️ Warning'),
                ),
                FilledButton.tonal(
                  onPressed: _error,
                  child: const Text('⛔ Error'),
                ),
                FilledButton(
                  onPressed: _jsonPayload,
                  child: const Text('{ } JSON payload'),
                ),
                OutlinedButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export & share'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<bool>(
              segments: const <ButtonSegment<bool>>[
                ButtonSegment<bool>(value: false, label: Text('Text')),
                ButtonSegment<bool>(value: true, label: Text('Pretty JSON')),
              ],
              selected: <bool>{_json},
              onSelectionChanged: (s) => setState(() => _json = s.first),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
              child:
                  _Terminal(events: _events, json: _json, controller: _scroll)),
        ],
      ),
    );
  }
}

/// A terminal-style panel: dark background, monospace text, a mac-style title
/// bar, and per-level colors (applied in Flutter, since the on-screen printers
/// emit plain text rather than ANSI escapes).
class _Terminal extends StatelessWidget {
  const _Terminal({
    required this.events,
    required this.json,
    required this.controller,
  });

  final List<LogEvent> events;
  final bool json;
  final ScrollController controller;

  static const Color _bg = Color(0xFF0C0C0C);
  static const Color _bar = Color(0xFF2B2B2B);

  // VS Code "Dark+"-ish palette.
  static const Color _cDebug = Color(0xFF8A8A8A);
  static const Color _cInfo = Color(0xFF4EC9B0);
  static const Color _cWarn = Color(0xFFDCDCAA);
  static const Color _cError = Color(0xFFF14C4C);
  static const Color _cJson = Color(0xFFD4D4D4);
  static const Color _cPrompt = Color(0xFF6A9955);

  Color _colorFor(LogLevel level) {
    if (json) return _cJson;
    return switch (level) {
      LogLevel.debug => _cDebug,
      LogLevel.info => _cInfo,
      LogLevel.warning => _cWarn,
      LogLevel.error => _cError,
    };
  }

  Widget _dot(Color color) => Container(
        width: 12,
        height: 12,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );

  @override
  Widget build(BuildContext context) {
    final printer =
        json ? _LogDemoPageState._jsonPrinter : _LogDemoPageState._textPrinter;
    final rows = <(String, LogLevel)>[
      for (final event in events)
        for (final line in printer.render(event)) (line, event.level),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3)),
        ],
      ),
      child: Column(
        children: <Widget>[
          // Title bar with traffic-light buttons.
          Container(
            color: _bar,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: <Widget>[
                _dot(const Color(0xFFFF5F56)),
                _dot(const Color(0xFFFFBD2E)),
                _dot(const Color(0xFF27C93F)),
                const SizedBox(width: 10),
                const Text(
                  'app.log — x_logger',
                  style: TextStyle(
                    color: Colors.white60,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        r'$ tap a level to emit a record_',
                        style: TextStyle(
                          color: _cPrompt,
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.all(14),
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final (text, level) = rows[i];
                      return Text(
                        text,
                        style: TextStyle(
                          color: _colorFor(level),
                          fontFamily: 'monospace',
                          fontSize: 13,
                          height: 1.5,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
