const String baseUrl = String.fromEnvironment(
  'BASE_URL',
  defaultValue: 'http://10.0.2.2:3000/api', // Android emulator → localhost
);

// Đổi IP này khi test trên thiết bị thật:
// const String baseUrl = 'http://192.168.1.x:3000/api';

const Duration connectTimeout = Duration(seconds: 15);
const Duration receiveTimeout = Duration(seconds: 60);

const String accessTokenKey = 'access_token';
const String refreshTokenKey = 'refresh_token';
const String userKey = 'user_data';
