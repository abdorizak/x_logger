import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'log_event.dart';
import 'log_filter.dart';
import 'log_level.dart';
import 'log_printer.dart';
import 'logger_config.dart';

/// A destination for log records.
///
/// Each output owns a [printer] (so the console can be colorized while a file
/// stays plain) and an optional [filter] (so different sinks can capture
/// different levels). The logger calls [handle] for every record; subclasses
/// implement [write], which receives the already-rendered lines.
abstract class LogOutput {
  LogOutput({LogPrinter? printer, this.filter})
      : printer = printer ?? const SimplePrinter();

  /// Renders records for this output.
  final LogPrinter printer;

  /// Optional per-output filter, applied after any global logger filter.
  final LogFilter? filter;

  /// Asynchronous setup (opening files, sockets, …). Safe to call repeatedly.
  Future<void> init() async {}

  /// Applies [filter], renders via [printer], then forwards to [write].
  void handle(LogEvent event) {
    final f = filter;
    if (f != null && !f.shouldLog(event)) return;
    write(event, printer.render(event));
  }

  /// Persists/transmits the rendered [lines]. Must not block the caller.
  void write(LogEvent event, List<String> lines);

  /// Forces buffered data out.
  Future<void> flush() async {}

  /// Releases resources. The output is unusable afterwards.
  Future<void> close() async {}
}

/// Writes lines to the terminal: `stdout` for normal records and (by default)
/// `stderr` for errors. Its default printer colorizes automatically when the
/// attached terminal supports ANSI escapes.
class ConsoleOutput extends LogOutput {
  // ignore: use_super_parameters — `printer` needs a computed (colorized) default.
  ConsoleOutput({
    LogPrinter? printer,
    LogFilter? filter,
    this.errorsToStdErr = true,
  }) : super(
          printer: printer ?? SimplePrinter(LoggerConfig(colorize: _ansi())),
          filter: filter,
        );

  /// Route [LogLevel.error] records to `stderr` instead of `stdout`.
  final bool errorsToStdErr;

  static bool _ansi() {
    try {
      return stdout.supportsAnsiEscapes;
    } catch (_) {
      return false;
    }
  }

  @override
  void write(LogEvent event, List<String> lines) {
    final sink =
        (errorsToStdErr && event.level == LogLevel.error) ? stderr : stdout;
    for (final line in lines) {
      sink.writeln(line);
    }
  }
}

/// Appends lines to a file on disk, asynchronously and without blocking.
///
/// Lines are pushed into a non-blocking [IOSink]. While the file is opening,
/// incoming lines are buffered in memory and flushed once the sink is ready.
///
/// Target resolution: explicit [filePath] → [directoryResolver] result →
/// application-documents directory (`path_provider`) → current working
/// directory (pure-Dart fallback when no platform plugin is registered).
class FileOutput extends LogOutput {
  FileOutput({
    this.filePath,
    this.fileName = 'x_logger.log',
    this.encoding = utf8,
    this.flushEveryWrite = false,
    Future<String> Function()? directoryResolver,
    super.printer,
    super.filter,
  }) : _directoryResolver = directoryResolver;

  /// Absolute path to the log file. When set, [fileName] and directory
  /// resolution are ignored.
  final String? filePath;

  /// File name used when resolving a directory automatically.
  final String fileName;

  /// Encoding used when opening the sink.
  final Encoding encoding;

  /// Flush after every write — crash-safer, but more I/O. Defaults to false.
  final bool flushEveryWrite;

  final Future<String> Function()? _directoryResolver;

  File? _file;
  IOSink? _sink;
  final List<String> _pending = <String>[];
  Completer<void>? _initCompleter;
  bool _closed = false;

  /// The resolved log file, available once [init] has completed.
  File? get file => _file;

  @override
  Future<void> init() {
    final existing = _initCompleter;
    if (existing != null) return existing.future;
    final completer = Completer<void>();
    _initCompleter = completer;
    _open(completer);
    return completer.future;
  }

