import 'dart:math';
import 'package:flutter/material.dart';

/// Credential sub-template inside the Passwords category.
enum PasswordSubTemplate {
  appLogin('App / Website', Icons.key_rounded),
  wifi('Wi-Fi Network', Icons.wifi_rounded),
  bankLogin('NetBanking', Icons.account_balance_rounded),
  apiKey('API / Token', Icons.terminal_rounded);

  const PasswordSubTemplate(this.label, this.icon);
  final String label;
  final IconData icon;

  static PasswordSubTemplate fromKey(String? raw) {
    for (final t in PasswordSubTemplate.values) {
      if (t.name == raw) return t;
    }
    return PasswordSubTemplate.appLogin;
  }
}

/// Pre-configured service preset for instant 1-tap login setup & OS Autofill binding.
class PasswordServicePreset {
  const PasswordServicePreset({
    required this.id,
    required this.name,
    required this.defaultUrl,
    required this.domains,
    required this.androidPackages,
    required this.icon,
    required this.accentColor,
    this.usernameHint = 'Email or username',
  });

  final String id;
  final String name;
  final String defaultUrl;
  final List<String> domains;
  final List<String> androidPackages;
  final IconData icon;
  final Color accentColor;
  final String usernameHint;
}

/// Field specification for schema-driven Identity Document forms.
class IdentityFieldSpec {
  const IdentityFieldSpec({
    required this.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.isSecret = false,
    this.isDate = false,
    this.uppercase = false,
    this.aadhaarGrouped = false,
    this.maxLength,
  });

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final bool isSecret;
  final bool isDate;
  final bool uppercase;
  final bool aadhaarGrouped;
  final int? maxLength;
}

/// Dynamic Identity Document template definition.
class IdentityDocTemplate {
  const IdentityDocTemplate({
    required this.id,
    required this.displayName,
    required this.shortLabel,
    required this.icon,
    required this.fields,
  });

  final String id;
  final String displayName;
  final String shortLabel;
  final IconData icon;
  final List<IdentityFieldSpec> fields;
}

/// Catalog of presets, document schemas, card helpers, and password generation.
class VaultTemplates {
  const VaultTemplates._();

