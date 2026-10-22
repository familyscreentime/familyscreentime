import 'package:family_screen_time/src/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every text exists in every language, with the same placeholders', () {
    final placeholders = RegExp(r'\{(\w+)\}');
    Set<String> names(String text) => {
      for (final m in placeholders.allMatches(text)) m.group(1)!,
    };
    const en = S('en');
    for (final lang in supportedLanguages) {
      final s = S(lang);
      expect(textKeys(lang), containsAll(textKeys('en')), reason: lang);
      expect(textKeys('en'), containsAll(textKeys(lang)), reason: lang);
      for (final key in textKeys('en')) {
        expect(names(s.t(key)), names(en.t(key)), reason: '$lang/$key');
      }
    }
  });

  test('unknown languages fall back to English', () {
    expect(S.of('de_DE').language, 'en');
    expect(S.of('fr-BE').language, 'fr');
    expect(S.of('nl').language, 'nl');
  });

  test('durations read naturally', () {
    const s = S('fr');
    expect(s.duration(const Duration(minutes: 85)), '1 h 25');
    expect(s.duration(const Duration(minutes: 120)), '2 h');
    expect(s.duration(const Duration(minutes: 25)), '25 min');
    expect(s.duration(const Duration(seconds: 40)), '40 s');
  });
}
