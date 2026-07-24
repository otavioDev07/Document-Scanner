import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

final class LegacyLocalizations {
  const LegacyLocalizations(this.locale, this._values, this._englishValues);

  final Locale locale;
  final Map<String, Object?> _values;
  final Map<String, Object?> _englishValues;

  static const List<String> localeIds = <String>[
    'ar',
    'bg',
    'ca',
    'cs',
    'de',
    'en',
    'eo',
    'es',
    'et',
    'eu',
    'fa',
    'fi',
    'fr',
    'gl',
    'he',
    'hi',
    'hr',
    'hu',
    'id',
    'it',
    'ja',
    'kab',
    'nb_NO',
    'nl',
    'oc',
    'pa',
    'pl',
    'pt',
    'pt_BR',
    'ro',
    'ru',
    'sv',
    'ta',
    'tr',
    'uk',
    'vi',
    'zh_CN',
    'zh_Hant',
  ];

  static final List<Locale> supportedLocales = localeIds
      .map(localeFromId)
      .toList(growable: false);

  static String displayName(String id) =>
      const <String, String>{
        'ar': 'العربية',
        'bg': 'Български',
        'ca': 'Català',
        'cs': 'Čeština',
        'de': 'Deutsch',
        'en': 'English',
        'eo': 'Esperanto',
        'es': 'Español',
        'et': 'Eesti',
        'eu': 'Euskara',
        'fa': 'فارسی',
        'fi': 'Suomi',
        'fr': 'Français',
        'gl': 'Galego',
        'he': 'עברית',
        'hi': 'हिन्दी',
        'hr': 'Hrvatski',
        'hu': 'Magyar',
        'id': 'Bahasa Indonesia',
        'it': 'Italiano',
        'ja': '日本語',
        'kab': 'Taqbaylit',
        'nb_NO': 'Norsk bokmål',
        'nl': 'Nederlands',
        'oc': 'Occitan',
        'pa': 'ਪੰਜਾਬੀ',
        'pl': 'Polski',
        'pt': 'Português',
        'pt_BR': 'Português (Brasil)',
        'ro': 'Română',
        'ru': 'Русский',
        'sv': 'Svenska',
        'ta': 'தமிழ்',
        'tr': 'Türkçe',
        'uk': 'Українська',
        'vi': 'Tiếng Việt',
        'zh_CN': '简体中文',
        'zh_Hant': '繁體中文',
      }[id] ??
      id;

  static LegacyLocalizations of(BuildContext context) =>
      Localizations.of<LegacyLocalizations>(context, LegacyLocalizations) ??
      const LegacyLocalizations(
        Locale('pt', 'BR'),
        <String, Object?>{},
        <String, Object?>{},
      );

  String text(
    String key, {
    String? fallback,
    List<Object> arguments = const [],
  }) {
    Object? value = _read(_values, key) ?? _read(_englishValues, key);
    if (value is Map) value = value['title'];
    String result = value is String && value.trim().isNotEmpty
        ? value
        : fallback ?? key;
    for (int index = 0; index < arguments.length; index++) {
      result = result.replaceAll('%${index + 1}\$s', '${arguments[index]}');
    }
    return result;
  }

  String pages(int count) => count == 1
      ? '$count ${text('page', fallback: 'página')}'
      : text(
          'nb_pages',
          fallback: '$count páginas',
          arguments: <Object>[count],
        );

  static Object? _read(Map<String, Object?> source, String key) {
    Object? current = source;
    for (final String component in key.split('.')) {
      if (current is! Map || !current.containsKey(component)) return null;
      current = current[component];
    }
    return current;
  }

  static Locale localeFromId(String id) {
    final List<String> components = id.split('_');
    if (components.length == 1) return Locale(components.first);
    if (components[1].length == 4) {
      return Locale.fromSubtags(
        languageCode: components.first,
        scriptCode: components[1],
      );
    }
    return Locale(components.first, components[1]);
  }

  static String localeId(Locale locale) {
    final String? script = locale.scriptCode;
    if (script != null &&
        localeIds.contains('${locale.languageCode}_$script')) {
      return '${locale.languageCode}_$script';
    }
    final String? country = locale.countryCode;
    if (country != null &&
        localeIds.contains('${locale.languageCode}_$country')) {
      return '${locale.languageCode}_$country';
    }
    if (localeIds.contains(locale.languageCode)) return locale.languageCode;
    return 'en';
  }
}

final class LegacyLocalizationsDelegate
    extends LocalizationsDelegate<LegacyLocalizations> {
  const LegacyLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => LegacyLocalizations.localeIds.any(
    (String id) =>
        id == locale.languageCode || id.startsWith('${locale.languageCode}_'),
  );

  @override
  Future<LegacyLocalizations> load(Locale locale) async {
    final String id = LegacyLocalizations.localeId(locale);
    final List<String> catalogs = await Future.wait<String>(<Future<String>>[
      rootBundle.loadString('assets/i18n/$id.json'),
      if (id != 'en') rootBundle.loadString('assets/i18n/en.json'),
    ]);
    final Map<String, Object?> values =
        jsonDecode(catalogs.first) as Map<String, Object?>;
    final Map<String, Object?> english = id == 'en'
        ? values
        : jsonDecode(catalogs.last) as Map<String, Object?>;
    return LegacyLocalizations(locale, values, english);
  }

  @override
  bool shouldReload(LegacyLocalizationsDelegate old) => false;
}

extension LegacyLocalizationsContext on BuildContext {
  LegacyLocalizations get l10n => LegacyLocalizations.of(this);
}