  static const List<PasswordServicePreset> passwordPresets = [
    PasswordServicePreset(
      id: 'google',
      name: 'Google / Gmail',
      defaultUrl: 'https://accounts.google.com',
      domains: ['google.com', 'gmail.com', 'accounts.google.com', 'youtube.com'],
      androidPackages: [
        'com.google.android.gm',
        'com.google.android.gms',
        'com.google.android.youtube',
      ],
      icon: Icons.mail_outline_rounded,
      accentColor: Color(0xFFEA4335),
      usernameHint: 'you@gmail.com',
    ),
    PasswordServicePreset(
      id: 'amazon',
      name: 'Amazon',
      defaultUrl: 'https://www.amazon.in',
      domains: ['amazon.in', 'amazon.com', 'amazon.co.uk', 'primevideo.com'],
      androidPackages: [
        'in.amazon.mShop.android.shopping',
        'com.amazon.mShop.android.shopping',
        'com.amazon.avod.thirdpartyclient',
      ],
      icon: Icons.shopping_bag_outlined,
      accentColor: Color(0xFFFF9900),
      usernameHint: 'Email or mobile number',
    ),
    PasswordServicePreset(
      id: 'netflix',
      name: 'Netflix',
      defaultUrl: 'https://www.netflix.com',
      domains: ['netflix.com'],
      androidPackages: ['com.netflix.mediaclient'],
      icon: Icons.movie_outlined,
      accentColor: Color(0xFFE50914),
      usernameHint: 'Email or phone number',
    ),
    PasswordServicePreset(
      id: 'instagram',
      name: 'Instagram',
      defaultUrl: 'https://www.instagram.com',
      domains: ['instagram.com'],
      androidPackages: ['com.instagram.android', 'com.instagram.barcelona'],
      icon: Icons.camera_alt_outlined,
      accentColor: Color(0xFFE1306C),
      usernameHint: '@username, email, or phone',
    ),
    PasswordServicePreset(
      id: 'apple',
      name: 'Apple ID',
      defaultUrl: 'https://appleid.apple.com',
      domains: ['apple.com', 'icloud.com'],
      androidPackages: ['com.apple.android.music'],
      icon: Icons.phone_iphone_rounded,
      accentColor: Color(0xFF1D1D1F),
      usernameHint: 'Apple ID email',
    ),
    PasswordServicePreset(
      id: 'github',
      name: 'GitHub',
      defaultUrl: 'https://github.com',
      domains: ['github.com'],
      androidPackages: ['com.github.android'],
      icon: Icons.code_rounded,
      accentColor: Color(0xFF24292F),
      usernameHint: 'Username or email',
    ),
    PasswordServicePreset(
      id: 'microsoft',
      name: 'Microsoft / Outlook',
      defaultUrl: 'https://login.live.com',
      domains: ['microsoft.com', 'live.com', 'outlook.com', 'office.com'],
      androidPackages: [
        'com.microsoft.office.outlook',
        'com.microsoft.teams',
        'com.azure.authenticator',
      ],
      icon: Icons.grid_view_rounded,
      accentColor: Color(0xFF0078D4),
      usernameHint: 'you@outlook.com',
    ),
    PasswordServicePreset(
      id: 'linkedin',
      name: 'LinkedIn',
      defaultUrl: 'https://www.linkedin.com',
      domains: ['linkedin.com'],
      androidPackages: ['com.linkedin.android'],
      icon: Icons.work_outline_rounded,
      accentColor: Color(0xFF0A66C2),
      usernameHint: 'Email or phone',
    ),
    PasswordServicePreset(
      id: 'x_twitter',
      name: 'X (Twitter)',
      defaultUrl: 'https://x.com',
      domains: ['x.com', 'twitter.com'],
      androidPackages: ['com.twitter.android'],
      icon: Icons.alternate_email_rounded,
      accentColor: Color(0xFF14171A),
      usernameHint: '@handle, email, or phone',
    ),
    PasswordServicePreset(
      id: 'facebook',
      name: 'Facebook',
      defaultUrl: 'https://www.facebook.com',
      domains: ['facebook.com', 'messenger.com'],
      androidPackages: [
        'com.facebook.katana',
        'com.facebook.lite',
        'com.facebook.orca',
      ],
      icon: Icons.people_outline_rounded,
      accentColor: Color(0xFF1877F2),
      usernameHint: 'Email or mobile number',
    ),
    PasswordServicePreset(
      id: 'spotify',
      name: 'Spotify',
      defaultUrl: 'https://accounts.spotify.com',
      domains: ['spotify.com'],
      androidPackages: ['com.spotify.music'],
      icon: Icons.music_note_rounded,
      accentColor: Color(0xFF1DB954),
      usernameHint: 'Email or username',
    ),
    PasswordServicePreset(
      id: 'flipkart',
      name: 'Flipkart',
      defaultUrl: 'https://www.flipkart.com',
      domains: ['flipkart.com'],
      androidPackages: ['com.flipkart.android'],
      icon: Icons.local_mall_outlined,
      accentColor: Color(0xFF2874F0),
      usernameHint: 'Mobile number or email',
    ),
    PasswordServicePreset(
      id: 'discord',
      name: 'Discord',
      defaultUrl: 'https://discord.com/login',
      domains: ['discord.com'],
      androidPackages: ['com.discord'],
      icon: Icons.forum_outlined,
      accentColor: Color(0xFF5865F2),
      usernameHint: 'Email or phone number',
    ),
    PasswordServicePreset(
      id: 'reddit',
      name: 'Reddit',
      defaultUrl: 'https://www.reddit.com',
      domains: ['reddit.com'],
      androidPackages: ['com.reddit.frontpage'],
      icon: Icons.chat_bubble_outline_rounded,
      accentColor: Color(0xFFFF4500),
      usernameHint: 'u/username or email',
    ),
    PasswordServicePreset(
      id: 'chatgpt',
      name: 'ChatGPT / OpenAI',
      defaultUrl: 'https://chatgpt.com',
      domains: ['chatgpt.com', 'openai.com'],
      androidPackages: ['com.openai.chatgpt'],
      icon: Icons.auto_awesome_outlined,
      accentColor: Color(0xFF10A37F),
      usernameHint: 'Email address',
    ),
    PasswordServicePreset(
      id: 'paypal',
      name: 'PayPal',
      defaultUrl: 'https://www.paypal.com',
      domains: ['paypal.com'],
      androidPackages: ['com.paypal.android.p2pmobile'],
      icon: Icons.account_balance_wallet_outlined,
      accentColor: Color(0xFF003087),
      usernameHint: 'Email or mobile number',
    ),
    PasswordServicePreset(
      id: 'zerodha',
      name: 'Zerodha Kite',
      defaultUrl: 'https://kite.zerodha.com',
      domains: ['zerodha.com', 'kite.zerodha.com'],
      androidPackages: ['com.zerodha.kite3'],
      icon: Icons.candlestick_chart_outlined,
      accentColor: Color(0xFF387ED1),
      usernameHint: '6-char User ID (e.g. AB1234)',
    ),
    PasswordServicePreset(
      id: 'groww',
      name: 'Groww',
      defaultUrl: 'https://groww.in',
      domains: ['groww.in'],
      androidPackages: ['com.nextbillion.groww'],
      icon: Icons.trending_up_rounded,
      accentColor: Color(0xFF00D09C),
      usernameHint: 'Registered email',
    ),
    PasswordServicePreset(
      id: 'irctc',
      name: 'IRCTC Rail',
      defaultUrl: 'https://www.irctc.co.in',
      domains: ['irctc.co.in'],
      androidPackages: ['cris.org.in.prs.ima'],
      icon: Icons.train_outlined,
      accentColor: Color(0xFF213D77),
      usernameHint: 'IRCTC User ID',
    ),
    PasswordServicePreset(
      id: 'digilocker',
      name: 'DigiLocker',
      defaultUrl: 'https://www.digilocker.gov.in',
      domains: ['digilocker.gov.in'],
      androidPackages: ['com.digilocker.android'],
      icon: Icons.verified_user_outlined,
      accentColor: Color(0xFF2B3990),
      usernameHint: 'Mobile or Aadhaar number',
    ),
    PasswordServicePreset(
      id: 'hdfc',
      name: 'HDFC NetBanking',
      defaultUrl: 'https://netbanking.hdfcbank.com',
      domains: ['hdfcbank.com'],
      androidPackages: ['com.snapwork.hdfc', 'com.hdfcbank.android.now'],
      icon: Icons.account_balance_outlined,
      accentColor: Color(0xFF004C8F),
      usernameHint: 'Customer ID',
    ),
    PasswordServicePreset(
      id: 'sbi',
      name: 'SBI YONO / OnlineSBI',
      defaultUrl: 'https://retail.onlinesbi.sbi',
      domains: ['onlinesbi.sbi', 'sbi.co.in'],
      androidPackages: ['com.sbi.lotusintouch', 'com.sbi.SBIFreedomPlus'],
      icon: Icons.account_balance_outlined,
      accentColor: Color(0xFF280071),
      usernameHint: 'OnlineSBI Username',
    ),
    PasswordServicePreset(
      id: 'icici',
      name: 'ICICI iMobile',
      defaultUrl: 'https://www.icicibank.com',
      domains: ['icicibank.com'],
      androidPackages: ['com.csam.icici.bank.imobile'],
      icon: Icons.account_balance_outlined,
      accentColor: Color(0xFFF37E20),
      usernameHint: 'User ID / Mobile',
    ),
    PasswordServicePreset(
      id: 'steam',
      name: 'Steam',
      defaultUrl: 'https://store.steampowered.com',
      domains: ['steampowered.com', 'steamcommunity.com'],
      androidPackages: ['com.valvesoftware.android.steam.community'],
      icon: Icons.sports_esports_outlined,
      accentColor: Color(0xFF171A21),
      usernameHint: 'Steam account name',
    ),
  ];

