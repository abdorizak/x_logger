import 'ansi_color.dart';
import 'log_level.dart';

/// Turns a [DateTime] into the string shown in the header.
typedef DateTimeFormatter = String Function(DateTime time);

/// Ready-made timestamp formatters (no `intl` dependency required).
class TimeFormats {
  const TimeFormats._();

  static String _pad2(int n) => n.toString().padLeft(2, '0');
  static String _pad3(int n) => n.toString().padLeft(3, '0');

  /// Full ISO-8601, e.g. `2026-05-24T09:12:03.114`.
  static String iso(DateTime t) => t.toIso8601String();

  /// Clock time only, e.g. `09:12:03.114`.
  static String clock(DateTime t) =>
      '${_pad2(t.hour)}:${_pad2(t.minute)}:${_pad2(t.second)}'
      '.${_pad3(t.millisecond)}';

  /// Date and time, e.g. `2026-05-24 09:12:03`.
  static String dateTime(DateTime t) =>
      '${t.year}-${_pad2(t.month)}-${_pad2(t.day)} '
      '${_pad2(t.hour)}:${_pad2(t.minute)}:${_pad2(t.second)}';
}

/// Describes how a [LogPrinter] renders a record: which header fields to show,
/// how to format the timestamp, whether to colorize, and which color/label to
/// use per level. Immutable; derive variants with [copyWith].
class LoggerConfig {
  const LoggerConfig({
    this.minLevel = LogLevel.debug,
    this.showTimestamp = true,
    this.showLevel = true,
    this.showName = true,
    this.showFields = true,
    this.showEmoji = false,
    this.useUtc = false,
    this.colorize = false,
    this.fieldSeparator = ' ',
    this.timeFormatter,
    this.levelColors = defaultLevelColors,
    this.levelLabels,
  });

  /// Default minimum level when the logger builds a [LevelFilter] for you.
  final LogLevel minLevel;

  /// Whether to prepend a timestamp.
  final bool showTimestamp;

  /// Whether to include the `[LEVEL]` tag.
  final bool showLevel;

  /// Whether to include the `(loggerName)` tag.
  final bool showName;

  /// Whether to append structured [LogEvent.fields].
  final bool showFields;

  /// Whether to prepend the per-level emoji (🐛 💡 ⚠️ ⛔).
  final bool showEmoji;

  /// Render timestamps in UTC rather than local time.
  final bool useUtc;

  /// Wrap output in ANSI color codes (terminals only — keep false for files).
  final bool colorize;

  /// Separator placed between header fields and the message.
  final String fieldSeparator;

  /// Custom timestamp formatter. When null, [TimeFormats.iso] is used.
  final DateTimeFormatter? timeFormatter;

  /// Per-level colors used when [colorize] is true.
  final Map<LogLevel, AnsiColor> levelColors;

  /// Optional per-level label overrides (e.g. localized or shortened tags).
  final Map<LogLevel, String>? levelLabels;

  /// Sensible default color scheme.
  static const Map<LogLevel, AnsiColor> defaultLevelColors =
      <LogLevel, AnsiColor>{
    LogLevel.debug: AnsiColor.gray,
    LogLevel.info: AnsiColor.blue,
    LogLevel.warning: AnsiColor.yellow,
    LogLevel.error: AnsiColor.red,
  };

  /// The color to apply for [level], honoring [colorize].
  AnsiColor colorFor(LogLevel level) {
    if (!colorize) return AnsiColor.none;
    return levelColors[level] ?? AnsiColor.none;
  }

  /// The label to display for [level], honoring [levelLabels].
  String labelFor(LogLevel level) => levelLabels?[level] ?? level.label;

  /// Formats [time] using [useUtc] and [timeFormatter].
  String formatTime(DateTime time) {
    final value = useUtc ? time.toUtc() : time;
    return (timeFormatter ?? TimeFormats.iso)(value);
  }

  LoggerConfig copyWith({
    LogLevel? minLevel,
    bool? showTimestamp,
    bool? showLevel,
    bool? showName,
    bool? showFields,
    bool? showEmoji,
    bool? useUtc,
    bool? colorize,
    String? fieldSeparator,
    DateTimeFormatter? timeFormatter,
    Map<LogLevel, AnsiColor>? levelColors,
    Map<LogLevel, String>? levelLabels,
  }) {
    return LoggerConfig(
      minLevel: minLevel ?? this.minLevel,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showLevel: showLevel ?? this.showLevel,
      showName: showName ?? this.showName,
      showFields: showFields ?? this.showFields,
      showEmoji: showEmoji ?? this.showEmoji,
      useUtc: useUtc ?? this.useUtc,
      colorize: colorize ?? this.colorize,
      fieldSeparator: fieldSeparator ?? this.fieldSeparator,
      timeFormatter: timeFormatter ?? this.timeFormatter,
      levelColors: levelColors ?? this.levelColors,
      levelLabels: levelLabels ?? this.levelLabels,
    );
  }
}
