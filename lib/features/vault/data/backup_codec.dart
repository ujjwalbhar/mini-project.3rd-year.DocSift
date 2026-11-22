import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:pointycastle/export.dart';

/// Thrown when a `.docsift` backup archive fails magic validation, AEAD tag
/// authentication (wrong passphrase or tampered bytes), or structural parsing.
class BackupAuthException implements Exception {
  const BackupAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Unsealed contents of a verified `.docsift` backup archive.
class RestoredBackupPayload {
  const RestoredBackupPayload({
    required this.createdAt,
    required this.vek,
    required this.dbKey,
    required this.dbBytes,
    required this.encryptedFiles,
  });

  final DateTime createdAt;
  final Uint8List vek; // 32-byte Vault Encryption Key
  final String dbKey; // SQLCipher database password
  final Uint8List dbBytes; // Raw SQLCipher docsift_vault.db bytes
  final Map<String, Uint8List> encryptedFiles; // basename.enc -> ciphertext
}

/// Portable zero-trust `.docsift` backup archive encoder/decoder.
///
/// Binary Wire Format:
/// - `[0..5]`   5B magic + version: `'DSBK\x01'` (`0x44 0x53 0x42 0x4B 0x01`)
/// - `[5..9]`   4B `uint32LE` PBKDF2-HMAC-SHA256 iteration count
/// - `[9..41]`  32B CSPRNG salt
/// - `[41..53]` 12B CSPRNG AES-256-GCM nonce/IV
/// - `[53..]`   AES-256-GCM ciphertext + 16B authentication tag
///              (with AAD = bytes `[0..41]` binding version, iterations & salt)
class BackupCodec {
  const BackupCodec._();

  static const List<int> _magic = <int>[0x44, 0x53, 0x42, 0x4B, 0x01]; // DSBK\x01
  static const int defaultIterations = 100000;
  static const int _minIterations = 1000;
  static const int _maxIterations = 2000000;
  static const int _headerAadLen = 5 + 4 + 32; // 41 bytes
  static const int _ivLen = 12;
  static const int _macLen = 16;
  static const int _minArchiveLen = _headerAadLen + _ivLen + _macLen; // 69 bytes

  /// Packs the vault database, key material, and `.enc` files into an
  /// authenticated AES-256-GCM `.docsift` container on a background isolate.
  static Future<Uint8List> seal({
    required String passphrase,
    required Uint8List vek,
    required String dbKey,
    required Uint8List dbBytes,
    required Map<String, Uint8List> encryptedFiles,
    int iterations = defaultIterations,
    DateTime? createdAt,
  }) async {
    if (passphrase.isEmpty) {
      throw const BackupAuthException('Backup passphrase cannot be empty.');
    }
    if (vek.length != 32) {
      throw const BackupAuthException('Invalid 256-bit VEK length.');
    }
    if (iterations < _minIterations || iterations > _maxIterations) {
      throw const BackupAuthException('Invalid PBKDF2 iteration count.');
    }

    final vekCopy = Uint8List.fromList(vek);
    final dbCopy = TransferableTypedData.fromList([dbBytes]);
    final filesTransfer = <String, TransferableTypedData>{
      for (final entry in encryptedFiles.entries)
        p.basename(entry.key): TransferableTypedData.fromList([entry.value]),
    };
    final timestampIso = (createdAt ?? DateTime.now().toUtc()).toIso8601String();

    final sealedTransfer = await Isolate.run(
      () => _sealIsolate(
        passphrase: passphrase,
        vek: vekCopy,
        dbKey: dbKey,
        dbTransfer: dbCopy,
        filesTransfer: filesTransfer,
        iterations: iterations,
        timestampIso: timestampIso,
      ),
    );
    return sealedTransfer.materialize().asUint8List();
  }

  /// Verifies and decrypts a `.docsift` archive on a background isolate.
  /// Throws [BackupAuthException] if the passphrase is wrong or any byte was tampered with.
  static Future<RestoredBackupPayload> open({
    required Uint8List archiveBytes,
    required String passphrase,
  }) async {
    if (archiveBytes.length < _minArchiveLen) {
      throw const BackupAuthException(
        'Invalid or truncated .docsift backup file.',
      );
    }
    for (int i = 0; i < _magic.length; i++) {
      if (archiveBytes[i] != _magic[i]) {
        throw const BackupAuthException(
          'Unrecognized file format (expected .docsift backup archive).',
        );
      }
    }

    final transfer = TransferableTypedData.fromList([archiveBytes]);
    final decoded = await Isolate.run(
      () => _openIsolate(transfer, passphrase),
    );

    return RestoredBackupPayload(
      createdAt: DateTime.tryParse(decoded.createdAtIso) ?? DateTime.now(),
      vek: decoded.vekTransfer.materialize().asUint8List(),
      dbKey: decoded.dbKey,
      dbBytes: decoded.dbTransfer.materialize().asUint8List(),
      encryptedFiles: {
        for (final entry in decoded.filesTransfer.entries)
          entry.key: entry.value.materialize().asUint8List(),
      },
    );
  }