  static const List<IdentityDocTemplate> identityTemplates = [
    IdentityDocTemplate(
      id: 'aadhaar',
      displayName: 'Aadhaar Card',
      shortLabel: 'Aadhaar',
      icon: Icons.fingerprint_rounded,
      fields: [
        IdentityFieldSpec(
          key: 'idNumber',
          label: 'AADHAAR NUMBER (12 DIGITS)',
          hint: '1234 5678 9012',
          icon: Icons.tag_rounded,
          isSecret: true,
          aadhaarGrouped: true,
          maxLength: 14,
        ),
        IdentityFieldSpec(
          key: 'holderName',
          label: 'FULL NAME ON AADHAAR',
          hint: 'Enter full name',
          icon: Icons.person_outline_rounded,
        ),
        IdentityFieldSpec(
          key: 'dob',
          label: 'DATE OF BIRTH',
          hint: 'DD/MM/YYYY',
          icon: Icons.cake_outlined,
          isDate: true,
        ),
        IdentityFieldSpec(
          key: 'vid',
          label: 'VIRTUAL ID (VID · OPTIONAL)',
          hint: '16-digit VID',
          icon: Icons.shield_outlined,
          isSecret: true,
        ),
        IdentityFieldSpec(
          key: 'address',
          label: 'REGISTERED ADDRESS',
          hint: 'House, street, city, PIN code',
          icon: Icons.home_outlined,
        ),
      ],
    ),
    IdentityDocTemplate(
      id: 'pan',
      displayName: 'PAN Card',
      shortLabel: 'PAN Card',
      icon: Icons.credit_card_outlined,
      fields: [
        IdentityFieldSpec(
          key: 'idNumber',
          label: 'PAN NUMBER',
          hint: 'ABCDE1234F',
          icon: Icons.tag_rounded,
          isSecret: true,
          uppercase: true,
          maxLength: 10,
        ),
        IdentityFieldSpec(
          key: 'holderName',
          label: 'FULL NAME',
          hint: 'Name as printed on PAN',
          icon: Icons.person_outline_rounded,
        ),
        IdentityFieldSpec(
          key: 'fatherName',
          label: "FATHER'S NAME",
          hint: "Father's full name",
          icon: Icons.family_restroom_outlined,
        ),
        IdentityFieldSpec(
          key: 'dob',
          label: 'DATE OF BIRTH',
          hint: 'DD/MM/YYYY',
          icon: Icons.cake_outlined,
          isDate: true,
        ),
      ],
    ),
    IdentityDocTemplate(
      id: 'passport',
      displayName: 'Passport',
      shortLabel: 'Passport',
      icon: Icons.public_rounded,
      fields: [
        IdentityFieldSpec(
          key: 'idNumber',
          label: 'PASSPORT NUMBER',
          hint: 'e.g. Z1234567',
          icon: Icons.tag_rounded,
          isSecret: true,
          uppercase: true,
          maxLength: 12,
        ),
        IdentityFieldSpec(
          key: 'holderName',
          label: 'GIVEN NAME & SURNAME',
          hint: 'Full name as on passport',
          icon: Icons.person_outline_rounded,
        ),
        IdentityFieldSpec(
          key: 'nationality',
          label: 'NATIONALITY',
          hint: 'e.g. Indian',
          icon: Icons.flag_outlined,
        ),
        IdentityFieldSpec(
          key: 'dob',
          label: 'DATE OF BIRTH',
          hint: 'DD/MM/YYYY',
          icon: Icons.cake_outlined,
          isDate: true,
        ),
        IdentityFieldSpec(
          key: 'issuedBy',
          label: 'PLACE OF ISSUE',
          hint: 'e.g. New Delhi / Mumbai',
          icon: Icons.location_on_outlined,
        ),
        IdentityFieldSpec(
          key: 'issueDate',
          label: 'DATE OF ISSUE',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_available_outlined,
          isDate: true,
        ),
        IdentityFieldSpec(
          key: 'expiry',
          label: 'DATE OF EXPIRY',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_outlined,
          isDate: true,
        ),
        IdentityFieldSpec(
          key: 'fileNumber',
          label: 'FILE NUMBER (OPTIONAL)',
          hint: 'Passport file number',
          icon: Icons.folder_outlined,
        ),
      ],
    ),
    IdentityDocTemplate(
      id: 'driving_license',
      displayName: 'Driving License',
      shortLabel: 'Driving License',
      icon: Icons.directions_car_outlined,
      fields: [
        IdentityFieldSpec(
          key: 'idNumber',
          label: 'LICENSE NUMBER',
          hint: 'e.g. DL-0120200012345',
          icon: Icons.tag_rounded,
          isSecret: true,
          uppercase: true,
        ),
        IdentityFieldSpec(
          key: 'holderName',
          label: 'HOLDER NAME',
          hint: 'Full name',
          icon: Icons.person_outline_rounded,
        ),
        IdentityFieldSpec(
          key: 'dob',
          label: 'DATE OF BIRTH',
          hint: 'DD/MM/YYYY',
          icon: Icons.cake_outlined,
          isDate: true,
        ),
        IdentityFieldSpec(
          key: 'bloodGroup',
          label: 'BLOOD GROUP',
          hint: 'e.g. O+, B+, A-',
          icon: Icons.bloodtype_outlined,
        ),
        IdentityFieldSpec(
          key: 'vehicleClass',
          label: 'VEHICLE CLASS',
          hint: 'e.g. MCWG, LMV',
          icon: Icons.commute_outlined,
          uppercase: true,
        ),
        IdentityFieldSpec(
          key: 'issuedBy',
          label: 'ISSUING RTO / STATE',
          hint: 'e.g. RTO Bengaluru Central',
          icon: Icons.account_balance_outlined,
        ),
        IdentityFieldSpec(
          key: 'expiry',
          label: 'VALID TILL',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_outlined,
          isDate: true,
        ),
      ],
    ),
    IdentityDocTemplate(
      id: 'voter_id',
      displayName: 'Voter ID (EPIC)',
      shortLabel: 'Voter ID',
      icon: Icons.how_to_vote_outlined,
      fields: [
        IdentityFieldSpec(
          key: 'idNumber',
          label: 'EPIC NUMBER',
          hint: 'e.g. ABC1234567',
          icon: Icons.tag_rounded,
          isSecret: true,
          uppercase: true,
        ),
        IdentityFieldSpec(
          key: 'holderName',
          label: 'ELECTOR NAME',
          hint: 'Full name',
          icon: Icons.person_outline_rounded,
        ),
        IdentityFieldSpec(
          key: 'dob',
          label: 'DATE OF BIRTH',
          hint: 'DD/MM/YYYY',
          icon: Icons.cake_outlined,
          isDate: true,
        ),
        IdentityFieldSpec(
          key: 'issuedBy',
          label: 'CONSTITUENCY / STATE',
          hint: 'Assembly constituency',
          icon: Icons.map_outlined,
        ),
      ],
    ),
    IdentityDocTemplate(
      id: 'vehicle_rc',
      displayName: 'Vehicle RC',
      shortLabel: 'Vehicle RC',
      icon: Icons.two_wheeler_rounded,
      fields: [
        IdentityFieldSpec(
          key: 'idNumber',
          label: 'REGISTRATION NUMBER',
          hint: 'e.g. MH12AB1234',
          icon: Icons.tag_rounded,
          uppercase: true,
        ),
        IdentityFieldSpec(
          key: 'holderName',
          label: 'OWNER NAME',
          hint: 'Registered owner',
          icon: Icons.person_outline_rounded,
        ),
        IdentityFieldSpec(
          key: 'makeModel',
          label: 'VEHICLE MAKE & MODEL',
          hint: 'e.g. Hyundai Creta SX',
          icon: Icons.directions_car_filled_outlined,
        ),
        IdentityFieldSpec(
          key: 'chassisNumber',
          label: 'CHASSIS NUMBER (VIN)',
          hint: '17-char VIN / Chassis No.',
          icon: Icons.confirmation_number_outlined,
          isSecret: true,
          uppercase: true,
        ),
        IdentityFieldSpec(
          key: 'engineNumber',
          label: 'ENGINE NUMBER',
          hint: 'Engine number',
          icon: Icons.build_outlined,
          isSecret: true,
          uppercase: true,
        ),
        IdentityFieldSpec(
          key: 'expiry',
          label: 'REG / FITNESS VALID TILL',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_outlined,
          isDate: true,
        ),
      ],
    ),
    IdentityDocTemplate(
      id: 'insurance',
      displayName: 'Health / Insurance ID',
      shortLabel: 'Insurance',
      icon: Icons.health_and_safety_outlined,
      fields: [
        IdentityFieldSpec(
          key: 'idNumber',
          label: 'POLICY / MEMBER NUMBER',
          hint: 'Policy or UHID number',
          icon: Icons.tag_rounded,
          isSecret: true,
        ),
        IdentityFieldSpec(
          key: 'issuedBy',
          label: 'INSURER / TPA NAME',
          hint: 'e.g. Star Health, HDFC ERGO',
          icon: Icons.local_hospital_outlined,
        ),
        IdentityFieldSpec(
          key: 'holderName',
          label: 'INSURED PERSON',
          hint: 'Primary insured name',
          icon: Icons.person_outline_rounded,
        ),
        IdentityFieldSpec(
          key: 'sumInsured',
          label: 'SUM INSURED / COVERAGE',
          hint: 'e.g. ₹10,00,000',
          icon: Icons.shield_outlined,
        ),
        IdentityFieldSpec(
          key: 'expiry',
          label: 'RENEWAL / EXPIRY DATE',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_outlined,
          isDate: true,
        ),
      ],
    ),
    IdentityDocTemplate(
      id: 'custom',
      displayName: 'Custom ID Document',
      shortLabel: 'Custom ID',
      icon: Icons.badge_outlined,
      fields: [
        IdentityFieldSpec(
          key: 'idNumber',
          label: 'ID / DOCUMENT NUMBER',
          hint: 'Enter document number',
          icon: Icons.tag_rounded,
          isSecret: true,
        ),
        IdentityFieldSpec(
          key: 'holderName',
          label: 'HOLDER NAME',
          hint: 'Full name on document',
          icon: Icons.person_outline_rounded,
        ),
        IdentityFieldSpec(
          key: 'dob',
          label: 'DATE OF BIRTH',
          hint: 'DD/MM/YYYY',
          icon: Icons.cake_outlined,
          isDate: true,
        ),
        IdentityFieldSpec(
          key: 'issuedBy',
          label: 'ISSUED BY',
          hint: 'Issuing authority',
          icon: Icons.account_balance_outlined,
        ),
        IdentityFieldSpec(
          key: 'expiry',
          label: 'EXPIRY DATE',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_outlined,
          isDate: true,
        ),
      ],
    ),
  ];

