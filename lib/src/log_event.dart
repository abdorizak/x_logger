import 'log_level.dart';

/// An immutable record describing a single log call.
///
/// Outputs receive the structured [LogEvent] (so a JSON/remote sink can use the
/// fields directly) as well as the lines produced by a [LogPrinter].
class LogEvent {
  LogEvent({
    required this.level,
    required this.message,
    required this.loggerName,
    this.fields = const <String, Object?>{},
    this.sequence,
    DateTime? time,
    this.error,
    this.stackTrace,
  }) : time = time ?? DateTime.now();

  /// Severity of this record.
  final LogLevel level;

  /// The human-readable message body.
  final String message;

  /// Name of the [XLogger] instance that emitted this record.
  final String loggerName;

  /// Arbitrary structured key/value context attached to the call.
  final Map<String, Object?> fields;

  /// Monotonic counter assigned by the emitting logger (null if not set).
  final int? sequence;

  /// When the record was created (local time unless rendered as UTC).
  final DateTime time;

  /// Optional associated error object.
  final Object? error;

  /// Optional stack trace captured at the log site.
  final StackTrace? stackTrace;
}

/// A rendered record: the source [event] paired with the lines a printer
/// produced for it. Emitted by [StreamOutput] so UIs can consume both.
class LogEntry {
  const LogEntry(this.event, this.lines);

  final LogEvent event;
  final List<String> lines;
}
