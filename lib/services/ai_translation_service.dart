import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

import 'subtitle_service.dart';

enum AiTranslationEngine {
  builtIn,
  gemini,
  openAi,
  libreTranslate,
}

class AiSubtitleTranslationService {
  AiSubtitleTranslationService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  // In-memory cache for translated cue texts: "text_targetLang" -> "translatedText"
  final Map<String, String> _translationCache = {};

  /// Translates a list of [SubtitleCue] into Indonesian (or specified target language).
  Future<List<SubtitleCue>> translateCues(
    List<SubtitleCue> cues, {
    String targetLanguage = 'id',
    AiTranslationEngine engine = AiTranslationEngine.builtIn,
    String? apiKey,
    String? apiEndpoint,
    void Function(double progress)? onProgress,
  }) async {
    if (cues.isEmpty) return const [];

    final resultCues = <SubtitleCue>[];
    final uncachedCues = <SubtitleCue>[];
    final uncachedIndices = <int>[];

    for (var i = 0; i < cues.length; i++) {
      final cue = cues[i];
      final cacheKey = _getCacheKey(cue.text, targetLanguage);
      if (_translationCache.containsKey(cacheKey)) {
        resultCues.add(
          SubtitleCue(
            start: cue.start,
            end: cue.end,
            text: _translationCache[cacheKey]!,
          ),
        );
      } else {
        resultCues.add(cue); // Placeholder to be replaced
        uncachedCues.add(cue);
        uncachedIndices.add(i);
      }
    }

    if (uncachedCues.isEmpty) {
      onProgress?.call(1.0);
      return resultCues;
    }

    // Process uncached cues in batches
    const batchSize = 12;
    final totalBatches = (uncachedCues.length / batchSize).ceil();

    for (var b = 0; b < totalBatches; b++) {
      final start = b * batchSize;
      final end = math.min(start + batchSize, uncachedCues.length);
      final batch = uncachedCues.sublist(start, end);

      List<String> translatedTexts;
      try {
        translatedTexts = await _translateBatch(
          batch.map((c) => c.text).toList(),
          targetLanguage: targetLanguage,
          engine: engine,
          apiKey: apiKey,
          apiEndpoint: apiEndpoint,
        );
      } catch (_) {
        // Fall back to local rule-based naturalizer on failure/offline
        translatedTexts = batch
            .map((c) => applyIndonesianNaturalizer(c.text))
            .toList();
      }

      for (var i = 0; i < batch.length; i++) {
        final cue = batch[i];
        final origIndex = uncachedIndices[start + i];
        final rawTranslated = i < translatedTexts.length
            ? translatedTexts[i]
            : applyIndonesianNaturalizer(cue.text);

        final naturalized = targetLanguage == 'id'
            ? applyIndonesianNaturalizer(rawTranslated)
            : rawTranslated;

        _translationCache[_getCacheKey(cue.text, targetLanguage)] = naturalized;

        resultCues[origIndex] = SubtitleCue(
          start: cue.start,
          end: cue.end,
          text: naturalized,
        );
      }

      onProgress?.call((b + 1) / totalBatches);
    }

    return resultCues;
  }

  String _getCacheKey(String text, String targetLang) => '${text}_$targetLang';

  Future<List<String>> _translateBatch(
    List<String> texts, {
    required String targetLanguage,
    required AiTranslationEngine engine,
    String? apiKey,
    String? apiEndpoint,
  }) async {
    switch (engine) {
      case AiTranslationEngine.gemini:
        if (apiKey != null && apiKey.isNotEmpty) {
          return await _translateWithGemini(
            texts,
            targetLanguage: targetLanguage,
            apiKey: apiKey,
          );
        }
        break;
      case AiTranslationEngine.openAi:
        if (apiKey != null && apiKey.isNotEmpty) {
          return await _translateWithOpenAi(
            texts,
            targetLanguage: targetLanguage,
            apiKey: apiKey,
            apiEndpoint: apiEndpoint,
          );
        }
        break;
      case AiTranslationEngine.libreTranslate:
        if (apiEndpoint != null && apiEndpoint.isNotEmpty) {
          return await _translateWithLibreTranslate(
            texts,
            targetLanguage: targetLanguage,
            apiEndpoint: apiEndpoint,
            apiKey: apiKey,
          );
        }
        break;
      case AiTranslationEngine.builtIn:
        break;
    }

    // Default built-in translator (MyMemory / Open Translation fallback)
    return await _translateWithBuiltIn(texts, targetLanguage: targetLanguage);
  }

