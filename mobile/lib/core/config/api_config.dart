enum ApiTarget { emulator, physical }

class ApiConfig {
  const ApiConfig._();

  static const String _targetValue = String.fromEnvironment(
    'KHATABOOK_API_TARGET',
    defaultValue: 'emulator',
  );
  static const String _physicalBaseUrl = String.fromEnvironment(
    'KHATABOOK_PHYSICAL_DEVICE_API_URL',
  );
  static const String emulatorBaseUrl = 'http://10.0.2.2:8000/api/';

  static ApiTarget get target =>
      _targetValue == 'physical' ? ApiTarget.physical : ApiTarget.emulator;

  static String get baseUrl {
    if (target == ApiTarget.emulator) return emulatorBaseUrl;
    if (_physicalBaseUrl.trim().isEmpty) {
      throw StateError(
        'Set KHATABOOK_PHYSICAL_DEVICE_API_URL to your computer LAN API URL.',
      );
    }
    final url = _physicalBaseUrl.trim();
    return url.endsWith('/') ? url : '$url/';
  }
}
