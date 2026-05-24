![x_logger](https://raw.githubusercontent.com/abdorizak/x_logger/main/doc/banner.png)

# x_logger

[![pub package](https://img.shields.io/pub/v/x_logger.svg)](https://pub.dev/packages/x_logger)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![platforms](https://img.shields.io/badge/platforms-android%20%7C%20ios%20%7C%20macos%20%7C%20windows%20%7C%20linux-blue.svg)](#platform-notes)

Configurable logging for Flutter: **named loggers**, **levels**, **pretty / JSON
/ colored** output, **filtering**, and **async export** of the log history to a
file your users can share — all configured once and reused across your app.

```text
09:12:03.114 💡 [INFO]  (QuranReader) ayah rendered {surah=2, ayah=255}
09:12:03.330 ⚠️ [WARN]  (AudioPlayer) buffering {bufferMs=1200}
09:12:03.440 ⛔ [ERROR] (AudioPlayer) playback stopped | error: Bad state
```

## Contents

- [Features](#features)
- [Architecture](#architecture)
- [Install](#install)
- [Quick start](#quick-start)
- [Zero config](#zero-config-no-customization)
- [Configure once, label with children](#recommended-configure-once-label-with-children)
- [Customizing the style](#customizing-the-style) · [JSON](#json-output-pretty-printed) · [Color](#custom-colors)
- [Filtering](#filtering)
- [Outputs](#outputs)
- [Writing to a file](#writing-to-a-file) · [Exporting / sharing](#exporting--sharing-the-log)
- [Example app](#example-app) · [Platform notes](#platform-notes)

## Features

- **Named instances** — one logger per part of your app (`QuranReader`,
  `AudioPlayer`, `Database`, …).
- **Levels** — `debug`, `info`, `warning`, `error`.
- **Pluggable style (printers)** — `SimplePrinter`, `PrettyPrinter` (boxed +
  emoji), or `CallbackPrinter` for a fully bespoke format.
- **Color** — ANSI 256-color output with a per-level scheme; auto-enabled when
  the terminal supports it, off for files.
- **Customizable header** — toggle timestamp / level / name / fields, choose a
  timestamp format (`iso`, `clock`, `dateTime`, or your own), UTC or local.
- **Filtering** — by level, name, or any predicate; combine with `allOf`/`anyOf`;
  apply globally and/or per output.
- **Structured fields** — attach `{key: value}` context to any call.
- **Multiple destinations** — `ConsoleOutput`, async `FileOutput`,
  `StreamOutput` (for in-app log views), `MemoryOutput` (ring buffer),
  `MultiOutput` (fan-out). Each owns its own printer + filter.
- **Export API** — get the backing `File` or read the whole history as a string.

## Architecture

A record flows through three independent, swappable stages:

```text
log()  →  LogFilter (global)  →  for each LogOutput:  LogFilter (local) → LogPrinter → write
```

- **`LogFilter`** decides *whether* to log.
- **`LogPrinter`** decides *how* it looks (style, color).
- **`LogOutput`** decides *where* it goes.

## Install

```yaml
dependencies:
  x_logger: ^0.2.0
```

```bash
flutter pub get
```

```dart
import 'package:x_logger/x_logger.dart';
```

## Quick start

```dart
final log = XLogger(name: 'QuranReader');

log.debug('Opening surah');
log.info('Ayah rendered', fields: {'surah': 2, 'ayah': 255});
log.warning('Slow font load');
log.error('Render failed', error: e, stackTrace: s);
```

```text
2026-05-24T09:12:03.114 [INFO] (QuranReader) Ayah rendered {surah=2, ayah=255}
```

## Zero config (no customization)

Don't want to configure anything? `XLogger.standard()` wires up a colorized
console **and** an on-device file in one line, so export works immediately:

```dart
final log = XLogger.standard(name: 'QuranReader');

log.info('ready');
log.error('failed', error: e, stackTrace: s);

// Already exportable — the file lives in the app documents directory.
final file = await log.getLogFile();
final text = await log.exportLogsAsString();
```

`XLogger.standard` accepts optional `name`, `fileName`, and `minLevel`; that's
all you need to touch.

## Recommended: configure once, label with children

Set the logger up **one time** at app startup, then create cheap `child()`
loggers wherever you want to tag a subsystem. Children **share** the parent's
config, filter, and outputs — the same single file, console, and buffers. They
cost almost nothing (just a name), so this does **not** duplicate I/O or memory.

```dart
// lib/logging.dart — created once, reused everywhere.
final appLog = XLogger(
  name: 'WACYI',
  outputs: [ConsoleOutput(), FileOutput(fileName: 'app.log')],
);

// Anywhere in the app — these reuse appLog's file & console:
final quranLog = appLog.child('QuranReader');
final audioLog = appLog.child('AudioPlayer');

quranLog.info('ayah rendered');     // (QuranReader) ...
audioLog.warning('buffering');      // (AudioPlayer) ... → same app.log
```

The label after `child(...)` shows up in `(parentheses)` so you can tell which
part of the app wrote each line — handy when you read the exported file.

> Create the logger **once** (a top-level variable, a DI singleton, etc.) and
> reuse it. The only thing to avoid is constructing a new `XLogger`/`FileOutput`
> repeatedly (e.g. inside `build()`), which would open redundant file handles.

If you don't care about per-subsystem labels at all, just use one logger
everywhere and skip `child()` entirely.

## Customizing the style

`LoggerConfig` drives the built-in printers:

```dart
final log = XLogger(
  name: 'Database',
  config: const LoggerConfig(
    showTimestamp: true,
    showLevel: true,
    showName: false,           // hide "(Database)"
    showFields: true,
    showEmoji: true,           // prepend 🐛 💡 ⚠️ ⛔
    useUtc: true,
    colorize: true,
    timeFormatter: TimeFormats.clock,   // 09:12:03.114
  ),
);
```

With `showEmoji`, each level is tagged with its glyph:

```text
09:12:03.114 🐛 [DEBUG] (Database) cache warmed
09:12:03.221 💡 [INFO]  (Database) row inserted
09:12:03.330 ⚠️ [WARN]  (Database) slow query
09:12:03.440 ⛔ [ERROR] (Database) connection lost
```

Use the boxed `PrettyPrinter` on a watched console:

```dart
final log = XLogger(
  name: 'AudioPlayer',
  outputs: [ConsoleOutput(printer: const PrettyPrinter())],
);
```

```text
┌──────────────────────────────
│ ⚠️ WARN  (AudioPlayer)  09:12:03.114
├──────────────────────────────
│ Buffering
└──────────────────────────────
```

Or take **full control** of the format with `CallbackPrinter`:

```dart
ConsoleOutput(
  printer: CallbackPrinter(
    (e) => ['#${e.sequence} ${e.level.label.padRight(5)} ${e.message}'],
  ),
);
```

### JSON output (pretty-printed)

Use `JsonPrinter` to render records as JSON — great for structured logs and for
inspecting payloads. It pretty-prints by default; pass `pretty: false` for a
single compact line. Values that aren't JSON-encodable fall back to `toString()`,
so it never throws.

```dart
final log = XLogger(
  name: 'QuranReader',
  outputs: [ConsoleOutput(printer: const JsonPrinter())],
);

log.info('search request', fields: {
  'query': 'mercy',
  'filters': {'surah': [1, 2, 18], 'exact': false},
});
```

```json
{
  "time": "2026-05-24T09:12:03.114",
  "level": "INFO",
  "logger": "QuranReader",
  "seq": 0,
  "message": "search request",
  "fields": {
    "query": "mercy",
    "filters": {
      "surah": [1, 2, 18],
      "exact": false
    }
  }
}
```

### Custom colors

```dart
const LoggerConfig(
  colorize: true,
  levelColors: {
    LogLevel.debug: AnsiColor.gray,
    LogLevel.info: AnsiColor.cyan,
    LogLevel.warning: AnsiColor.orange,
    LogLevel.error: AnsiColor.magenta,
  },
);
```

## Filtering

```dart
// Global: only warnings and above.
XLogger(name: 'A', filter: const LevelFilter(LogLevel.warning));

// By predicate (inspect level, name, message, or fields).
PredicateFilter((e) => e.fields['important'] == true);

// By logger name.
const NameFilter(allow: {'QuranReader', 'AudioPlayer'});

// Combine.
LogFilter.allOf([
  const LevelFilter(LogLevel.info),
  NotFilter(const NameFilter(deny: {'Noisy'})),
]);
```

Filters also attach per output, so each sink can capture a different slice:

```dart
XLogger(
  name: 'QuranReader',
  filter: const LevelFilter(LogLevel.debug),   // file gets everything
  outputs: [
    FileOutput(fileName: 'app.log'),
    ConsoleOutput(filter: const LevelFilter(LogLevel.warning)), // console: warns+
  ],
);
```

## Outputs

```dart
XLogger(
  name: 'QuranReader',
  outputs: [
    ConsoleOutput(),                       // colorized; errors → stderr
    FileOutput(fileName: 'app.log'),       // async, non-blocking
    StreamOutput(),                        // for an in-app log view
    MemoryOutput(capacity: 500),           // recent-lines ring buffer
  ],
);
```

Subscribe to a `StreamOutput` to render logs live in the UI:

```dart
log.stream?.listen((entry) {
  setState(() => visibleLines.addAll(entry.lines));
});
```

## Writing to a file

By default `FileOutput` writes into the app's documents directory — resolved
automatically via `path_provider` on Android, iOS, macOS, Windows and Linux, no
setup required:

```dart
FileOutput(fileName: 'agent.log'); // app documents dir, all platforms
```

Override the location when you need to — a custom directory or an explicit path:

```dart
FileOutput(
  fileName: 'agent.log',
  directoryResolver: () async =>
      (await getApplicationSupportDirectory()).path,
);

FileOutput(filePath: '/some/writable/dir/agent.log');
```

Writes are buffered into an async `IOSink`, so logging never blocks the UI
thread. Set `flushEveryWrite: true` for crash-safety at the cost of more I/O.

## Exporting / sharing the log

```dart
await log.flush();                          // ensure buffered writes landed

final file = await log.getLogFile();        // the on-device log file
final history = await log.exportLogsAsString();
final recent = log.memoryDump;              // from a MemoryOutput, if attached

await log.dispose();                        // flush + close all outputs
```

To let the user share the file with anyone, hand its path to a share plugin:

```dart
final file = await log.getLogFile();
if (file != null) {
  await Share.shareXFiles([XFile(file.path)]); // package:share_plus
}
```

## Example app

A runnable Flutter app lives in [`example/`](example/). It has a button for
every level (🐛 Debug, 💡 Info, ⚠️ Warning, ⛔ Error) plus a JSON-payload
button, a **Text ⇄ Pretty JSON** toggle that re-renders the captured records
live, and an **Export & share** button that writes the log file and opens the
native share sheet — so you can verify export on every platform.

```bash
cd example
flutter pub get

flutter run -d android     # Android device/emulator
flutter run -d ios         # iOS device/simulator
flutter run -d macos       # macOS desktop
flutter run -d windows     # Windows desktop
flutter run -d linux       # Linux desktop
```

Platform folders for all five targets are checked in. Export behavior:

| Platform | Export to file | Native share sheet |
|----------|----------------|--------------------|
| Android  | ✅             | ✅                 |
| iOS      | ✅             | ✅                 |
| macOS    | ✅             | ✅                 |
| Windows  | ✅             | ✅                 |
| Linux    | ✅             | falls back to showing the file path |

On Linux, `share_plus` does not implement file sharing, so the example reports
the on-device file path instead — the export itself still succeeds.

## Platform notes

- This is a Flutter package. File / console output use `dart:io`, so they run on
  iOS, Android, and desktop — **not** Flutter web (use `ConsoleOutput` only, or
  `StreamOutput`/`MemoryOutput` there).
- `FileOutput` writes on-device; the user exports/shares the file from the app.
  In unit tests (no platform plugin), prefer an explicit `filePath`.

## License

See [LICENSE](LICENSE).