  static const List<String> popularBanks = [
    'HDFC Bank',
    'SBI',
    'ICICI Bank',
    'Axis Bank',
    'Kotak Mahindra',
    'American Express',
    'IDFC FIRST',
    'Yes Bank',
    'IndusInd Bank',
    'Chase',
  ];

  static IdentityDocTemplate identityTemplateById(String? id) {
    if (id != null && id.isNotEmpty) {
      for (final t in identityTemplates) {
        if (t.id == id) return t;
      }
    }
    return identityTemplates.last; // custom fallback
  }

  /// Infers an [IdentityDocTemplate] from a saved JSON map (supporting legacy items).
  static IdentityDocTemplate inferIdentityTemplate(Map<String, dynamic> data) {
    final explicit = data['docType'] as String?;
    if (explicit != null && explicit.isNotEmpty) {
      return identityTemplateById(explicit);
    }
    final docName = (data['documentName'] as String? ?? '').toLowerCase();
    if (docName.contains('aadhaar') || docName.contains('aadhar')) {
      return identityTemplateById('aadhaar');
    }
    if (docName == 'pan' || docName.contains('pan card')) {
      return identityTemplateById('pan');
    }
    if (docName.contains('passport')) {
      return identityTemplateById('passport');
    }
    if (docName.contains('driving') || docName.contains('licence') || docName.contains('license')) {
      return identityTemplateById('driving_license');
    }
    if (docName.contains('voter') || docName.contains('epic')) {
      return identityTemplateById('voter_id');
    }
    if (docName.contains('rc') || docName.contains('registration')) {
      return identityTemplateById('vehicle_rc');
    }
    if (docName.contains('insurance') || docName.contains('health')) {
      return identityTemplateById('insurance');
    }
    return identityTemplateById('custom');
  }

