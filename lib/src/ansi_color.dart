/// A terminal foreground color, expressed as an xterm 256-color code.
///
/// Wrapping is opt-in: [paint] returns the text unchanged when [code] is null
/// or when styling is disabled at the call site, so the same printer works in
/// both ANSI-capable terminals and plain files.
class AnsiColor {
  const AnsiColor(this.code);

  /// xterm 256-color code, or null for no styling.
  final int? code;

  static const String _reset = '\x1B[0m';

  /// No color; [paint] is a pass-through.
  static const AnsiColor none = AnsiColor(null);

  static const AnsiColor gray = AnsiColor(245);
  static const AnsiColor blue = AnsiColor(39);
  static const AnsiColor cyan = AnsiColor(44);
  static const AnsiColor green = AnsiColor(40);
  static const AnsiColor yellow = AnsiColor(214);
  static const AnsiColor orange = AnsiColor(208);
  static const AnsiColor red = AnsiColor(196);
  static const AnsiColor magenta = AnsiColor(170);
  static const AnsiColor white = AnsiColor(231);

  /// Wraps [text] in escape codes, or returns it unchanged when [code] is null.
  String paint(String text) {
    final c = code;
    if (c == null) return text;
    return '\x1B[38;5;${c}m$text$_reset';
  }
}
