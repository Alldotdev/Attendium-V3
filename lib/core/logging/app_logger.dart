import 'dart:developer' as developer;

enum LogLevel { debug, info, warning, error }

class AppLogger {
  static LogLevel minimumLevel = LogLevel.info;

  static void debug(String message, [String? tag]) {
    _log(LogLevel.debug, message, tag);
  }

  static void info(String message, [String? tag]) {
    _log(LogLevel.info, message, tag);
  }

  static void warning(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.warning, message, tag, error, stackTrace);
  }

  static void error(String message, [String? tag, Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, message, tag, error, stackTrace);
  }

  static void _log(
    LogLevel level,
    String message,
    String? tag, [
    Object? error,
    StackTrace? stackTrace,
  ]) {
    if (level.index < minimumLevel.index) return;

    final sanitizedMessage = _scrubSecrets(message);
    final formattedTag = tag ?? 'Attendium';
    final timestamp = DateTime.now().toIso8601String();

    developer.log(
      '[$timestamp] [${level.name.toUpperCase()}] [$formattedTag] $sanitizedMessage',
      name: formattedTag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  /// Scrubs API keys, passwords, and tokens from log lines.
  static String _scrubSecrets(String text) {
    var sanitized = text;
    // Scrub potential bearer tokens
    sanitized = sanitized.replaceAll(
      RegExp(r'(Bearer\s+)[A-Za-z0-9\-._~+/]+=*', caseSensitive: false),
      r'$1[SCRUBBED_TOKEN]',
    );
    // Scrub API keys (OpenAI / Gemini / Google)
    sanitized = sanitized.replaceAll(
      RegExp(r'(AIza[0-9A-Za-z-_]{35}|sk-[a-zA-Z0-9]{20,})'),
      '[SCRUBBED_KEY]',
    );
    // Scrub key/password assignments in JSON/strings
    sanitized = sanitized.replaceAll(
      RegExp(r'("?(?:api_?key|password|secret|token)"?\s*[:=]\s*)"[^"]+"', caseSensitive: false),
      r'$1"[SCRUBBED]"',
    );
    return sanitized;
  }
}