  /// Resolves known domains & Android package names from a preset, title, or URL
  /// so OS Autofill matches accurately even when the user only typed "Amazon" or "Gmail".
  static ({List<String> domains, List<String> packages}) resolveAutofillTargets({
    required String title,
    required String url,
    List<String>? explicitDomains,
    List<String>? explicitPackages,
  }) {
    final domains = <String>{
      if (explicitDomains != null)
        ...explicitDomains
            .map(extractNormalizedDomain)
            .where((d) => d.isNotEmpty),
    };
    final packages = <String>{
      if (explicitPackages != null)
        ...explicitPackages.map((p) => p.trim()).where((p) => p.isNotEmpty),
    };

    final urlDomain = extractNormalizedDomain(url);
    if (urlDomain.isNotEmpty) {
      domains.add(urlDomain);
    }

    final lowerTitle = title.trim().toLowerCase();
    for (final preset in passwordPresets) {
      final presetNameLower = preset.name.toLowerCase();
      final idLower = preset.id.toLowerCase();
      final matchesTitle = lowerTitle == presetNameLower ||
          lowerTitle == idLower ||
          presetNameLower.split('/').any((part) => part.trim() == lowerTitle) ||
          (lowerTitle.length >= 4 && preset.domains.any((d) => d.split('.').first == lowerTitle));
      final matchesDomain =
          urlDomain.isNotEmpty && preset.domains.any((d) => urlDomain == d || urlDomain.endsWith('.$d'));

      if (matchesTitle || matchesDomain) {
        domains.addAll(preset.domains.map(extractNormalizedDomain));
        packages.addAll(preset.androidPackages);
      }
    }

    return (
      domains: domains.where((d) => d.isNotEmpty).toList(),
      packages: packages.toList(),
    );
  }

