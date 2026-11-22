import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:docsift/core/constants/app_colors.dart';
import 'package:docsift/core/theme/app_theme.dart';
import 'package:docsift/features/vault/domain/models/vault_templates.dart';
import 'package:docsift/features/vault/presentation/add_text_item_screen.dart';

void main() {
  group('VaultTemplates Autofill Target Resolution', () {
    test('resolves Amazon & Gmail domains and Android packages even with blank URL', () {
      final amazon = VaultTemplates.resolveAutofillTargets(
        title: 'Amazon',
        url: '',
      );
      expect(amazon.domains, containsAll(['amazon.in', 'amazon.com']));
      expect(
        amazon.packages,
        contains('in.amazon.mShop.android.shopping'),
      );

      final gmail = VaultTemplates.resolveAutofillTargets(
        title: 'Gmail',
        url: '',
      );
      expect(gmail.domains, containsAll(['gmail.com', 'google.com']));
      expect(gmail.packages, contains('com.google.android.gm'));
    });

    test('extractNormalizedDomain strips scheme, www, m, port, and path', () {
      expect(
        VaultTemplates.extractNormalizedDomain('https://www.amazon.in/gp/cart?ref=1'),
        'amazon.in',
      );
      expect(
        VaultTemplates.extractNormalizedDomain('m.facebook.com/login'),
        'facebook.com',
      );
      expect(
        VaultTemplates.extractNormalizedDomain('https://kite.zerodha.com:443/dashboard'),
        'kite.zerodha.com',
      );
    });
  });

  group('Identity Document Dynamic Schemas', () {
    test('Aadhaar and PAN omit expiry while Passport and Driving License include it', () {
      final aadhaar = VaultTemplates.identityTemplateById('aadhaar');
      final pan = VaultTemplates.identityTemplateById('pan');
      final passport = VaultTemplates.identityTemplateById('passport');
      final dl = VaultTemplates.identityTemplateById('driving_license');

      expect(aadhaar.fields.any((f) => f.key == 'expiry'), isFalse);
      expect(pan.fields.any((f) => f.key == 'expiry'), isFalse);
      expect(pan.fields.any((f) => f.key == 'fatherName'), isTrue);

      expect(passport.fields.any((f) => f.key == 'expiry'), isTrue);
      expect(passport.fields.any((f) => f.key == 'nationality'), isTrue);
      expect(dl.fields.any((f) => f.key == 'vehicleClass'), isTrue);
      expect(dl.fields.any((f) => f.key == 'bloodGroup'), isTrue);
    });

    test('inferIdentityTemplate supports both explicit docType and legacy documentName', () {
      expect(
        VaultTemplates.inferIdentityTemplate({'docType': 'vehicle_rc'}).id,
        'vehicle_rc',
      );
      expect(
        VaultTemplates.inferIdentityTemplate({'documentName': 'My Aadhaar Card'}).id,
        'aadhaar',
      );
      expect(
        VaultTemplates.inferIdentityTemplate({'documentName': 'Indian Passport'}).id,
        'passport',
      );
      expect(
        VaultTemplates.inferIdentityTemplate({'documentName': 'Employee Badge'}).id,
        'custom',
      );
    });
  });

  group('CSPRNG Password Generator, Card Detection & Field Humanization', () {
    test('generateStrongPassword enforces length and character classes with Very Strong rating', () {
      final pw = VaultTemplates.generateStrongPassword(length: 20);
      expect(pw.length, 20);
      expect(RegExp(r'[A-Z]').hasMatch(pw), isTrue);
      expect(RegExp(r'[a-z]').hasMatch(pw), isTrue);
      expect(RegExp(r'[0-9]').hasMatch(pw), isTrue);
      expect(RegExp(r'[^A-Za-z0-9]').hasMatch(pw), isTrue);

      final strength = VaultTemplates.evaluatePasswordStrength(pw);
      expect(strength.label, 'Very Strong');
      expect(strength.score, greaterThanOrEqualTo(0.85));
    });

    test('detectCardNetwork identifies Visa, Mastercard, RuPay, and Amex', () {
      expect(VaultTemplates.detectCardNetwork('4111 1111 1111 1111'), 'VISA');
      expect(VaultTemplates.detectCardNetwork('5242 1234 5678 9010'), 'MASTERCARD');
      expect(VaultTemplates.detectCardNetwork('6521 8800 1234 5678'), 'RUPAY');
      expect(VaultTemplates.detectCardNetwork('3782 822463 10005'), 'AMEX');
    });

    test('humanizeFieldKey converts camelCase keys into natural QA phrases', () {
      expect(VaultTemplates.humanizeFieldKey('ifscCode'), 'IFSC code');
      expect(VaultTemplates.humanizeFieldKey('bloodGroup'), 'blood group');
      expect(VaultTemplates.humanizeFieldKey('fatherName'), "father's name");
    });
  });

  group('Bank & Template Chip Contrast Regression', () {
    testWidgets(
      'Card bank chips render high-contrast text both unselected and selected',
      (tester) async {
        GoogleFonts.config.allowRuntimeFetching = false;
        final theme = AppTheme.light;
        expect(theme.chipTheme.labelStyle?.color, AppColors.textPrimary);
        expect(theme.chipTheme.labelStyle?.color, isNot(AppColors.cardCanvas));

        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: theme,
              home: const AddTextItemScreen(categoryId: 'cards'),
            ),
          ),
        );

        final hdfcTextFinder = find.text('HDFC Bank');
        expect(hdfcTextFinder, findsOneWidget);

        final unselectedText = tester.widget<Text>(hdfcTextFinder);
        final unselectedChip = tester.widget<ActionChip>(
          find.ancestor(of: hdfcTextFinder, matching: find.byType(ActionChip)),
        );
        expect(unselectedChip.backgroundColor, AppColors.cardCanvas);
        expect(unselectedText.style?.color, AppColors.primaryNavy);
        expect(
          unselectedText.style?.color,
          isNot(equals(unselectedChip.backgroundColor)),
        );

        await tester.tap(hdfcTextFinder);
        await tester.pumpAndSettle();

        final selectedText = tester.widget<Text>(hdfcTextFinder);
        final selectedChip = tester.widget<ActionChip>(
          find.ancestor(of: hdfcTextFinder, matching: find.byType(ActionChip)),
        );
        expect(selectedChip.backgroundColor, AppColors.categoryCardsColor);
        expect(selectedText.style?.color, Colors.white);
        expect(
          selectedText.style?.color,
          isNot(equals(selectedChip.backgroundColor)),
        );
      },
    );
  });
}

