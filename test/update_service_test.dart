import 'package:flutter_test/flutter_test.dart';
import 'package:ficbatch/services/update_service.dart';

void main() {
  test('isNewerVersion compares dotted versions numerically', () {
    expect(UpdateService.isNewerVersion('0.7.5', '0.7.3'), isTrue);
    expect(UpdateService.isNewerVersion('0.7.10', '0.7.9'), isTrue);
    expect(UpdateService.isNewerVersion('0.7.3', '0.7.3'), isFalse);
    expect(UpdateService.isNewerVersion('0.7.2', '0.7.3'), isFalse);
    expect(UpdateService.isNewerVersion('1.0.0', '0.9.9'), isTrue);
    expect(UpdateService.isNewerVersion('0.8', '0.7.9'), isTrue);
    expect(UpdateService.isNewerVersion('garbage', '0.7.3'), isFalse);
  });
}
