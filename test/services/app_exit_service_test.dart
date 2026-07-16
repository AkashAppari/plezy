import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/services/app_exit_service.dart';

void main() {
  test('desktop exit uses the required application exit API', () async {
    ui.AppExitType? requestedType;
    int? requestedCode;

    expect(
      await AppExitService.requestExit(
        exitApplicationForTesting: (exitType, exitCode) async {
          requestedType = exitType;
          requestedCode = exitCode;
          return ui.AppExitResponse.exit;
        },
      ),
      isTrue,
    );
    expect(requestedType, ui.AppExitType.required);
    expect(requestedCode, 0);
  });
}
