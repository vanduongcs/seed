import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum AppLanguage {
  vi('vi', 'Việt Nam'),
  en('en', 'English');

  final String code;
  final String label;

  const AppLanguage(this.code, this.label);

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (language) => language.code == code,
      orElse: () => AppLanguage.vi,
    );
  }
}

const _languageStorageKey = 'seed_app_language';

final appLanguageProvider =
    StateNotifierProvider<AppLanguageNotifier, AppLanguage>((ref) {
  return AppLanguageNotifier()..load();
});

class AppLanguageNotifier extends StateNotifier<AppLanguage> {
  AppLanguageNotifier() : super(AppLanguage.vi);

  static const _storage = FlutterSecureStorage();

  Future<void> load() async {
    final savedCode = await _storage.read(key: _languageStorageKey);
    state = AppLanguage.fromCode(savedCode);
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    await _storage.write(key: _languageStorageKey, value: language.code);
  }
}

String appText(AppLanguage language, String vi, String en) {
  return language == AppLanguage.en ? en : vi;
}
