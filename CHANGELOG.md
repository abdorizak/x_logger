## 0.1.0

- Initial release.
- Named loggers with `debug`/`info`/`warning`/`error` levels and structured `fields`.
- Pluggable printers: `SimplePrinter`, `PrettyPrinter`, `JsonPrinter`, `CallbackPrinter`.
- Toggleable timestamp / level / name / emoji, custom time formats, and ANSI color.
- Filtering: `LevelFilter`, `PredicateFilter`, `NameFilter`, `NotFilter`,
  `LogFilter.allOf`/`anyOf` — applied globally and/or per output.
- Outputs: `ConsoleOutput`, async `FileOutput` (on-device path via `path_provider`),
  `StreamOutput`, `MemoryOutput`, `MultiOutput`.
- Export API: `getLogFile()` and `exportLogsAsString()`.
- `XLogger.standard()` zero-config factory and `child()` loggers that share outputs.