  Future<void> _open(Completer<void> completer) async {
    try {
      final path = await _resolvePath();
      final file = File(path);
      await file.parent.create(recursive: true);
      final sink =
          file.openWrite(mode: FileMode.writeOnlyAppend, encoding: encoding);

      _file = file;
      _sink = sink;

      if (_pending.isNotEmpty) {
        for (final line in _pending) {
          sink.writeln(line);
        }
        _pending.clear();
        if (flushEveryWrite) await sink.flush();
      }
      completer.complete();
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
    }
  }

  Future<String> _resolvePath() async {
    final explicit = filePath;
    if (explicit != null) return explicit;

    final resolver = _directoryResolver;
    final directory =
        resolver != null ? await resolver() : await _defaultLogDirectory();
    return _join(directory, fileName);
  }

  @override
  void write(LogEvent event, List<String> lines) {
    if (_closed) return;

    final sink = _sink;
    if (sink == null) {
      _pending.addAll(lines);
      // ignore: discarded_futures
      init();
      return;
    }

    for (final line in lines) {
      sink.writeln(line);
    }
    if (flushEveryWrite) {
      // ignore: discarded_futures
      sink.flush();
    }
  }

  @override
  Future<void> flush() async {
    await _awaitInit();
    await _sink?.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _awaitInit();
    final sink = _sink;
    if (sink != null) {
      await sink.flush();
      await sink.close();
    }
    _sink = null;
  }

  Future<void> _awaitInit() async {
    try {
      await _initCompleter?.future;
    } catch (_) {
      // The original error already surfaced to init()'s first caller; teardown
      // must not throw.
    }
  }

  static Future<String> _defaultLogDirectory() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } catch (_) {
      return Directory.current.path;
    }
  }

  static String _join(String directory, String name) {
    final sep = Platform.pathSeparator;
    if (directory.isEmpty) return name;
    return directory.endsWith(sep) ? '$directory$name' : '$directory$sep$name';
  }
}

/// Re-emits records on a broadcast [Stream] of [LogEntry] — subscribe to drive
/// an in-app log console, a debug overlay, or to pipe logs anywhere reactive.
class StreamOutput extends LogOutput {
  StreamOutput({super.printer, super.filter});

  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast();

  /// The live stream of rendered records.
  Stream<LogEntry> get stream => _controller.stream;

  @override
  void write(LogEvent event, List<String> lines) {
    if (!_controller.isClosed) {
      _controller.add(LogEntry(event, lines));
    }
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}

/// Keeps the most recent [capacity] lines in a ring buffer — handy as an
/// export source when no file is attached, or to surface "recent logs" in UI.
class MemoryOutput extends LogOutput {
  MemoryOutput({this.capacity = 200, super.printer, super.filter});

  /// Maximum number of lines retained; oldest are dropped first.
  final int capacity;

  final ListQueue<String> _buffer = ListQueue<String>();

  /// A snapshot of the buffered lines, oldest first.
  List<String> get lines => List<String>.unmodifiable(_buffer);

  /// All buffered lines joined with newlines.
  String dump() => _buffer.join('\n');

  /// Clears the buffer.
  void clear() => _buffer.clear();

  @override
  void write(LogEvent event, List<String> lines) {
    for (final line in lines) {
      _buffer.addLast(line);
      while (_buffer.length > capacity) {
        _buffer.removeFirst();
      }
    }
  }
}

/// Fans a record out to several [children]. Each child applies its own filter
/// and printer, so you can group, e.g., a colorized console and a plain file
/// behind one output.
class MultiOutput extends LogOutput {
  MultiOutput(this.children);

  final List<LogOutput> children;

  @override
  Future<void> init() async {
    for (final child in children) {
      await child.init();
    }
  }

  @override
  void handle(LogEvent event) {
    for (final child in children) {
      child.handle(event);
    }
  }

  @override
  void write(LogEvent event, List<String> lines) {
    // Unused: handle() delegates directly to children.
  }

  @override
  Future<void> flush() async {
    for (final child in children) {
      await child.flush();
    }
  }

  @override
  Future<void> close() async {
    for (final child in children) {
      await child.close();
    }
  }
}
