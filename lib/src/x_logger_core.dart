import 'dart:io';

import 'log_event.dart';
import 'log_filter.dart';
import 'log_level.dart';
import 'log_output.dart';
import 'logger_config.dart';

/// The primary logger.
///
/// Pipeline for every call: build a [LogEvent] → apply the global [filter] →
/// dispatch to each [LogOutput], which applies its own filter and renders with
/// its own printer. Create one named instance per workflow you want to track:
///
/// ```dart
/// final agent = XLogger(
///   name: 'AgentAlpha',
///   filter: const LevelFilter(LogLevel.debug),
///   outputs: [ConsoleOutput(), FileOutput(fileName: 'agent.log')],
/// );
/// agent.info('Stream opened', fields: {'tokens': 42});
/// ```
class XLogger {
  XLogger({
    this.name = 'XLogger',
    this.config = const LoggerConfig(),
    LogFilter? filter,
    List<LogOutput>? outputs,
  })  : filter = filter ?? LevelFilter(config.minLevel),
        _outputs = outputs ?? <LogOutput>[ConsoleOutput()] {
    for (final output in _outputs) {
      // Start async setup; early writes are buffered by the output itself.
      // ignore: discarded_futures
      output.init();
    }
  }

  /// A zero-configuration logger with sensible defaults: a colorized
  /// [ConsoleOutput] plus a [FileOutput] that writes to the app documents
  /// directory (resolved automatically), so [getLogFile]/[exportLogsAsString]
  /// work out of the box. Use this when you don't want to customize anything.
  ///
  /// ```dart
  /// final log = XLogger.standard(name: 'AgentAlpha');
  /// log.info('ready');
  /// final file = await log.getLogFile(); // ready to share
  /// ```
  factory XLogger.standard({
    String name = 'XLogger',
    String fileName = 'x_logger.log',
    LogLevel minLevel = LogLevel.debug,
  }) {
    return XLogger(
      name: name,
      filter: LevelFilter(minLevel),
      outputs: <LogOutput>[
        ConsoleOutput(),
        FileOutput(fileName: fileName),
      ],
    );
  }

  /// Identifier shown in the `(name)` header field.
  final String name;

  /// Default style for the built-in console output. Mutable so verbosity/format
  /// can change at runtime.
  LoggerConfig config;

  /// Global gate applied before any output sees a record. Mutable.
  LogFilter filter;

  final List<LogOutput> _outputs;
  int _sequence = 0;

  /// The attached outputs, as an unmodifiable view.
  List<LogOutput> get outputs => List<LogOutput>.unmodifiable(_outputs);

  /// Logs at [LogLevel.debug].
  void debug(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) =>
      log(LogLevel.debug, message,
          error: error, stackTrace: stackTrace, fields: fields);

  /// Logs at [LogLevel.info].
  void info(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) =>
      log(LogLevel.info, message,
          error: error, stackTrace: stackTrace, fields: fields);

  /// Logs at [LogLevel.warning].
  void warning(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) =>
      log(LogLevel.warning, message,
          error: error, stackTrace: stackTrace, fields: fields);

  /// Logs at [LogLevel.error].
  void error(
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) =>
      log(LogLevel.error, message,
          error: error, stackTrace: stackTrace, fields: fields);

  /// Core entry point: builds the event, applies the global [filter], and
  /// dispatches it to every output.
  void log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final event = LogEvent(
      level: level,
      message: message,
      loggerName: name,
      fields: fields,
      sequence: _sequence++,
      error: error,
      stackTrace: stackTrace,
    );

    if (!filter.shouldLog(event)) return;

    for (final output in _outputs) {
      output.handle(event);
    }
  }

  /// Attaches an additional output at runtime and initializes it.
  void addOutput(LogOutput output) {
    _outputs.add(output);
    // ignore: discarded_futures
    output.init();
  }

  /// Creates a logger with a different [name] that shares this logger's
  /// [config], [filter], and outputs (and therefore the same file/stream).
  XLogger child(String name) =>
      XLogger(name: name, config: config, filter: filter, outputs: _outputs);

  // ---- Export API ---------------------------------------------------------

  T? _firstOutput<T extends LogOutput>() {
    for (final output in _outputs) {
      if (output is T) return output;
    }
    return null;
  }

  /// The live record stream from the first attached [StreamOutput], if any.
  Stream<LogEntry>? get stream => _firstOutput<StreamOutput>()?.stream;

  /// The buffered lines from the first attached [MemoryOutput], if any.
  String? get memoryDump => _firstOutput<MemoryOutput>()?.dump();

  /// Flushes pending writes and returns the backing log [File].
  ///
  /// Returns null when no [FileOutput] is attached, or when nothing has been
  /// written yet. Use [File.path] to hand off to `share_plus`, an upload, etc.
  Future<File?> getLogFile() async {
    final output = _firstOutput<FileOutput>();
    if (output == null) return null;
    await output.flush();
    final file = output.file;
    if (file == null || !await file.exists()) return null;
    return file;
  }

  /// Returns the full contents of the log file, or null when no file output is
  /// attached / the file does not exist yet.
  Future<String?> exportLogsAsString() async {
    final file = await getLogFile();
    if (file == null) return null;
    return file.readAsString();
  }

  /// Flushes every attached output. Call before reading or sharing the file.
  Future<void> flush() async {
    for (final output in _outputs) {
      await output.flush();
    }
  }

  /// Flushes and closes every output. The logger should not be used afterwards.
  Future<void> dispose() async {
    for (final output in _outputs) {
      await output.close();
    }
  }
}
