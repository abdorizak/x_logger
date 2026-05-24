import 'dart:convert';

import 'log_event.dart';
import 'logger_config.dart';

/// Converts a [LogEvent] into the lines that an output will write.
///
/// This is the seam for customizing *how* a log looks, independent of *where*
/// it goes. Provide a built-in printer ([SimplePrinter], [PrettyPrinter]) or a
/// [CallbackPrinter] for a fully bespoke style.
abstract class LogPrinter {
  const LogPrinter();

  /// Renders [event] into zero or more lines (no trailing newlines).
  List<String> render(LogEvent event);
}

/// A compact, one-record-per-line printer.
///
/// `2026-05-24T09:12:03.114 [INFO] (AgentAlpha) Stream opened {tokens=42}`
///
/// Stack traces are appended as additional lines. When [LoggerConfig.colorize]
/// is set, every produced line is wrapped in the level color.
class SimplePrinter extends LogPrinter {
  const SimplePrinter([this.config = const LoggerConfig()]);

  final LoggerConfig config;

  @override
  List<String> render(LogEvent event) {
    final color = config.colorFor(event.level);

    final header = <String>[];
    if (config.showTimestamp) header.add(config.formatTime(event.time));
    if (config.showEmoji) header.add(event.level.emoji);
    if (config.showLevel) header.add('[${config.labelFor(event.level)}]');
    if (config.showName) header.add('(${event.loggerName})');

    final buffer = StringBuffer();
    if (header.isNotEmpty) {
      buffer
        ..writeAll(header, config.fieldSeparator)
        ..write(config.fieldSeparator);
    }
    buffer.write(event.message);

    if (config.showFields && event.fields.isNotEmpty) {
      final rendered =
          event.fields.entries.map((e) => '${e.key}=${e.value}').join(', ');
      buffer.write(' {$rendered}');
    }
    if (event.error != null) {
      buffer.write('${config.fieldSeparator}| error: ${event.error}');
    }

    final lines = <String>[color.paint(buffer.toString())];
    final stackTrace = event.stackTrace;
    if (stackTrace != null) {
      for (final line in stackTrace.toString().trimRight().split('\n')) {
        lines.add(color.paint(line));
      }
    }
    return lines;
  }
}

/// A decorative, boxed multi-line printer — useful for human-watched consoles.
///
/// ```
/// ┌────────────────────────────────
/// │ ⚠️ WARN  (AgentAlpha)  09:12:03.114
/// ├────────────────────────────────
/// │ Rate limit close
/// │ tokens=42, model=opus
/// └────────────────────────────────
/// ```
class PrettyPrinter extends LogPrinter {
  const PrettyPrinter({
    this.config = const LoggerConfig(colorize: true),
    this.lineLength = 64,
  });

  final LoggerConfig config;
  final int lineLength;

  static const String _vertical = '│';
  static const String _topLeft = '┌';
  static const String _middleLeft = '├';
  static const String _bottomLeft = '└';
  static const String _horizontal = '─';

  @override
  List<String> render(LogEvent event) {
    final color = config.colorFor(event.level);
    final rule = _horizontal * (lineLength - 1);
    final top = color.paint('$_topLeft$rule');
    final middle = color.paint('$_middleLeft$rule');
    final bottom = color.paint('$_bottomLeft$rule');

    final headerParts = <String>[event.emojiTag(config)];
    if (config.showName) headerParts.add('(${event.loggerName})');
    if (config.showTimestamp) headerParts.add(config.formatTime(event.time));

    final lines = <String>[
      top,
      color.paint('$_vertical ${headerParts.join('  ')}'),
      middle,
    ];

    for (final line in event.message.split('\n')) {
      lines.add(color.paint('$_vertical $line'));
    }
    if (config.showFields && event.fields.isNotEmpty) {
      final rendered =
          event.fields.entries.map((e) => '${e.key}=${e.value}').join(', ');
      lines.add(color.paint('$_vertical $rendered'));
    }
    if (event.error != null) {
      lines.add(color.paint('$_vertical error: ${event.error}'));
    }
    final stackTrace = event.stackTrace;
    if (stackTrace != null) {
      lines.add(middle);
      for (final line in stackTrace.toString().trimRight().split('\n')) {
        lines.add(color.paint('$_vertical $line'));
      }
    }
    lines.add(bottom);
    return lines;
  }
}

/// Renders each record as JSON — ideal for structured/machine-readable logs
/// and for inspecting payloads. With [pretty] (the default) the object is
/// indented across multiple lines; otherwise it is a single compact line.
///
/// Field values that aren't natively JSON-encodable fall back to `toString()`,
/// so this never throws on arbitrary `fields`, `error`, or stack traces.
///
/// ```json
/// {
///   "time": "2026-05-24T09:12:03.114",
///   "level": "INFO",
///   "logger": "QuranReader",
///   "message": "ayah rendered",
///   "fields": { "surah": 2, "ayah": 255 }
/// }
/// ```
class JsonPrinter extends LogPrinter {
  const JsonPrinter({this.pretty = true, this.indent = '  '});

  /// Indent the JSON across multiple lines instead of one compact line.
  final bool pretty;

  /// Indentation unit used when [pretty] is true.
  final String indent;

  @override
  List<String> render(LogEvent event) {
    final map = <String, Object?>{
      'time': event.time.toIso8601String(),
      'level': event.level.label,
      'logger': event.loggerName,
      if (event.sequence != null) 'seq': event.sequence,
      'message': event.message,
      if (event.fields.isNotEmpty) 'fields': event.fields,
      if (event.error != null) 'error': event.error.toString(),
      if (event.stackTrace != null) 'stackTrace': event.stackTrace.toString(),
    };

    final encoder = pretty
        ? JsonEncoder.withIndent(indent, _toEncodable)
        : JsonEncoder(_toEncodable);
    final text = encoder.convert(map);
    return pretty ? text.split('\n') : <String>[text];
  }

  static Object? _toEncodable(Object? value) => value.toString();
}

/// Delegates rendering to a user-supplied function — full control over style.
///
/// ```dart
/// CallbackPrinter((e) => ['${e.sequence}: ${e.level.label} ${e.message}']);
/// ```
class CallbackPrinter extends LogPrinter {
  const CallbackPrinter(this.builder);

  final List<String> Function(LogEvent event) builder;

  @override
  List<String> render(LogEvent event) => builder(event);
}

extension on LogEvent {
  String emojiTag(LoggerConfig config) =>
      '${level.emoji} ${config.labelFor(level)}';
}
