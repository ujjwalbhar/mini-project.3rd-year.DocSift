import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:docsift/features/auth/data/auth_repository.dart';
import 'package:docsift/features/vault/data/vault_repository.dart';

class _TestAuthRepository extends AuthRepository {
  _TestAuthRepository({required this.locked, List<int>? key})
      : _key = key ?? List<int>.generate(32, (i) => (i * 7 + 13) & 0xFF);

  bool locked;
  final List<int> _key;

  @override
  bool get isLocked => locked;

  @override
  List<int>? get vaultEncryptionKey => locked ? null : _key;
}

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('docsift_crypto_test_');
  });

  tearDown(() async {
    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });

  test('VaultRepository AES-256-GCM encrypts, stores, decrypts, and securely deletes files', () async {
    final auth = _TestAuthRepository(locked: false);
    final repo = VaultRepository(auth, vaultRootOverride: tempRoot);

    const secretMessage = 'Top secret passport & banking recovery keys 2026!';
    final sourceFile = File('${tempRoot.path}/plain.txt');
    await sourceFile.writeAsBytes(utf8.encode(secretMessage));

    final encPath = await repo.encryptAndStore(sourceFile);
    final encFile = File(encPath);
    expect(await encFile.exists(), isTrue);

    // Ciphertext on disk must not contain plaintext
    final rawEncrypted = await encFile.readAsBytes();
    expect(
      utf8.decode(rawEncrypted, allowMalformed: true),
      isNot(contains('Top secret passport')),
    );

    // Decrypt back to memory and verify exact byte equality
    final decrypted = await repo.decryptToMemory(encPath);
    expect(utf8.decode(decrypted), secretMessage);

    // Secure delete removes file from disk
    await repo.deleteVaultFile(encPath);
    expect(await encFile.exists(), isFalse);
  });

  test('VaultRepository rejects encrypt and decrypt when vault is locked', () async {
    final auth = _TestAuthRepository(locked: true);
    final repo = VaultRepository(auth, vaultRootOverride: tempRoot);

    final sourceFile = File('${tempRoot.path}/plain.txt');
    await sourceFile.writeAsString('secret');

    expect(() => repo.encryptAndStore(sourceFile), throwsException);
    expect(() => repo.decryptToMemory('${tempRoot.path}/missing.enc'), throwsException);
  });

  test('VaultRepository AES-256-GCM detects tampered ciphertext via MAC check', () async {
    final auth = _TestAuthRepository(locked: false);
    final repo = VaultRepository(auth, vaultRootOverride: tempRoot);

    final sourceFile = File('${tempRoot.path}/plain.txt');
    await sourceFile.writeAsString('Authentic vault payload');

    final encPath = await repo.encryptAndStore(sourceFile);
    final encFile = File(encPath);
    final bytes = Uint8List.fromList(await encFile.readAsBytes());

    // Flip one bit in the ciphertext/MAC region
    bytes[bytes.length - 5] ^= 0xFF;
    await encFile.writeAsBytes(bytes, flush: true);

    expect(() => repo.decryptToMemory(encPath), throwsA(anything));
  });
}