  /// Normalizes a URL or host string to its registrable/canonical lowercase host.
  static String extractNormalizedDomain(String raw) {
    var trimmed = raw.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    if (!trimmed.contains('://')) {
      trimmed = 'https://$trimmed';
    }
    final uri = Uri.tryParse(trimmed);
    var host = uri?.host ?? '';
    if (host.startsWith('www.')) {
      host = host.substring(4);
    }
    if (host.startsWith('m.')) {
      host = host.substring(2);
    }
    return host;
  }

  /// Detects payment card network from IIN/BIN digits.
  static String detectCardNetwork(String rawCardNumber) {
    final digits = rawCardNumber.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'CARD';
    if (digits.startsWith('4')) return 'VISA';
    if (digits.startsWith('34') || digits.startsWith('37')) return 'AMEX';
    if (digits.startsWith('60') ||
        digits.startsWith('6521') ||
        digits.startsWith('6522') ||
        digits.startsWith('81') ||
        digits.startsWith('82') ||
        digits.startsWith('508')) {
      return 'RUPAY';
    }
    final prefix2 = digits.length >= 2 ? int.tryParse(digits.substring(0, 2)) ?? 0 : 0;
    final prefix4 = digits.length >= 4 ? int.tryParse(digits.substring(0, 4)) ?? 0 : 0;
    if ((prefix2 >= 51 && prefix2 <= 55) || (prefix4 >= 2221 && prefix4 <= 2720)) {
      return 'MASTERCARD';
    }
    if (digits.startsWith('6011') || digits.startsWith('65')) return 'DISCOVER';
    return 'CARD';
  }

