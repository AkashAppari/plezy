import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/screens/settings/add_jellyfin_screen.dart';
import 'package:plezy/utils/platform_detector.dart';

Profile _profile(String id) => Profile(
  id: id,
  kind: ProfileKind.local,
  displayName: id,
  sortOrder: 0,
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

void main() {
  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('autofocuses the server URL field', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AddJellyfinScreen()));
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField));

    expect(field.autofocus, isTrue);
  });

  testWidgets('TV initial focus stays on the server URL field', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(true);

    await tester.pumpWidget(const InputModeTracker(child: MaterialApp(home: AddJellyfinScreen())));
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'AddJellyfin:Url');
  });

  group('Jellyfin profile binding decisions', () {
    test('creates a local profile only on true first-run with no profiles', () {
      expect(shouldCreateLocalJellyfinProfile(targetProfile: null, activeProfile: null, hasProfiles: false), isTrue);
      expect(
        shouldPromptForJellyfinProfileSelection(targetProfile: null, activeProfile: null, hasProfiles: false),
        isFalse,
      );
    });

    test('uses existing active profile without prompting or creating', () {
      final active = _profile('active');
      expect(shouldCreateLocalJellyfinProfile(targetProfile: null, activeProfile: active, hasProfiles: true), isFalse);
      expect(
        shouldPromptForJellyfinProfileSelection(targetProfile: null, activeProfile: active, hasProfiles: true),
        isFalse,
      );
    });

    test('prompts when profiles exist but no profile is active', () {
      expect(shouldCreateLocalJellyfinProfile(targetProfile: null, activeProfile: null, hasProfiles: true), isFalse);
      expect(
        shouldPromptForJellyfinProfileSelection(targetProfile: null, activeProfile: null, hasProfiles: true),
        isTrue,
      );
    });

    test('explicit target profile never creates or prompts', () {
      final target = _profile('target');
      expect(shouldCreateLocalJellyfinProfile(targetProfile: target, activeProfile: null, hasProfiles: true), isFalse);
      expect(
        shouldPromptForJellyfinProfileSelection(targetProfile: target, activeProfile: null, hasProfiles: true),
        isFalse,
      );
    });
  });
}
