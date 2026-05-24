import 'log_event.dart';
import 'log_level.dart';

/// Decides whether a record should be emitted.
///
/// A filter can be attached globally on the [XLogger] (applied once before
/// dispatch) and/or per [LogOutput] (so, e.g., the file captures everything
/// while the console only shows warnings).
abstract class LogFilter {
  const LogFilter();

  bool shouldLog(LogEvent event);

  /// Passes only when *every* filter passes.
  factory LogFilter.allOf(List<LogFilter> filters) = _AllFilter;

  /// Passes when *any* filter passes.
  factory LogFilter.anyOf(List<LogFilter> filters) = _AnyFilter;
}

/// Passes records at or above [minLevel].
class LevelFilter extends LogFilter {
  const LevelFilter(this.minLevel);

  final LogLevel minLevel;

  @override
  bool shouldLog(LogEvent event) => event.level.isAtLeast(minLevel);
}

/// Passes records for which [predicate] returns true. The most flexible filter:
/// inspect level, name, message, fields — anything on the event.
class PredicateFilter extends LogFilter {
  const PredicateFilter(this.predicate);

  final bool Function(LogEvent event) predicate;

  @override
  bool shouldLog(LogEvent event) => predicate(event);
}

/// Restricts records by logger name. When [allow] is non-null only those names
/// pass; names in [deny] are always rejected.
class NameFilter extends LogFilter {
  const NameFilter({this.allow, this.deny = const <String>{}});

  final Set<String>? allow;
  final Set<String> deny;

  @override
  bool shouldLog(LogEvent event) {
    if (deny.contains(event.loggerName)) return false;
    final allowed = allow;
    return allowed == null || allowed.contains(event.loggerName);
  }
}

/// Inverts another filter.
class NotFilter extends LogFilter {
  const NotFilter(this.inner);

  final LogFilter inner;

  @override
  bool shouldLog(LogEvent event) => !inner.shouldLog(event);
}

class _AllFilter extends LogFilter {
  const _AllFilter(this.filters);

  final List<LogFilter> filters;

  @override
  bool shouldLog(LogEvent event) =>
      filters.every((f) => f.shouldLog(event));
}

class _AnyFilter extends LogFilter {
  const _AnyFilter(this.filters);

  final List<LogFilter> filters;

  @override
  bool shouldLog(LogEvent event) =>
      filters.isEmpty || filters.any((f) => f.shouldLog(event));
}
