typedef void MissingKeyTranslationHandler(String key);

/// Translator for simple values
class SimpleTranslator {
  final Map<dynamic, dynamic>? decodedMap;
  final String? fallbackKey;
  final String? keySeparator;
  final MissingKeyTranslationHandler? missingKeyTranslationHandler;

  String key;
  Map<String?, String>? translationParams;

  SimpleTranslator(
    this.decodedMap,
    this.key,
    this.keySeparator, {
    this.fallbackKey,
    this.translationParams,
    this.missingKeyTranslationHandler,
  });

  /// Return the translation of the key provided, otherwise return the fallbackKey (if provided), otherwise return the same key
  String translate() {
    String translation = _translateWithKeyFallback();
    if (translationParams != null) {
      translation = _replaceParams(translation);
    }
    return translation;
  }

  String _replaceParams(String translation) {
    for (final String? paramKey in translationParams!.keys) {
      translation = translation.replaceAll(
          RegExp('{$paramKey}'), translationParams![paramKey]!);
    }
    return translation;
  }

  String _translateWithKeyFallback() {
    return [
          _decodeFromMap(key),
          _decodeFromMap(fallbackKey ?? ""),
          fallbackKey,
          key
        ].firstWhere((translation) => translation != null) ??
        key;
  }

  String? _decodeFromMap(final String key) {
    final dynamic subMap = calculateSubmap(key);
    if (subMap is List) {
      final String lastKeyPart = key.split(this.keySeparator!).last;
      final result = subMap[int.parse(lastKeyPart)] is String
          ? subMap[int.parse(lastKeyPart)]
          : null;

      if (result == null && key.length > 0) {
        missingKeyTranslationHandler!(key);
      }

      return result;
    } else if (subMap is Map) {
      final String lastKeyPart = key.split(this.keySeparator!).last;
      final result = subMap[lastKeyPart] is String ? subMap[lastKeyPart] : null;

      if (result == null && key.length > 0) {
        missingKeyTranslationHandler!(key);
      }

      return result;
    }
  }

  dynamic calculateSubmap(final String translationKey) {
    final List<String> translationKeySplitted =
        translationKey.split(this.keySeparator!);
    translationKeySplitted.removeLast();
    dynamic decodedSubMap = decodedMap;
    translationKeySplitted.forEach((listKey) {
      final subMap = (decodedSubMap ?? Map())[listKey];
      decodedSubMap = subMap;
    });
    return decodedSubMap ?? {};
  }
}
