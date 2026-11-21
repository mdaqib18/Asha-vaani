import 'dart:io';
import 'dart:math' as math;

import 'package:asha_vaani/screens/component_gallery_screen.dart';
import 'package:asha_vaani/theme/app_theme.dart';
import 'package:asha_vaani/ui/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _channelLuminance(int channel) {
  final c = channel / 255.0;
  return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color color) {
  final r = _channelLuminance((color.r * 255).round());
  final g = _channelLuminance((color.g * 255).round());
  final b = _channelLuminance((color.b * 255).round());
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a);
  final lb = _relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('all text and badge token pairs meet >= 4.5:1 WCAG AA contrast', () {
    for (final tokens in [AppTokens.standard, AppTokens.highContrast]) {
      expect(_contrastRatio(tokens.ink, tokens.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.ink, tokens.surfaceRaised), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.inkMuted, tokens.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.inkMuted, tokens.surfaceRaised), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.primary, tokens.surface), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.primary, tokens.primaryContainer), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.ink, tokens.primaryContainer), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(Colors.white, tokens.primary), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.riskHigh, tokens.riskHighContainer), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.riskMedium, tokens.riskMediumContainer), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.riskOk, tokens.riskOkContainer), greaterThanOrEqualTo(4.5));
      expect(_contrastRatio(tokens.info, tokens.infoContainer), greaterThanOrEqualTo(4.5));
    }
  });

  test('bundled Noto Sans static TTF fonts exist with valid TrueType headers', () {
    const fontFiles = [
      'assets/fonts/NotoSans-Regular.ttf',
      'assets/fonts/NotoSans-SemiBold.ttf',
      'assets/fonts/NotoSansDevanagari-Regular.ttf',
      'assets/fonts/NotoSansDevanagari-SemiBold.ttf',
      'assets/fonts/NotoSansKannada-Regular.ttf',
      'assets/fonts/NotoSansKannada-SemiBold.ttf',
    ];
    for (final rel in fontFiles) {
      final file = File(rel);
      expect(file.existsSync(), isTrue, reason: 'Missing $rel');
      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(30000));
      expect(bytes.sublist(0, 4), [0x00, 0x01, 0x00, 0x00]);
    }
  });

  testWidgets(
      'ComponentGalleryScreen renders all 19 components at 360x640 and 130% text scale without overflow',
      (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme(),
        builder: (context, child) {
          final data = MediaQuery.of(context);
          return MediaQuery(
            data: data.copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          );
        },
        home: const ComponentGalleryScreen(),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('V2 UI Gallery'), findsOneWidget);
    expect(find.byType(PrimaryButton), findsWidgets);
    expect(
      tester.getSize(find.byType(PrimaryButton).first).height,
      greaterThanOrEqualTo(48),
    );

    // Scroll down through the gallery to exercise all 19 components under 360x640 @ 1.3x.
    final listFinder = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Read back fields'),
      200,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SecondaryButton), findsWidgets);
    expect(find.byType(TextAction), findsWidgets);
    expect(
      tester.getSize(find.byType(SecondaryButton).first).height,
      greaterThanOrEqualTo(48),
    );

    await tester.scrollUntilVisible(
      find.text('MicButton States (88dp)'),
      200,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(MicButton), findsWidgets);

    // MicButton circle must be 88dp.
    final micBox = tester.getSize(
      find.descendant(
        of: find.byType(MicButton).first,
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(micBox.width, 88);
    expect(micBox.height, 88);

    await tester.scrollUntilVisible(
      find.text('StatTile & Badges'),
      200,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(StatTile), findsNWidgets(3));

    await tester.scrollUntilVisible(
      find.byType(SecurityChip),
      200,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(RiskBadge), findsWidgets);
    expect(find.byType(SyncChip), findsNWidgets(5));
    expect(find.byType(SecurityChip), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(BeneficiaryTile),
      150,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(BeneficiaryTile), findsWidgets);

    await tester.scrollUntilVisible(
      find.byType(VisitTile),
      150,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(VisitTile), findsWidgets);

    await tester.scrollUntilVisible(
      find.byType(FieldCard),
      150,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(FieldCard), findsWidgets);

    await tester.scrollUntilVisible(
      find.byType(LiveTranscript),
      150,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(LiveTranscript), findsWidgets);

    await tester.scrollUntilVisible(
      find.byType(FollowUpCard),
      150,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(FollowUpCard), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(EmptyState),
      150,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(EmptyState), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(ErrorState),
      150,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorState), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byType(SkeletonLoader),
      150,
      scrollable: listFinder,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(SkeletonLoader), findsOneWidget);

    // Toggle High Contrast theme in gallery.
    await tester.tap(find.text('High contrast'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Standard'), findsOneWidget);

    // Open ConfirmSheet from gallery.
    await tester.scrollUntilVisible(
      find.text('Open confirm sheet'),
      -300,
      scrollable: listFinder,
    );
    await tester.tap(find.text('Open confirm sheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(tester.takeException(), isNull);
    expect(find.byType(ConfirmSheet), findsOneWidget);
    expect(find.text('Confirm visit record?'), findsOneWidget);
  });
}
