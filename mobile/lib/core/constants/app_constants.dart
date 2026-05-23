const String configuredBaseUrl = String.fromEnvironment('BASE_URL');

const String defaultBaseUrl =
    'https://seed-vanb2207577-aybrd9fwhnf3hqe.eastasia-01.azurewebsites.net/api';
const String baseUrl =
    configuredBaseUrl == '' ? defaultBaseUrl : configuredBaseUrl;

const Duration connectTimeout = Duration(seconds: 15);
const Duration receiveTimeout = Duration(seconds: 180);

const String accessTokenKey = 'access_token';
const String refreshTokenKey = 'refresh_token';
const String userKey = 'user_data';
const String guestModeKey = 'guest_mode';
const String resolvedBaseUrlKey = 'resolved_base_url';
