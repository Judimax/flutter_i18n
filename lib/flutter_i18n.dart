import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_i18n/loaders/file_translation_loader.dart';
import 'package:flutter_i18n/loaders/local_translation_loader.dart';
import 'package:flutter_i18n/loaders/namespace_file_translation_loader.dart';
import 'package:flutter_i18n/loaders/network_file_translation_loader.dart';
import 'package:flutter_i18n/loaders/translation_loader.dart';
import 'package:flutter_i18n/models/loading_status.dart';
import 'package:flutter_i18n/utils/plural_translator.dart';
import 'package:flutter_i18n/utils/simple_translator.dart';
import 'package:flutter_i18n/utils/translation_cache.dart';
import 'package:intl/intl.dart' as intl;

export 'flutter_i18n_delegate.dart';
export 'loaders/e2e_file_translation_loader.dart';
export 'loaders/file_translation_loader.dart';
export 'loaders/namespace_file_translation_loader.dart';
export 'loaders/network_file_translation_loader.dart';
export 'loaders/translation_loader.dart';
export 'widgets/I18nPlural.dart';
export 'widgets/I18nText.dart';

typedef void MissingTranslationHandler(String key, Locale? locale);

/// Facade used to hide the loading and translations logic
class FlutterI18n {
  TranslationLoader? translationLoader;
  late MissingTranslationHandler missingTranslationHandler;
  String? keySeparator;

  Map<dynamic, dynamic>? decodedMap;

  final _localeStream = StreamController<Locale?>.broadcast();

  // ignore: close_sinks
  final _loadingStream = StreamController<LoadingStatus>.broadcast();

  Stream<LoadingStatus> get loadingStream => _loadingStream.stream;

  Stream<bool> get isLoadedStream => loadingStream
      .map((loadingStatus) => loadingStatus == LoadingStatus.loaded);

  FlutterI18n(
    TranslationLoader? translationLoader,
    String keySeparator, {
    MissingTranslationHandler? missingTranslationHandler,
  }) {
    this.translationLoader = translationLoader ?? FileTranslationLoader();
    this._loadingStream.add(LoadingStatus.notLoaded);
    this.missingTranslationHandler =
        missingTranslationHandler ?? (key, locale) {};
    this.keySeparator = keySeparator;
  }

  /// Used to load the locale translation file
  Future<bool> load() async {
    this._loadingStream.add(LoadingStatus.loading);
    decodedMap = await translationLoader!.load();
    translationCache.setLocale(locale.toString(), decodedMap!);
    _localeStream.add(locale);
    this._loadingStream.add(LoadingStatus.loaded);
    return true;
  }

  /// The locale used for the translation logic
  get locale => this.translationLoader!.locale;

  /// Facade method to the plural translation logic
  static String plural(final BuildContext context, final String translationKey,
      final int pluralValue) {
    final FlutterI18n currentInstance = _retrieveCurrentInstance(context)!;
    final PluralTranslator pluralTranslator = PluralTranslator(
      currentInstance.decodedMap,
      translationKey,
      currentInstance.keySeparator,
      pluralValue,
      missingKeyTranslationHandler: (key) {
        currentInstance.missingTranslationHandler(key, currentInstance.locale);
      },
    );
    return pluralTranslator.plural();
  }

  /// Facade method to force the load of a new locale
  static Future refresh(
      final BuildContext context, final Locale? forcedLocale) async {
    final FlutterI18n currentInstance = _retrieveCurrentInstance(context)!;
    currentInstance.translationLoader!.forcedLocale = forcedLocale;
    await currentInstance.load();
  }

  /// Facade method to the simple translation logic
  static String translate(final BuildContext context, final String key,
      {final String? fallbackKey,
      final Map<String, String>? translationParams}) {
    final FlutterI18n currentInstance = _retrieveCurrentInstance(context)!;
    final SimpleTranslator simpleTranslator = SimpleTranslator(
      currentInstance.decodedMap,
      key,
      currentInstance.keySeparator,
      fallbackKey: fallbackKey,
      translationParams: translationParams,
      missingKeyTranslationHandler: (key) {
        currentInstance.missingTranslationHandler(key, currentInstance.locale);
      },
    );
    return simpleTranslator.translate();
  }

  /// Same as `get locale`, but this can be invoked from widgets
  static Locale? currentLocale(final BuildContext context) {
    final FlutterI18n? currentInstance = _retrieveCurrentInstance(context);
    return currentInstance?.translationLoader?.locale;
  }

