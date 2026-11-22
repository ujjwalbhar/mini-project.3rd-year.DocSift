import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../auth/data/auth_repository.dart';
import '../ocr/domain/extraction_queue.dart';
import '../vault/data/vault_repository.dart';
import '../vault/domain/models/vault_item.dart';
import '../vault/domain/models/vault_templates.dart';
import '../vault/domain/vault_service.dart';

final autofillSyncServiceProvider = Provider<AutofillSyncService>((ref) {
  return AutofillSyncService(
    authRepo: ref.read(authRepositoryProvider),
    vaultService: ref.read(vaultServiceProvider),
    vaultRepo: ref.read(vaultRepositoryProvider),
    extractionQueue: ref.read(extractionQueueProvider),
  );
});

final autofillEnabledStatusProvider = FutureProvider.autoDispose<bool>((ref) async {
  return ref.read(autofillSyncServiceProvider).isSystemAutofillEnabled();
});

/// Bridges DocSift's encrypted vault with Android's native `AutofillService`
/// (`DocSiftAutofillService`) using hardware-keystore-encrypted storage.
class AutofillSyncService {
  AutofillSyncService({
    required AuthRepository authRepo,
    required VaultService vaultService,
    required VaultRepository vaultRepo,
    required ExtractionQueue extractionQueue,
  })  : _authRepo = authRepo,
        _vaultService = vaultService,
        _vaultRepo = vaultRepo,
        _extractionQueue = extractionQueue;

  static const MethodChannel _channel =
      MethodChannel('com.docsift.docsift/autofill');

  final AuthRepository _authRepo;
  final VaultService _vaultService;
  final VaultRepository _vaultRepo;
  final ExtractionQueue _extractionQueue;
  bool _isSyncing = false;

  bool get isSupportedPlatform {
    try {
      return Platform.isAndroid;
    } catch (_) {
      return false;
    }
  }

  /// Checks whether DocSift is currently selected as the active Android Autofill provider.
  Future<bool> isSystemAutofillEnabled() async {
    if (!isSupportedPlatform) return false;
    try {
      final enabled =
          await _channel.invokeMethod<bool>('isAutofillServiceEnabled');
      return enabled ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Opens Android's official "Autofill service" system settings sheet for DocSift.
  Future<bool> requestEnableSystemAutofill() async {
    if (!isSupportedPlatform) return false;
    _authRepo.isBypassAutoLock = true;
    try {
      final result = await _channel.invokeMethod<bool>('openAutofillSettings');
      return result ?? false;
    } on MissingPluginException {
      return false;
    } catch (_) {
      return false;
    } finally {
      _authRepo.isBypassAutoLock = false;
    }
  }

  /// Imports any new logins captured by `DocSiftAutofillService.onSaveRequest`
  /// when the user created accounts in external apps/browsers, then pushes the
  /// latest autofill credential index to Android's Keystore-encrypted store.
  /// Returns the count of newly imported external accounts.
  Future<int> syncVaultAndImportCapturedLogins() async {
    if (!isSupportedPlatform || _authRepo.isLocked || _isSyncing) return 0;
    _isSyncing = true;
    int importedCount = 0;

    try {
      // 1. Drain any credentials captured via OS "Save to DocSift?" prompts
      final rawPending =
          await _channel.invokeMethod<List<dynamic>>('consumePendingSaves');
      if (rawPending != null && rawPending.isNotEmpty) {
        for (final raw in rawPending) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);
          final username = (map['username'] as String? ?? '').trim();
          final password = map['password'] as String? ?? '';
          if (password.isEmpty) continue;

          final rawTitle = (map['title'] as String? ?? '').trim();
          final domain = (map['domain'] as String? ?? '').trim();
          final pkg = (map['packageName'] as String? ?? '').trim();

          final effectiveTitle = rawTitle.isNotEmpty
              ? rawTitle
              : (domain.isNotEmpty ? domain : pkg);
          final defaultUrl = domain.isNotEmpty ? 'https://$domain' : '';

          final targets = VaultTemplates.resolveAutofillTargets(
            title: effectiveTitle,
            url: defaultUrl,
            explicitDomains: domain.isNotEmpty ? [domain] : null,
            explicitPackages: pkg.isNotEmpty ? [pkg] : null,
          );

          final jsonPayload = <String, dynamic>{
            'subType': PasswordSubTemplate.appLogin.name,
            'title': effectiveTitle.isNotEmpty ? effectiveTitle : 'Saved Login',
            'username': username,
            'password': password,
            'url': defaultUrl,
            'domains': targets.domains,
            'androidPackages': targets.packages,
            'notes': 'Captured automatically via DocSift Autofill',
          };

          final created = await _vaultService.importJsonItem(
            jsonPayload['title'] as String,
            jsonPayload,
            'passwords',
          );
          _extractionQueue.enqueue(created);
          importedCount++;
        }
      }

      // 2. Push current vault password entries to the hardware-encrypted autofill index
      final passwordItems =
          await _vaultService.getVaultItems(categoryId: 'passwords');
      final outgoing = <Map<String, dynamic>>[];

      for (final item in passwordItems) {
        if (item.fileType != FileType.json) continue;
        Uint8List? plainBytes;
        try {
          plainBytes = await _vaultRepo.decryptToMemory(item.encryptedFilePath);
          final jsonStr = utf8.decode(plainBytes, allowMalformed: true);
          final data = jsonDecode(jsonStr);
          if (data is! Map<String, dynamic>) continue;

          final subType = PasswordSubTemplate.fromKey(data['subType'] as String?);
          if (subType == PasswordSubTemplate.wifi ||
              subType == PasswordSubTemplate.apiKey) {
            continue;
          }

          final title =
              (data['title'] as String? ?? item.displayName).trim();
          final username = (data['username'] as String? ??
                  data['customerId'] as String? ??
                  '')
              .trim();
          final password = (data['password'] as String? ?? '');
          if (password.isEmpty) continue;

          final url = (data['url'] as String? ?? '').trim();
          final explicitDomains = (data['domains'] as List?)
              ?.map((e) => e.toString())
              .toList();
          final explicitPackages = (data['androidPackages'] as List?)
              ?.map((e) => e.toString())
              .toList();

          final targets = VaultTemplates.resolveAutofillTargets(
            title: title,
            url: url,
            explicitDomains: explicitDomains,
            explicitPackages: explicitPackages,
          );

          outgoing.add(<String, dynamic>{
            'id': item.id,
            'title': title,
            'username': username,
            'password': password,
            'domains': targets.domains,
            'packages': targets.packages,
            'updatedAt': item.modifiedAt.millisecondsSinceEpoch,
          });
        } catch (_) {
          // Skip malformed item without interrupting sync
        } finally {
          if (plainBytes != null) {
            for (int i = 0; i < plainBytes.length; i++) {
              plainBytes[i] = 0;
            }
          }
        }
      }

      await _channel.invokeMethod<void>('syncCredentials', outgoing);
    } on MissingPluginException {
      // Running in unit tests or unsupported platform
    } catch (_) {
      // Non-fatal
    } finally {
      _isSyncing = false;
    }

    return importedCount;
  }

  /// Wipes all native autofill index files (used during Factory Reset).
  Future<void> clearNativeAutofillStore() async {
    if (!isSupportedPlatform) return;
    try {
      await _channel.invokeMethod<void>('clearAllAutofillData');
    } catch (_) {}
  }
}

