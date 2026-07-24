final class ScannedPage {
  const ScannedPage({
    required this.id,
    required this.fileName,
    required this.width,
    required this.height,
    required this.createdAt,
    this.rotationQuarterTurns = 0,
    this.filter = 'original',
    this.ocrText = '',
    this.ocrLanguage,
    this.ocrUpdatedAt,
  });

  final String id;
  final String fileName;
  final int width;
  final int height;
  final DateTime createdAt;
  final int rotationQuarterTurns;
  final String filter;
  final String ocrText;
  final String? ocrLanguage;
  final DateTime? ocrUpdatedAt;

  ScannedPage copyWith({
    int? rotationQuarterTurns,
    String? filter,
    String? ocrText,
    Object? ocrLanguage = _unset,
    Object? ocrUpdatedAt = _unset,
  }) => ScannedPage(
    id: id,
    fileName: fileName,
    width: width,
    height: height,
    createdAt: createdAt,
    rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
    filter: filter ?? this.filter,
    ocrText: ocrText ?? this.ocrText,
    ocrLanguage: identical(ocrLanguage, _unset)
        ? this.ocrLanguage
        : ocrLanguage as String?,
    ocrUpdatedAt: identical(ocrUpdatedAt, _unset)
        ? this.ocrUpdatedAt
        : ocrUpdatedAt as DateTime?,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'fileName': fileName,
    'width': width,
    'height': height,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'rotationQuarterTurns': rotationQuarterTurns,
    'filter': filter,
    'ocrText': ocrText,
    'ocrLanguage': ocrLanguage,
    'ocrUpdatedAt': ocrUpdatedAt?.toUtc().toIso8601String(),
  };

  factory ScannedPage.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Scanned page must be an object');
    }
    final String? id = value['id'] as String?;
    final String? fileName = value['fileName'] as String?;
    final num? width = value['width'] as num?;
    final num? height = value['height'] as num?;
    final DateTime? createdAt = DateTime.tryParse(
      value['createdAt'] as String? ?? '',
    );
    final int rotation = (value['rotationQuarterTurns'] as num?)?.toInt() ?? 0;
    if (id == null ||
        id.isEmpty ||
        fileName == null ||
        fileName.isEmpty ||
        width == null ||
        width <= 0 ||
        height == null ||
        height <= 0 ||
        createdAt == null ||
        rotation < 0 ||
        rotation > 3) {
      throw const FormatException('Scanned page metadata is invalid');
    }
    return ScannedPage(
      id: id,
      fileName: fileName,
      width: width.toInt(),
      height: height.toInt(),
      createdAt: createdAt,
      rotationQuarterTurns: rotation,
      filter: value['filter'] as String? ?? 'original',
      ocrText: value['ocrText'] as String? ?? '',
      ocrLanguage: value['ocrLanguage'] as String?,
      ocrUpdatedAt: DateTime.tryParse(value['ocrUpdatedAt'] as String? ?? ''),
    );
  }
}

final class ScannedDocument {
  ScannedDocument({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required List<ScannedPage> pages,
    List<String> folderIds = const <String>[],
    this.favorite = false,
    this.trashedAt,
    List<String> tags = const <String>[],
  }) : pages = List<ScannedPage>.unmodifiable(pages),
       folderIds = List<String>.unmodifiable(folderIds),
       tags = List<String>.unmodifiable(tags);

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ScannedPage> pages;
  final List<String> folderIds;
  final bool favorite;
  final DateTime? trashedAt;
  final List<String> tags;

  bool get isTrashed => trashedAt != null;

  String get searchableText => <String>[
    name,
    ...tags,
    ...pages.map((ScannedPage page) => page.ocrText),
  ].join('\n').toLowerCase();

  ScannedDocument copyWith({
    String? name,
    DateTime? updatedAt,
    List<ScannedPage>? pages,
    List<String>? folderIds,
    bool? favorite,
    Object? trashedAt = _unset,
    List<String>? tags,
  }) => ScannedDocument(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pages: pages ?? this.pages,
    folderIds: folderIds ?? this.folderIds,
    favorite: favorite ?? this.favorite,
    trashedAt: identical(trashedAt, _unset)
        ? this.trashedAt
        : trashedAt as DateTime?,
    tags: tags ?? this.tags,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': 2,
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'pages': pages.map((ScannedPage page) => page.toJson()).toList(),
    'folderIds': folderIds,
    'favorite': favorite,
    'trashedAt': trashedAt?.toUtc().toIso8601String(),
    'tags': tags,
  };

  factory ScannedDocument.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Scanned document must be an object');
    }
    final String? id = value['id'] as String?;
    final String? name = value['name'] as String?;
    final DateTime? createdAt = DateTime.tryParse(
      value['createdAt'] as String? ?? '',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      value['updatedAt'] as String? ?? '',
    );
    final Object? rawPages = value['pages'];
    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.trim().isEmpty ||
        createdAt == null ||
        updatedAt == null ||
        rawPages is! List) {
      throw const FormatException('Scanned document metadata is invalid');
    }
    return ScannedDocument(
      id: id,
      name: name.trim(),
      createdAt: createdAt,
      updatedAt: updatedAt,
      pages: rawPages.map(ScannedPage.fromJson).toList(growable: false),
      folderIds: _stringList(value['folderIds']),
      favorite: value['favorite'] as bool? ?? false,
      trashedAt: DateTime.tryParse(value['trashedAt'] as String? ?? ''),
      tags: _stringList(value['tags']),
    );
  }
}

const Object _unset = Object();

List<String> _stringList(Object? value) {
  if (value is! List) return const <String>[];
  return value
      .whereType<String>()
      .map((String item) => item.trim())
      .where((String item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);
}
