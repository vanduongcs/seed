import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../core/network/api_client.dart';
import '../../../core/constants/app_constants.dart';

final authStateProvider = FutureProvider<bool>((ref) async {
  const storage = FlutterSecureStorage();
  final token = await storage.read(key: accessTokenKey);
  return token != null;
});

final authProvider = StateNotifierProvider<AuthNotifier, AsyncValue<void>>(
  (ref) => AuthNotifier(ref),
);

class AuthNotifier extends StateNotifier<AsyncValue<void>> {
  final Ref _ref;
  final _api = ApiClient();
  final _storage = const FlutterSecureStorage();

  AuthNotifier(this._ref) : super(const AsyncValue.data(null));

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await _api
          .post('/auth/login', data: {'email': email, 'password': password});
      await _saveTokens(res.data['data']);
      _ref.invalidate(authStateProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> register(String name, String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final res = await _api.post('/auth/register',
          data: {'name': name, 'email': email, 'password': password});
      await _saveTokens(res.data['data']);
      _ref.invalidate(authStateProvider);
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> logout() async {
    try {
      await _api.post('/auth/logout');
    } catch (_) {
      // Local logout should still complete when the access token is expired.
    }
    await _storage.delete(key: accessTokenKey);
    await _storage.delete(key: refreshTokenKey);
    await _storage.delete(key: userKey);
    _ref.invalidate(authStateProvider);
  }

  Future<void> _saveTokens(Map<String, dynamic> data) async {
    await _storage.write(key: accessTokenKey, value: data['accessToken']);
    await _storage.write(key: refreshTokenKey, value: data['refreshToken']);
    if (data['user'] != null) {
      await _storage.write(key: userKey, value: jsonEncode(data['user']));
    }
  }
}