  static TransferableTypedData _sealIsolate({
    required String passphrase,
    required Uint8List vek,
    required String dbKey,
    required TransferableTypedData dbTransfer,
    required Map<String, TransferableTypedData> filesTransfer,
    required int iterations,
    required String timestampIso,
  }) {
    final dbBytes = dbTransfer.materialize().asUint8List();
    final materializedFiles = <MapEntry<Uint8List, Uint8List>>[];
    for (final entry in filesTransfer.entries) {
      final safeName = p.basename(entry.key);
      if (safeName.isEmpty || safeName == '.' || safeName == '..') continue;
      materializedFiles.add(
        MapEntry(
          Uint8List.fromList(utf8.encode(safeName)),
          entry.value.materialize().asUint8List(),
        ),
      );
    }

    final manifestBytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode(<String, Object>{
          'format': 'docsift-backup-v1',
          'createdAt': timestampIso,
          'vekB64': base64Encode(vek),
          'dbKey': dbKey,
          'fileCount': materializedFiles.length,
        }),
      ),
    );

    // Compute exact inner bundle byte length to allocate a single contiguous buffer
    int innerLen = 4 + manifestBytes.length + 4 + dbBytes.length + 4;
    for (final entry in materializedFiles) {
      innerLen += 2 + entry.key.length + 4 + entry.value.length;
    }

    final inner = Uint8List(innerLen);
    final bd = ByteData.sublistView(inner);
    int offset = 0;

    bd.setUint32(offset, manifestBytes.length, Endian.little);
    offset += 4;
    inner.setRange(offset, offset + manifestBytes.length, manifestBytes);
    offset += manifestBytes.length;

    bd.setUint32(offset, dbBytes.length, Endian.little);
    offset += 4;
    inner.setRange(offset, offset + dbBytes.length, dbBytes);
    offset += dbBytes.length;

    bd.setUint32(offset, materializedFiles.length, Endian.little);
    offset += 4;
    for (final entry in materializedFiles) {
      bd.setUint16(offset, entry.key.length, Endian.little);
      offset += 2;
      inner.setRange(offset, offset + entry.key.length, entry.key);
      offset += entry.key.length;

      bd.setUint32(offset, entry.value.length, Endian.little);
      offset += 4;
      inner.setRange(offset, offset + entry.value.length, entry.value);
      offset += entry.value.length;
    }

    final rng = Random.secure();
    final salt =
        Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    final iv =
        Uint8List.fromList(List<int>.generate(_ivLen, (_) => rng.nextInt(256)));

    final aad = Uint8List(_headerAadLen);
    aad.setRange(0, 5, _magic);
    ByteData.sublistView(aad).setUint32(5, iterations, Endian.little);
    aad.setRange(9, 41, salt);

