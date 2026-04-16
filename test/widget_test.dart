// LSE widget tests placeholder.
//
// Full integration tests would require mocking HTTPS server and network interfaces.
// For now, we validate that the core services compile and basic logic works.

import 'package:flutter_test/flutter_test.dart';
import 'package:lse_client/shared/services/code_service.dart';
import 'package:lse_client/core/constants/app_constants.dart';

void main() {
  group('CodeService', () {
    test('generates 6-digit code', () {
      final service = CodeService();
      final code = service.generateCode();
      expect(code.length, AppConstants.codeLength);
      expect(int.tryParse(code), isNotNull);
    });

    test('consumes code after verification', () {
      final service = CodeService();
      final code = service.generateCode();
      expect(service.verifyAndConsume(code), isTrue);
      expect(service.verifyAndConsume(code), isFalse); // already consumed
    });

    test('rejects invalid code', () {
      final service = CodeService();
      expect(service.verifyAndConsume('000000'), isFalse);
    });
  });
}