  static FlutterI18n? _retrieveCurrentInstance(BuildContext context) {
    return Localizations.of<FlutterI18n>(context, FlutterI18n);
  }

  /// Build for root widget, to support RTL languages
  static Widget Function(BuildContext, Widget?) rootAppBuilder() {
    Widget appBuilder(BuildContext context, Widget? child) {
      final instance = _retrieveCurrentInstance(context);

      return StreamBuilder<Locale?>(
        initialData: instance?.locale,
        stream: instance?._localeStream.stream,
        builder: (context, snapshot) {
          return Directionality(
            textDirection: _findTextDirection(snapshot.data),
            child: child!,
          );
        },
      );
    }

    return appBuilder;
  }

  /// Used to retrieve the loading status stream
  static Stream<LoadingStatus> retrieveLoadingStream(
      final BuildContext context) {
    return _retrieveCurrentInstance(context)!.loadingStream;
  }

  /// Used to check if the translation file is still loading
  static Stream<bool> retrieveLoadedStream(final BuildContext context) {
    return _retrieveCurrentInstance(context)!.isLoadedStream;
  }

  static TextDirection _findTextDirection(final Locale? locale) {
    return intl.Bidi.isRtlLanguage(locale?.languageCode)
        ? TextDirection.rtl
        : TextDirection.ltr;
  }

  static TranslationCache translationCache = TranslationCache();

  /// [Map<dynamic, dynamic>] or a [List<dynamic>]
  static Future<dynamic> getLocaleMap(BuildContext context,
      [String? key, String? localeCode]) async {
    Map<dynamic, dynamic> localeMap;
    final FlutterI18n? currentInstance = _retrieveCurrentInstance(context);
    if (localeCode == null) {
      localeCode = currentInstance?.translationLoader?.locale?.toString() ?? 'en';
    }
    if (translationCache.hasLocale(localeCode)) {
      localeMap = translationCache.getLocale(localeCode)!;
      if (key == null) {
        return localeMap;
      } else {
        return getValueFromKey(localeMap, key);
      }
    }

    TranslationLoader? translationLoader = currentInstance?.translationLoader;

    if (translationLoader is FileTranslationLoader) {
      FileTranslationLoader newTranslationLoader = FileTranslationLoader(
        basePath: translationLoader.basePath,
        fallbackFile: translationLoader.fallbackFile,
        forcedLocale: Locale(localeCode),
        useCountryCode: translationLoader.useCountryCode,
        useScriptCode: translationLoader.useScriptCode,
      );
      localeMap = await newTranslationLoader.load();
    } else if (translationLoader is NamespaceFileTranslationLoader) {
      NamespaceFileTranslationLoader newTranslationLoader =
          NamespaceFileTranslationLoader(
        namespaces: translationLoader.namespaces,
        fallbackDir: translationLoader.fallbackDir,
        basePath: translationLoader.basePath,
        useCountryCode: translationLoader.useCountryCode,
        useScriptCode: translationLoader.useScriptCode,
        forcedLocale: Locale(localeCode),
      );
      localeMap = await newTranslationLoader.load();
    } else if (translationLoader is NetworkFileTranslationLoader) {
      NetworkFileTranslationLoader newTranslationLoader =
          NetworkFileTranslationLoader(
        baseUri: translationLoader.baseUri,
        forcedLocale: Locale(localeCode),
        fallbackFile: translationLoader.fallbackFile,
        useCountryCode: translationLoader.useCountryCode,
        useScriptCode: translationLoader.useScriptCode,
      );
      localeMap = await newTranslationLoader.load();
    } else {
      throw Exception("Unsupported translation loader");
    }

    translationCache.setLocale(localeCode, localeMap);
    if (key == null) {
      return localeMap;
    } else {
      return getValueFromKey(localeMap, key);
    }
  }

  static dynamic getValueFromKey(Map<dynamic, dynamic> map, String key) {
    dynamic value = map;
    List<String> keys = key.split('.');

    for (String subkey in keys) {
      if (value is Map) {
        value = value[subkey];
      } else if (value is List && int.tryParse(subkey) != null) {
        int index = int.parse(subkey);
        if (index >= 0 && index < value.length) {
          value = value[index];
        } else {
          return null; // Out of bounds
        }
      } else {
        return null; // Invalid key or type
      }

      if (value == null) {
        return null; // Key not found or invalid path
      }
    }
    return value;
  }
}