  /// Cryptographically secure password generator with guaranteed class coverage.
  static String generateStrongPassword({
    int length = 18,
    bool uppercase = true,
    bool lowercase = true,
    bool digits = true,
    bool symbols = true,
  }) {
    const upperChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
    const lowerChars = 'abcdefghijkmnopqrstuvwxyz';
    const digitChars = '23456789';
    const symbolChars = '!@#\$%^&*_-+=?';

    final pools = <String>[
      if (uppercase) upperChars,
      if (lowercase) lowerChars,
      if (digits) digitChars,
      if (symbols) symbolChars,
    ];
    if (pools.isEmpty) {
      pools.add(lowerChars);
    }

    final rng = Random.secure();
    final effectiveLen = length.clamp(8, 64);
    final chars = <String>[];

    // Guarantee at least one character from each enabled class
    for (final pool in pools) {
      chars.add(pool[rng.nextInt(pool.length)]);
    }

    final combined = pools.join();
    while (chars.length < effectiveLen) {
      chars.add(combined[rng.nextInt(combined.length)]);
    }

    // Fisher-Yates CSPRNG shuffle
    for (int i = chars.length - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = chars[i];
      chars[i] = chars[j];
      chars[j] = tmp;
    }

    return chars.join();
  }

  /// Evaluates password entropy/strength in `[0.0 .. 1.0]` + human label.
  static ({double score, String label}) evaluatePasswordStrength(String password) {
    if (password.isEmpty) return (score: 0.0, label: 'Empty');
    int classes = 0;
    if (RegExp(r'[a-z]').hasMatch(password)) classes++;
    if (RegExp(r'[A-Z]').hasMatch(password)) classes++;
    if (RegExp(r'[0-9]').hasMatch(password)) classes++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) classes++;

