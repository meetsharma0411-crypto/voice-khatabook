import 'package:flutter_test/flutter_test.dart';
import 'package:keshav_ai_voice_khatabook/core/config/api_config.dart';

void main() {
  test('emulator target uses Android emulator host alias', () {
    expect(ApiConfig.target, ApiTarget.emulator);
    expect(ApiConfig.baseUrl, 'http://10.0.2.2:8000/api/');
  });
}
