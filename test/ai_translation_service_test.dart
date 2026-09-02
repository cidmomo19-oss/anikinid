import 'package:flutter_test/flutter_test.dart';
import 'package:anikin/services/ai_translation_service.dart';
import 'package:anikin/services/subtitle_service.dart';

void main() {
  group('AiSubtitleTranslationService tests', () {
    late AiSubtitleTranslationService service;

    setUp(() {
      service = AiSubtitleTranslationService();
    });

    test('translateCues with empty list returns empty list', () async {
      final result = await service.translateCues([]);
      expect(result, isEmpty);
    });

    test('Indonesian naturalizer fixes common literal phrases', () {
      expect(
        AiSubtitleTranslationService.applyIndonesianNaturalizer('I see.'),
        contains('Begitu ya'),
      );
      expect(
        AiSubtitleTranslationService.applyIndonesianNaturalizer('Are you okay?'),
        equals('Kamu baik-baik saja?'),
      );
      expect(
        AiSubtitleTranslationService.applyIndonesianNaturalizer("It can't be helped"),
        equals('Mau bagaimana lagi'),
      );
      expect(
        AiSubtitleTranslationService.applyIndonesianNaturalizer('Don’t worry'),
        equals('Jangan khawatir'),
      );
      expect(
        AiSubtitleTranslationService.applyIndonesianNaturalizer('Wait!'),
        equals('Tunggu!'),
      );
      expect(
        AiSubtitleTranslationService.applyIndonesianNaturalizer('Look out!'),
        equals('Awas!'),
      );
      expect(
        AiSubtitleTranslationService.applyIndonesianNaturalizer('I understand'),
        equals('Aku mengerti'),
      );
    });

    test('Formatting tags are stripped correctly', () {
      final input = r'{\pos(192,200)}<i>Hello World</i>';
      final stripped = AiSubtitleTranslationService.stripFormatting(input);
      expect(stripped, equals('Hello World'));
    });

    test('translateCues translates cues and applies naturalization', () async {
      final cues = [
        const SubtitleCue(
          start: Duration(seconds: 1),
          end: Duration(seconds: 3),
          text: 'I see. Are you okay?',
        ),
        const SubtitleCue(
          start: Duration(seconds: 4),
          end: Duration(seconds: 6),
          text: 'Wait! Look out!',
        ),
      ];

      final translated = await service.translateCues(
        cues,
        targetLanguage: 'id',
      );

      expect(translated.length, equals(2));
      expect(translated[0].start, equals(cues[0].start));
      expect(translated[0].end, equals(cues[0].end));
      expect(translated[0].text, contains('Begitu ya'));
      expect(translated[0].text, contains('Kamu baik-baik saja?'));
      expect(translated[1].text, contains('Tunggu!'));
      expect(translated[1].text, contains('Awas!'));
    });

    test('translateCues caches results for repeated calls', () async {
      final cues = [
        const SubtitleCue(
          start: Duration(seconds: 1),
          end: Duration(seconds: 3),
          text: 'I understand',
        ),
      ];

      final firstRun = await service.translateCues(cues, targetLanguage: 'id');
      final secondRun = await service.translateCues(cues, targetLanguage: 'id');

      expect(firstRun.first.text, equals(secondRun.first.text));
      expect(secondRun.first.text, equals('Aku mengerti'));
    });
  });
}
