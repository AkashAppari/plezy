import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/player_utils.dart';

void main() {
  group('shouldRestartBeforePreviousItem', () {
    test('keeps previous item behavior within the restart threshold', () {
      expect(shouldRestartBeforePreviousItem(Duration.zero), isFalse);
      expect(shouldRestartBeforePreviousItem(const Duration(seconds: 3)), isFalse);
    });

    test('restarts the current item after the threshold', () {
      expect(shouldRestartBeforePreviousItem(const Duration(milliseconds: 3001)), isTrue);
    });
  });
}
