import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../constants/app_constants.dart';
import 'api_base_url_resolver.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  final _storage = const FlutterSecureStorage();
  final _baseUrlResolver = ApiBaseUrlResolver();

  ApiClient._internal() {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
      headers: {'Content-Type': 'application/json'},
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.read(key: accessTokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        return handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          try {
            final refreshed = await _refresh();
            if (refreshed) {
              final token = await _storage.read(key: accessTokenKey);
              error.requestOptions.headers['Authorization'] = 'Bearer $token';
              final response = await dio.fetch(error.requestOptions);
              return handler.resolve(response);
            }
          } catch (_) {}
        }
        return handler.next(error);
      },
    ));
  }

  Future<bool> _refresh() async {
    final refreshToken = await _storage.read(key: refreshTokenKey);
    if (refreshToken == null) return false;
    final resolvedBaseUrl = await _baseUrlResolver.resolve();
    final response = await Dio().post('$resolvedBaseUrl/auth/refresh',
        data: {'refreshToken': refreshToken});
    final data = response.data['data'];
    await _storage.write(key: accessTokenKey, value: data['accessToken']);
    await _storage.write(key: refreshTokenKey, value: data['refreshToken']);
    return true;
  }

  Future<void> _ensureBaseUrl() async {
    dio.options.baseUrl = await _baseUrlResolver.resolve();
  }

  Future<Response> get(String path, {Map<String, dynamic>? params}) async {
    await _ensureBaseUrl();
    return dio.get(path, queryParameters: params);
  }

  Future<Response> post(String path, {dynamic data, Options? options}) async {
    await _ensureBaseUrl();
    return dio.post(path, data: data, options: options);
  }

  Future<Response> patch(String path, {dynamic data}) async {
    await _ensureBaseUrl();
    return dio.patch(path, data: data);
  }

  Future<Response> delete(String path) async {
    await _ensureBaseUrl();
    return dio.delete(path);
  }
}
