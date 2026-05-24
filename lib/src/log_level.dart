/// Severity of a log record, ordered from least to most severe.
///
/// Each level carries a numeric [severity] (used for threshold filtering), a
/// short uppercase [label], and an [emoji] used by decorative printers.
enum LogLevel {
  /// Fine-grained diagnostic information, typically disabled in production.
  debug(0, 'DEBUG', '🐛'),

  /// Normal, expected lifecycle events.
  info(1, 'INFO', '💡'),

  /// Something unexpected that the app can recover from.
  warning(2, 'WARN', '⚠️'),

  /// A failure that likely requires attention.
  error(3, 'ERROR', '⛔');

  const LogLevel(this.severity, this.label, this.emoji);

  /// Ordinal rank. Higher means more severe.
  final int severity;

  /// Short uppercase tag used in rendered output, e.g. `INFO`.
  final String label;

  /// Decorative glyph used by [PrettyPrinter].
  final String emoji;

  /// Whether this level is at least as severe as [other].
  bool isAtLeast(LogLevel other) => severity >= other.severity;
}