  /// Built-in translation using MyMemory / Open API with batch delimiter.
  Future<List<String>> _translateWithBuiltIn(
    List<String> texts, {
    required String targetLanguage,
  }) async {
    final cleanedTexts = texts.map((t) => stripFormatting(t)).toList();
    final combined = cleanedTexts.join('\n---LINE---\n');

    final uri = Uri.parse(
      'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(combined)}&langpair=en|$targetLanguage',
    );

    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final responseData = json['responseData'];
      if (responseData is Map && responseData['translatedText'] != null) {
        final translatedCombined = responseData['translatedText'].toString();
        final lines = translatedCombined.split(RegExp(r'\n?\s*---LINE---\s*\n?'));
        if (lines.length == texts.length) {
          return lines.map((l) => l.trim()).toList();
        }
      }
    }

    // Individual line fallback if batch splitting mismatched
    final results = <String>[];
    for (final text in cleanedTexts) {
      final itemUri = Uri.parse(
        'https://api.mymemory.translated.net/get?q=${Uri.encodeComponent(text)}&langpair=en|$targetLanguage',
      );
      try {
        final res = await _client.get(itemUri).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final json = jsonDecode(res.body);
          final translated = json['responseData']?['translatedText']?.toString();
          if (translated != null && translated.isNotEmpty) {
            results.add(translated.trim());
            continue;
          }
        }
      } catch (_) {}
      results.add(applyIndonesianNaturalizer(text));
    }
    return results;
  }

  /// Gemini API translation implementation.
  Future<List<String>> _translateWithGemini(
    List<String> texts, {
    required String targetLanguage,
    required String apiKey,
  }) async {
    final combined = texts.join('\n[SEP]\n');
    final prompt =
        'Translate the following subtitle lines to natural Indonesian ($targetLanguage) suitable for anime/movie subtitles. Preserve line order, keep the [SEP] delimiter exactly as is, and retain Japanese honorifics (-san, -kun, Senpai, etc.).\n\n$combined';

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=$apiKey',
    );
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ]
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final text = json['candidates']?[0]?['content']?['parts']?[0]?['text']?.toString();
      if (text != null) {
        final parts = text.split(RegExp(r'\n?\s*\[SEP\]\s*\n?'));
        if (parts.length == texts.length) {
          return parts.map((p) => p.trim()).toList();
        }
      }
    }
    return await _translateWithBuiltIn(texts, targetLanguage: targetLanguage);
  }

  /// OpenAI API translation implementation.
  Future<List<String>> _translateWithOpenAi(
    List<String> texts, {
    required String targetLanguage,
    required String apiKey,
    String? apiEndpoint,
  }) async {
    final endpoint = apiEndpoint?.isNotEmpty == true
        ? apiEndpoint!
        : 'https://api.openai.com/v1/chat/completions';
    final combined = texts.join('\n---SPLIT---\n');

    final response = await _client.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {
            'role': 'system',
            'content':
                'You are a professional Indonesian anime/movie subtitle translator. Translate lines into natural Indonesian. Keep ---SPLIT--- intact and maintain line count.'
          },
          {'role': 'user', 'content': combined}
        ],
        'temperature': 0.3,
      }),
    ).timeout(const Duration(seconds: 10));

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final content = json['choices']?[0]?['message']?['content']?.toString();
      if (content != null) {
        final parts = content.split(RegExp(r'\n?\s*---SPLIT---\s*\n?'));
        if (parts.length == texts.length) {
          return parts.map((p) => p.trim()).toList();
        }
      }
    }
    return await _translateWithBuiltIn(texts, targetLanguage: targetLanguage);
  }

  /// LibreTranslate API implementation.
  Future<List<String>> _translateWithLibreTranslate(
    List<String> texts, {
    required String targetLanguage,
    required String apiEndpoint,
    String? apiKey,
  }) async {
    final url = Uri.parse(
      apiEndpoint.endsWith('/translate')
          ? apiEndpoint
          : '$apiEndpoint/translate',
    );
    final results = <String>[];
    for (final text in texts) {
      final response = await _client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'q': stripFormatting(text),
          'source': 'auto',
          'target': targetLanguage,
          'format': 'text',
          if (apiKey != null && apiKey.isNotEmpty) 'api_key': apiKey,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        final translated = json['translatedText']?.toString();
        if (translated != null && translated.isNotEmpty) {
          results.add(translated.trim());
          continue;
        }
      }
      results.add(applyIndonesianNaturalizer(text));
    }
    return results;
  }

  /// Strips formatting tags (ASS styles, WebVTT tags, HTML) before translation.
  static String stripFormatting(String text) {
    return text
        .replaceAll(RegExp(r'\{[^}]*\}'), '')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\h', ' ')
        .trim();
  }

  /// Post-processor for Indonesian Subtitles ("sekelas subtitle indo umum").
  /// Transforms robotic/literal phrases into standard natural Indonesian subtitle phrasing.
  static String applyIndonesianNaturalizer(String text) {
    if (text.isEmpty) return text;

    var s = text;

    // Common literal English-Indonesian fixes for natural subtitle flow
    final replacements = <RegExp, String>{
      RegExp(r'\bI see\b', caseSensitive: false): 'Begitu ya',
      RegExp(r'\bAre you okay\?\b', caseSensitive: false): 'Kamu baik-baik saja?',
      RegExp(r'\bAre you alright\?\b', caseSensitive: false): 'Kamu baik-baik saja?',
      RegExp(r'\bIt can’t be helped\b|\bIt cannot be helped\b', caseSensitive: false): 'Mau bagaimana lagi',
      RegExp(r'\bWhat should I do\?\b', caseSensitive: false): 'Harus bagaimana ini?',
      RegExp(r'\bDon’t worry\b|\bDont worry\b', caseSensitive: false): 'Jangan khawatir',
      RegExp(r'\bNo way!\b', caseSensitive: false): 'Tidak mungkin!',
      RegExp(r'\bWhat is it\?\b', caseSensitive: false): 'Ada apa?',
      RegExp(r'\bWhat happened\?\b', caseSensitive: false): 'Apa yang terjadi?',
      RegExp(r'\bI’m coming\b|\bIm coming\b', caseSensitive: false): 'Aku datang',
      RegExp(r'\bThank you very much\b', caseSensitive: false): 'Terima kasih banyak',
      RegExp(r'\bThank you\b', caseSensitive: false): 'Terima kasih',
      RegExp(r'\bYou’re welcome\b|\bYou are welcome\b', caseSensitive: false): 'Sama-sama',
      RegExp(r'\bExcuse me\b', caseSensitive: false): 'Permisi',
      RegExp(r'\bI understand\b', caseSensitive: false): 'Aku mengerti',
      RegExp(r'\bI got it\b', caseSensitive: false): 'Aku paham',
      RegExp(r'\bOf course\b', caseSensitive: false): 'Tentu saja',
      RegExp(r'\bWait a minute\b|\bWait a second\b', caseSensitive: false): 'Tunggu sebentar',
      RegExp(r'\bWait!\b', caseSensitive: false): 'Tunggu!',
      RegExp(r'\bShut up!\b', caseSensitive: false): 'Diam!',
      RegExp(r'\bBe careful!\b', caseSensitive: false): 'Hati-hati!',
      RegExp(r'\bLook out!\b', caseSensitive: false): 'Awas!',
      RegExp(r'\bThat’s right\b|\bThats right\b', caseSensitive: false): 'Itu benar',
      RegExp(r'\bIs that so\?\b', caseSensitive: false): 'Benarkah?',
      RegExp(r'\bNever mind\b', caseSensitive: false): 'Lupakan saja',
      RegExp(r'\bWhat’s wrong\?\b|\bWhats wrong\?\b', caseSensitive: false): 'Ada apa?',
      RegExp(r'\bLet’s go!\b|\bLets go!\b', caseSensitive: false): 'Ayo pergi!',
    };

    for (final entry in replacements.entries) {
      s = s.replaceAll(entry.key, entry.value);
    }

    // Fix awkward automated machine translation phrasing in Indonesian
    s = s
        .replaceAll(RegExp(r'\bsedang datang\b', caseSensitive: false), 'datang')
        .replaceAll(RegExp(r'\bsaya rasa\b', caseSensitive: false), 'kurasai')
        .replaceAll(RegExp(r'\baku rasa\b', caseSensitive: false), 'kurasa')
        .replaceAll(RegExp(r'\bkamu adalah\b', caseSensitive: false), 'kau')
        .replaceAll(RegExp(r'\bdiriku adalah\b', caseSensitive: false), 'aku')
        .replaceAll(RegExp(r'\btidak bisa\b', caseSensitive: false), 'tak bisa')
        .replaceAll(RegExp(r'\btidak ada\b', caseSensitive: false), 'tak ada')
        .replaceAll(RegExp(r'\btidak mau\b', caseSensitive: false), 'tak mau')
        .replaceAll(RegExp(r'\btidak tahu\b', caseSensitive: false), 'tak tahu');

    return s;
  }
}
