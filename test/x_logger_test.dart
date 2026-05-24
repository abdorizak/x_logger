import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:x_logger/x_logger.dart';

/// In-memory output that records rendered lines for assertions.
class _CaptureOutput extends LogOutput {
  _CaptureOutput({super.printer, super.filter});

  final List<String> lines = <String>[];

  @override
  void write(LogEvent event, List<String> rendered) => lines.addAll(rendered);
}

void main() {
  group('SimplePrinter formatting', () {
    test('includes level and name, omits timestamp when disabled', () {
      final printer = const SimplePrinter(
        LoggerConfig(showTimestamp: false),
      );

      final lines = printer.render(
        LogEvent(
          level: LogLevel.info,
          message: 'streaming started',
          loggerName: 'AgentAlpha',
        ),
      );

      expect(lines, ['[INFO] (AgentAlpha) streaming started']);
    });

    test('appends structured fields and error', () {
      const printer = SimplePrinter(
        LoggerConfig(showTimestamp: false, showName: false),
      );

      final lines = printer.render(
        LogEvent(
          level: LogLevel.error,
          message: 'query failed',
          loggerName: 'DB',
          fields: {'table': 'users', 'rows': 0},
          error: StateError('boom'),
        ),
      );

      expect(lines.single, contains('[ERROR] query failed'));
      expect(lines.single, contains('{table=users, rows=0}'));
      expect(lines.single, contains('| error: Bad state: boom'));
    });

    test('prepends the level emoji when showEmoji is set', () {
      const printer = SimplePrinter(
        LoggerConfig(showTimestamp: false, showEmoji: true),
      );

      final lines = printer.render(
        LogEvent(level: LogLevel.warning, message: 'careful', loggerName: 'N'),
      );

      expect(lines.single, '⚠️ [WARN] (N) careful');
    });

    test('custom timestamp formatter is honored', () {
      final printer = SimplePrinter(
        LoggerConfig(
          showLevel: false,
          showName: false,
          timeFormatter: (_) => 'T0',
        ),
      );

      final lines = printer.render(
        LogEvent(level: LogLevel.info, message: 'x', loggerName: 'N'),
      );

      expect(lines.single, 'T0 x');
    });
  });

  group('JsonPrinter', () {
    test('pretty-prints nested fields across lines', () {
      const printer = JsonPrinter();

      final lines = printer.render(
        LogEvent(
          level: LogLevel.info,
          message: 'search request',
          loggerName: 'QuranReader',
          sequence: 7,
          fields: {
            'query': 'mercy',
            'filters': {'surah': [1, 2], 'exact': false},
          },
        ),
      );

      // Multi-line, indented output.
      expect(lines.length, greaterThan(1));
      final joined = lines.join('\n');
      expect(joined, contains('"level": "INFO"'));
      expect(joined, contains('"logger": "QuranReader"'));
      expect(joined, contains('"seq": 7'));
      expect(joined, contains('"query": "mercy"'));
      expect(joined, contains('    "surah": ['));
    });

    test('compact mode emits a single line', () {
      const printer = JsonPrinter(pretty: false);

      final lines = printer.render(
        LogEvent(level: LogLevel.debug, message: 'x', loggerName: 'N'),
      );

      expect(lines, hasLength(1));
      expect(lines.single, startsWith('{'));
    });
  });

  group('filtering', () {
    test('global level filter drops low-severity records', () {
      final capture = _CaptureOutput(
        printer: const SimplePrinter(LoggerConfig(showTimestamp: false)),
      );
      final logger = XLogger(
        name: 'T',
        filter: const LevelFilter(LogLevel.warning),
        outputs: <LogOutput>[capture],
      );

      logger
        ..debug('a')
        ..info('b')
        ..warning('c')
        ..error('d');

      expect(capture.lines, hasLength(2));
      expect(capture.lines[0], contains('[WARN] (T) c'));
      expect(capture.lines[1], contains('[ERROR] (T) d'));
    });

    test('per-output filter is independent of the global one', () {
      final everything = _CaptureOutput(
        printer: const SimplePrinter(LoggerConfig(showTimestamp: false)),
      );
      final errorsOnly = _CaptureOutput(
        printer: const SimplePrinter(LoggerConfig(showTimestamp: false)),
        filter: const LevelFilter(LogLevel.error),
      );
      final logger = XLogger(
        name: 'T',
        filter: const LevelFilter(LogLevel.debug),
        outputs: <LogOutput>[everything, errorsOnly],
      );

      logger
        ..info('i')
        ..error('e');

      expect(everything.lines, hasLength(2));
      expect(errorsOnly.lines, hasLength(1));
      expect(errorsOnly.lines.single, contains('[ERROR] (T) e'));
    });

    test('predicate filter inspects fields', () {
      final capture = _CaptureOutput(
        printer: const SimplePrinter(LoggerConfig(showTimestamp: false)),
      );
      final logger = XLogger(
        name: 'T',
        filter: PredicateFilter((e) => e.fields['keep'] == true),
        outputs: <LogOutput>[capture],
      );

      logger.info('dropped');
      logger.info('kept', fields: {'keep': true});

      expect(capture.lines, hasLength(1));
      expect(capture.lines.single, contains('kept'));
    });
  });

  group('StreamOutput', () {
    test('emits rendered entries', () async {
      final streamOut = StreamOutput(
        printer: const SimplePrinter(LoggerConfig(showTimestamp: false)),
      );
      final logger = XLogger(name: 'S', outputs: <LogOutput>[streamOut]);

      final received = <LogEntry>[];
      final sub = logger.stream!.listen(received.add);

      logger.info('one');
      logger.warning('two');
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(2));
      expect(received.first.event.message, 'one');
      expect(received.first.lines.single, contains('[INFO] (S) one'));

      await sub.cancel();
      await logger.dispose();
    });
  });

  group('MemoryOutput', () {
    test('retains a bounded ring buffer', () {
      final mem = MemoryOutput(
        capacity: 2,
        printer: const SimplePrinter(
          LoggerConfig(showTimestamp: false, showName: false, showLevel: false),
        ),
      );
      final logger = XLogger(name: 'M', outputs: <LogOutput>[mem]);

      logger
        ..info('a')
        ..info('b')
        ..info('c');

      expect(logger.memoryDump, 'b\nc');
    });
  });

  group('file export', () {
    test('writes lines and exports contents', () async {
      final tmp = await Directory.systemTemp.createTemp('x_logger_test');
      final path = '${tmp.path}${Platform.pathSeparator}session.log';

      final logger = XLogger(
        name: 'File',
        outputs: <LogOutput>[
          FileOutput(
            filePath: path,
            printer: const SimplePrinter(LoggerConfig(showTimestamp: false)),
          ),
        ],
      );

      logger.info('hello');
      logger.error('boom');
      await logger.flush();

      final contents = await logger.exportLogsAsString();
      expect(contents, contains('[INFO] (File) hello'));
      expect(contents, contains('[ERROR] (File) boom'));

      final file = await logger.getLogFile();
      expect(file!.path, path);

      await logger.dispose();
      await tmp.delete(recursive: true);
    });

    test('export accessors return null without a file output', () async {
      final logger = XLogger(name: 'NoFile', outputs: <LogOutput>[]);
      expect(await logger.exportLogsAsString(), isNull);
      expect(await logger.getLogFile(), isNull);
    });
  });

  group('child loggers', () {
    test('share the same outputs (one file, distinct names)', () async {
      final tmp = await Directory.systemTemp.createTemp('x_logger_child');
      final path = '${tmp.path}${Platform.pathSeparator}app.log';

      final root = XLogger(
        name: 'WACYI',
        outputs: <LogOutput>[
          FileOutput(
            filePath: path,
            printer: const SimplePrinter(LoggerConfig(showTimestamp: false)),
          ),
        ],
      );
      final quran = root.child('QuranReader');
      final audio = root.child('AudioPlayer');

      // All three share the single FileOutput instance => one file handle.
      expect(quran.outputs.single, same(root.outputs.single));
      expect(audio.outputs.single, same(root.outputs.single));

      root.info('app started');
      quran.info('ayah rendered');
      audio.warning('buffering');

      await root.flush();
      final contents = await root.exportLogsAsString();
      expect(contents, contains('(WACYI) app started'));
      expect(contents, contains('(QuranReader) ayah rendered'));
      expect(contents, contains('(AudioPlayer) buffering'));

      await root.dispose();
      await tmp.delete(recursive: true);
    });
  });
}
