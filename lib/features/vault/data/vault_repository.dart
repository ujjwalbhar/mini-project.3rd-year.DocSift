import 'dart:io';
import 'dart:typed_data';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';
import 'package:uuid/uuid.dart';
import '../../auth/data/auth_repository.dart';

final vaultRepositoryProvider = Provider<VaultRepository>((ref) {
  final authRepo = ref.read(authRepositoryProvider);
  return VaultRepository(authRepo);
});

class VaultRepository {
  VaultRepository(this._authRepo);

  final AuthRepository _authRepo;
  final _uuid = const Uuid();

  /// Encrypts a source file and saves it to the secure vault directory.
  /// Returns the path to the encrypted file.
  Future<String> encryptAndStore(File sourceFile) async {
    final vek = _authRepo.vaultEncryptionKey;
    if (vek == null) {
      throw Exception('Vault is locked. Cannot encrypt file.');
    }

    final sourceBytes = await sourceFile.readAsBytes();
    
    // Generate 12-byte IV for GCM
    final rng = Random.secure();
    final iv = Uint8List.fromList(List<int>.generate(12, (_) => rng.nextInt(256)));

    // Set up AES-GCM cipher
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // encrypt
        AEADParameters(
          KeyParameter(Uint8List.fromList(vek)),
          128, // 16 bytes MAC length
          iv,
          Uint8List(0), // empty AAD
        ),
      );

    // Encrypt
    final ciphertextAndMac = cipher.process(sourceBytes);

    // Format: [12 bytes IV] + [ciphertext + 16 bytes MAC]
    final finalBytes = BytesBuilder()
      ..add(iv)
      ..add(ciphertextAndMac);

    // Store in vault directory
    final appDocsDir = await getApplicationDocumentsDirectory();
    final vaultDir = Directory(p.join(appDocsDir.path, 'vault_files'));
    if (!await vaultDir.exists()) {
      await vaultDir.create(recursive: true);
    }

    final encryptedFileName = '${_uuid.v4()}.enc';
    final encryptedPath = p.join(vaultDir.path, encryptedFileName);

    final encryptedFile = File(encryptedPath);
    await encryptedFile.writeAsBytes(finalBytes.toBytes(), flush: true);

    // Wipe plain text bytes from memory
    for (int i = 0; i < sourceBytes.length; i++) {
      sourceBytes[i] = 0;
    }

    return encryptedPath;
  }

  /// Decrypts a file from the vault directly into memory.
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

    // Extract IV and ciphertext
    final iv = allBytes.sublist(0, 12);
    final ciphertextAndMac = allBytes.sublist(12);

    // Set up AES-GCM cipher
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // decrypt
        AEADParameters(
          KeyParameter(Uint8List.fromList(vek)),
          128,
          iv,
          Uint8List(0),
        ),
      );

    // Decrypt
    final plaintext = cipher.process(ciphertextAndMac);
    return plaintext;
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
