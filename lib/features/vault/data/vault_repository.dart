import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';
import '../../auth/data/auth_repository.dart';

final vaultRepositoryProvider = Provider<VaultRepository>((ref) {
  final authRepo = ref.read(authRepositoryProvider);
  return VaultRepository(authRepo);
});

class VaultRepository {
  VaultRepository(this._authRepo, {Directory? vaultRootOverride})
      : _vaultRootOverride = vaultRootOverride;

  final AuthRepository _authRepo;
  final Directory? _vaultRootOverride;
  final _uuid = const Uuid();

  /// Encrypts a source file off-thread via AES-256-GCM and saves it to the
  /// secure vault directory. Returns the path to the encrypted `.enc` file.
  Future<String> encryptAndStore(File sourceFile) async {
    final vek = _authRepo.vaultEncryptionKey;
    if (vek == null) {
      throw Exception('Vault is locked. Cannot encrypt file.');
    }

    final sourceBytes = await sourceFile.readAsBytes();
    final vekCopy = Uint8List.fromList(vek);
    final transferablePlain = TransferableTypedData.fromList([sourceBytes]);
    final transferableKey = TransferableTypedData.fromList([vekCopy]);

    // Wipe caller-side plaintext & key copies immediately after staging transfer
    _wipeBytes(sourceBytes);
    _wipeBytes(vekCopy);

    final transferableEnc = await Isolate.run(
      () => _encryptBytesIsolate(transferablePlain, transferableKey),
    );
    final encryptedPayload = transferableEnc.materialize().asUint8List();

    // Store in vault directory
    final baseDir =
        _vaultRootOverride ?? await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(baseDir.path, 'vault_files'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    final encryptedFileName = '${_uuid.v4()}.enc';
    final encryptedPath = p.join(vaultDir.path, encryptedFileName);

    final encryptedFile = File(encryptedPath);
    await encryptedFile.writeAsBytes(encryptedPayload, flush: true);

    return encryptedPath;
  }

  /// Decrypts a file from the vault directly into memory on a background isolate.
  /// Ensure you wipe the returned Uint8List when done!
  Future<Uint8List> decryptToMemory(String encryptedPath) async {
    final vek = _authRepo.vaultEncryptionKey;
    if (vek == null) {
      throw Exception('Vault is locked. Cannot decrypt file.');
    }

    final encryptedFile = File(encryptedPath);
    if (!await encryptedFile.exists()) {
      throw Exception('Encrypted file not found.');
    }

    final allBytes = await encryptedFile.readAsBytes();

    if (allBytes.length < 28) {
      // 12 (IV) + 16 (MAC) = 28 minimum
      throw Exception('Invalid encrypted file format.');
    }

    final vekCopy = Uint8List.fromList(vek);
    final transferableEnc = TransferableTypedData.fromList([allBytes]);
    final transferableKey = TransferableTypedData.fromList([vekCopy]);
    _wipeBytes(vekCopy);

    final transferablePlain = await Isolate.run(
      () => _decryptBytesIsolate(transferableEnc, transferableKey),
    );
    return transferablePlain.materialize().asUint8List();
  }

  static TransferableTypedData _encryptBytesIsolate(
    TransferableTypedData transferablePlain,
    TransferableTypedData transferableKey,
  ) {
    final plain = transferablePlain.materialize().asUint8List();
    final key = transferableKey.materialize().asUint8List();
    try {
      final rng = Random.secure();
      final iv =
          Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true, // encrypt
          AEADParameters(
            KeyParameter(key),
            128, // 16 bytes MAC length
            iv,
            Uint8List(0), // empty AAD
          ),
        );

      final ciphertextAndMac = cipher.process(plain);

      // Format: [12 bytes IV] + [ciphertext + 16 bytes MAC]
      final out = Uint8List(iv.length + ciphertextAndMac.length);
      out.setRange(0, iv.length, iv);
      out.setRange(iv.length, out.length, ciphertextAndMac);
      return TransferableTypedData.fromList([out]);
    } finally {
      _wipeBytes(plain);
      _wipeBytes(key);
    }
  }

  static TransferableTypedData _decryptBytesIsolate(
    TransferableTypedData transferableEnc,
    TransferableTypedData transferableKey,
  ) {
    final allBytes = transferableEnc.materialize().asUint8List();
    final key = transferableKey.materialize().asUint8List();
    try {
      final iv = Uint8List.sublistView(allBytes, 0, 12);
      final ciphertextAndMac = Uint8List.sublistView(allBytes, 12);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false, // decrypt
          AEADParameters(
            KeyParameter(key),
            128,
            iv,
            Uint8List(0),
          ),
        );

      final plaintext = cipher.process(ciphertextAndMac);
      return TransferableTypedData.fromList([plaintext]);
    } finally {
      _wipeBytes(key);
    }
  }

  static void _wipeBytes(Uint8List bytes) {
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  /// Deletes an encrypted file from the filesystem.
  Future<void> deleteVaultFile(String encryptedPath) async {
    final file = File(encryptedPath);
    if (await file.exists()) {
      // Optional: Securely wipe the file before deleting
      final length = await file.length();
      final rng = Random.secure();
      final wipeBytes = List<int>.generate(min(length, 1024 * 1024), (_) => rng.nextInt(256));
      try {
        final sink = file.openWrite();
        int written = 0;
        while (written < length) {
          sink.add(wipeBytes);
          written += wipeBytes.length;
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        // Ignore wipe errors
      }
      
      await file.delete();
    }
  }
}
