import 'package:equatable/equatable.dart';

enum FileType { pdf, docx, txt, md, image, video, zip, json, other }

class VaultItem extends Equatable {
  const VaultItem({
    required this.id,
    required this.name,
    required this.originalExtension,
    required this.encryptedFilePath,
    required this.fileType,
    required this.createdAt,
    required this.modifiedAt,
    this.categoryId,
    this.fileSizeBytes,
    this.mimeType,
    this.thumbnailPath,
    this.isStarred = false,
    this.extractionStatus = ExtractionStatus.pending,
    this.tags = const [],
  });

  final String id;
  final String name;
  final String originalExtension;
  final String? categoryId;
  final String encryptedFilePath;
  final int? fileSizeBytes;
  final String? mimeType;
  final String? thumbnailPath;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final bool isStarred;
  final FileType fileType;
  final ExtractionStatus extractionStatus;
  final List<String> tags;

  String get displayName => name;
  String get sizeLabel {
    if (fileSizeBytes == null) return '—';
    final bytes = fileSizeBytes!;
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  VaultItem copyWith({
    String? id,
    String? name,
    String? originalExtension,
    String? categoryId,
    String? encryptedFilePath,
    int? fileSizeBytes,
    String? mimeType,
    String? thumbnailPath,
    DateTime? createdAt,
    DateTime? modifiedAt,
    bool? isStarred,
    FileType? fileType,
    ExtractionStatus? extractionStatus,
    List<String>? tags,
  }) {
    return VaultItem(
      id: id ?? this.id,
      name: name ?? this.name,
      originalExtension: originalExtension ?? this.originalExtension,
      categoryId: categoryId ?? this.categoryId,
      encryptedFilePath: encryptedFilePath ?? this.encryptedFilePath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      mimeType: mimeType ?? this.mimeType,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      isStarred: isStarred ?? this.isStarred,
      fileType: fileType ?? this.fileType,
      extractionStatus: extractionStatus ?? this.extractionStatus,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'original_extension': originalExtension,
        'category_id': categoryId,
        'encrypted_file_path': encryptedFilePath,
        'file_size_bytes': fileSizeBytes,
        'mime_type': mimeType,
        'thumbnail_path': thumbnailPath,
        'created_at': createdAt.millisecondsSinceEpoch,
        'modified_at': modifiedAt.millisecondsSinceEpoch,
        'is_starred': isStarred ? 1 : 0,
        'file_type': fileType.name,
        'extraction_status': extractionStatus.name,
        'tags': tags.join(','),
      };

  factory VaultItem.fromMap(Map<String, dynamic> map) => VaultItem(
        id: map['id'] as String,
        name: map['name'] as String,
        originalExtension: map['original_extension'] as String,
        categoryId: map['category_id'] as String?,
        encryptedFilePath: map['encrypted_file_path'] as String,
        fileSizeBytes: map['file_size_bytes'] as int?,
        mimeType: map['mime_type'] as String?,
        thumbnailPath: map['thumbnail_path'] as String?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(map['modified_at'] as int),
        isStarred: (map['is_starred'] as int?) == 1,
        fileType: FileType.values.byName(
            (map['file_type'] as String?) ?? FileType.other.name),
        extractionStatus: ExtractionStatus.values.byName(
            (map['extraction_status'] as String?) ?? ExtractionStatus.pending.name),
        tags: ((map['tags'] as String?) ?? '').isEmpty
            ? []
            : (map['tags'] as String).split(','),
      );

  @override
  List<Object?> get props => [id, name, encryptedFilePath, modifiedAt];
}

enum ExtractionStatus { pending, processing, done, failed }

class VaultCategory extends Equatable {
  const VaultCategory({
    required this.id,
    required this.name,
    required this.createdAt,
    this.iconCodepoint,
    this.colorValue,
    this.itemCount = 0,
  });

  final String id;
  final String name;
  final int? iconCodepoint;
  final int? colorValue;
  final DateTime createdAt;
  final int itemCount;

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'icon_codepoint': iconCodepoint,
        'color_value': colorValue,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  factory VaultCategory.fromMap(Map<String, dynamic> map) => VaultCategory(
        id: map['id'] as String,
        name: map['name'] as String,
        iconCodepoint: map['icon_codepoint'] as int?,
        colorValue: map['color_value'] as int?,
        createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
        itemCount: (map['item_count'] as int?) ?? 0,
      );

  @override
  List<Object?> get props => [id, name];
}

// Helper to resolve FileType from extension
FileType fileTypeFromExtension(String ext) {
  switch (ext.toLowerCase()) {
    case 'pdf':
      return FileType.pdf;
    case 'docx':
    case 'doc':
      return FileType.docx;
    case 'txt':
      return FileType.txt;
    case 'json':
      return FileType.json;
    case 'md':
      return FileType.md;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'webp':
    case 'gif':
      return FileType.image;
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
      return FileType.video;
    case 'zip':
    case 'rar':
    case '7z':
    case 'tar':
      return FileType.zip;
    default:
      return FileType.other;
  }
}