    double score = (password.length / 20.0).clamp(0.0, 0.65) + (classes * 0.0875);
    if (password.length < 8) {
      score = score.clamp(0.0, 0.3);
    }
    score = score.clamp(0.0, 1.0);

    if (score < 0.35) return (score: score, label: 'Weak');
    if (score < 0.65) return (score: score, label: 'Fair');
    if (score < 0.85) return (score: score, label: 'Strong');
    return (score: score, label: 'Very Strong');
  }

  /// Humanizes camelCase JSON field keys into natural phrases for AI RAG indexing.
  static String humanizeFieldKey(String key) {
    const overrides = <String, String>{
      'idNumber': 'ID number',
      'holderName': 'holder name',
      'fatherName': "father's name",
      'dob': 'date of birth',
      'vid': 'virtual ID',
      'issuedBy': 'issued by',
      'issueDate': 'issue date',
      'expiry': 'expiry date',
      'fileNumber': 'file number',
      'bloodGroup': 'blood group',
      'vehicleClass': 'vehicle class',
      'makeModel': 'vehicle make and model',
      'chassisNumber': 'chassis number',
      'engineNumber': 'engine number',
      'sumInsured': 'sum insured',
      'bankName': 'bank name',
      'cardHolder': 'cardholder name',
      'cardNumber': 'card number',
      'cardType': 'card type',
      'upiPin': 'UPI PIN',
      'ifscCode': 'IFSC code',
      'accountNumber': 'account number',
      'customerId': 'customer ID',
      'transactionPassword': 'transaction password',
      'ssid': 'Wi-Fi network SSID',
      'securityType': 'Wi-Fi security type',
      'routerIp': 'router admin IP',
      'apiKey': 'API key',
      'apiSecret': 'API secret token',
      'environment': 'environment',
    };
    if (overrides.containsKey(key)) return overrides[key]!;
    return key
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAll('_', ' ')
        .toLowerCase();
  }
}