    final key = _deriveBackupKey(passphrase, salt, iterations);
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(KeyParameter(key), 128, iv, aad),
        );
      final ctAndTag = cipher.process(inner);

      final archive = Uint8List(_headerAadLen + _ivLen + ctAndTag.length);
      archive.setRange(0, _headerAadLen, aad);
      archive.setRange(_headerAadLen, _headerAadLen + _ivLen, iv);
      archive.setRange(_headerAadLen + _ivLen, archive.length, ctAndTag);

      return TransferableTypedData.fromList([archive]);
    } finally {
      _wipe(key);
      _wipe(vek);
      _wipe(manifestBytes);
      _wipe(inner);
    }
  }

  static _IsolateDecodedBackup _openIsolate(
    TransferableTypedData archiveTransfer,
    String passphrase,
  ) {
    final archive = archiveTransfer.materialize().asUint8List();
    final headerBd = ByteData.sublistView(archive, 0, _headerAadLen);
    final iterations = headerBd.getUint32(5, Endian.little);
    if (iterations < _minIterations || iterations > _maxIterations) {
      throw const BackupAuthException(
        'Corrupted backup header (invalid KDF parameters).',
      );
    }

    final aad = Uint8List.sublistView(archive, 0, _headerAadLen);
    final salt = Uint8List.sublistView(archive, 9, 41);
    final iv =
        Uint8List.sublistView(archive, _headerAadLen, _headerAadLen + _ivLen);
    final ctAndTag =
        Uint8List.sublistView(archive, _headerAadLen + _ivLen);

    final key = _deriveBackupKey(passphrase, salt, iterations);
    Uint8List? inner;
    try {
      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(KeyParameter(key), 128, iv, aad),
        );
      inner = cipher.process(ctAndTag);
    } on InvalidCipherTextException {
      throw const BackupAuthException(
        'Incorrect backup passphrase or tampered backup file.',
      );
    } catch (_) {
      throw const BackupAuthException(
        'Failed to decrypt backup archive.',
      );
    } finally {
      _wipe(key);
    }

    try {
      final bd = ByteData.sublistView(inner);
      int offset = 0;

      if (offset + 4 > inner.length) {
        throw const BackupAuthException('Truncated backup manifest.');
      }
      final manifestLen = bd.getUint32(offset, Endian.little);
      offset += 4;
      if (offset + manifestLen > inner.length) {
        throw const BackupAuthException('Corrupted backup manifest.');
      }
      final manifestJson = utf8.decode(
        Uint8List.sublistView(inner, offset, offset + manifestLen),
      );
      offset += manifestLen;

      final manifest = jsonDecode(manifestJson) as Map<String, dynamic>;
      if (manifest['format'] != 'docsift-backup-v1') {
        throw const BackupAuthException('Unsupported backup format version.');
      }
      final vekB64 = manifest['vekB64'] as String? ?? '';
      final vek = Uint8List.fromList(base64Decode(vekB64));
      if (vek.length != 32) {
        throw const BackupAuthException('Corrupted backup encryption key.');
      }
      final dbKey = manifest['dbKey'] as String? ?? '';
      if (dbKey.isEmpty) {
        throw const BackupAuthException('Missing database key in backup.');
      }
      final createdAtIso = manifest['createdAt'] as String? ?? '';

      if (offset + 4 > inner.length) {
        throw const BackupAuthException('Truncated database section.');
      }
      final dbLen = bd.getUint32(offset, Endian.little);
      offset += 4;
      if (offset + dbLen > inner.length) {
        throw const BackupAuthException('Corrupted database payload.');
      }
      final dbBytes = Uint8List.fromList(
        Uint8List.sublistView(inner, offset, offset + dbLen),
      );
      offset += dbLen;

      if (offset + 4 > inner.length) {
        throw const BackupAuthException('Truncated vault file table.');
      }
      final fileCount = bd.getUint32(offset, Endian.little);
      offset += 4;

      final filesTransfer = <String, TransferableTypedData>{};
      for (int i = 0; i < fileCount; i++) {
        if (offset + 2 > inner.length) {
          throw const BackupAuthException('Truncated file entry name.');
        }
        final nameLen = bd.getUint16(offset, Endian.little);
        offset += 2;
        if (offset + nameLen + 4 > inner.length) {
          throw const BackupAuthException('Corrupted file entry header.');
        }
        final rawName = utf8.decode(
          Uint8List.sublistView(inner, offset, offset + nameLen),
        );
        offset += nameLen;

        final dataLen = bd.getUint32(offset, Endian.little);
        offset += 4;
        if (offset + dataLen > inner.length) {
          throw const BackupAuthException('Truncated encrypted vault file.');
        }
        final safeName = p.basename(rawName);
        if (safeName.isNotEmpty && safeName != '.' && safeName != '..') {
          final fileBytes = Uint8List.fromList(
            Uint8List.sublistView(inner, offset, offset + dataLen),
          );
          filesTransfer[safeName] =
              TransferableTypedData.fromList([fileBytes]);
        }
        offset += dataLen;
      }

      return _IsolateDecodedBackup(
        createdAtIso: createdAtIso,
        vekTransfer: TransferableTypedData.fromList([vek]),
        dbKey: dbKey,
        dbTransfer: TransferableTypedData.fromList([dbBytes]),
        filesTransfer: filesTransfer,
      );
    } finally {
      _wipe(inner);
    }
  }

  static Uint8List _deriveBackupKey(
    String passphrase,
    Uint8List salt,
    int iterations,
  ) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(salt, iterations, 32));
    final passBytes = Uint8List.fromList(utf8.encode(passphrase));
    try {
      return derivator.process(passBytes);
    } finally {
      _wipe(passBytes);
    }
  }

  static void _wipe(Uint8List bytes) {
    for (int i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }
}

class _IsolateDecodedBackup {
  const _IsolateDecodedBackup({
    required this.createdAtIso,
    required this.vekTransfer,
    required this.dbKey,
    required this.dbTransfer,
    required this.filesTransfer,
  });

  final String createdAtIso;
  final TransferableTypedData vekTransfer;
  final String dbKey;
  final TransferableTypedData dbTransfer;
  final Map<String, TransferableTypedData> filesTransfer;
}

