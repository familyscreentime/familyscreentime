/// Canonical JSON: the same value always gives the same bytes, whatever the
/// order its maps were built in. Signatures and comparisons rely on it.
library;

import 'dart:convert';

/// [value] as canonical JSON: map keys sorted, no spaces. Only JSON values
/// (null, bool, num, String, List, Map with String keys) are accepted.
String canonicalJson(Object? value) {
  final out = StringBuffer();
  _write(out, value);
  return out.toString();
}

/// UTF-8 bytes of [canonicalJson].
List<int> canonicalBytes(Object? value) => utf8.encode(canonicalJson(value));

void _write(StringBuffer out, Object? value) {
  switch (value) {
    case null || bool() || String():
      out.write(jsonEncode(value));
    case int():
      out.write(value);
    case double():
      // Whole numbers are written as integers, so that a value read back
      // from JSON (where 3.0 may become 3) signs the same.
      if (value.isFinite && value == value.truncateToDouble()) {
        out.write(value.toInt());
      } else {
        out.write(jsonEncode(value));
      }
    case List():
      out.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) out.write(',');
        _write(out, value[i]);
      }
      out.write(']');
    case Map():
      final keys = [for (final k in value.keys) k as String]..sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out.write(jsonEncode(keys[i]));
        out.write(':');
        _write(out, value[keys[i]]);
      }
      out.write('}');
    default:
      throw ArgumentError.value(value, 'value', 'not a JSON value');
  }
}

/// Whether [a] and [b] are the same JSON value.
bool sameJson(Object? a, Object? b) => canonicalJson(a) == canonicalJson(b);
