final class ScannedPage {
  const ScannedPage({
    required this.id,
    required this.fileName,
    required this.width,
    required this.height,
    required this.createdAt,
    this.rotationQuarterTurns = 0,
    this.filter = 'original',
  });

  final String id;
  final String fileName;
  final int width;
  final int height;
  final DateTime createdAt;
  final int rotationQuarterTurns;
  final String filter;

  ScannedPage copyWith({int? rotationQuarterTurns, String? filter}) =>
      ScannedPage(
        id: id,
        fileName: fileName,
        width: width,
        height: height,
        createdAt: createdAt,
        rotationQuarterTurns: rotationQuarterTurns ?? this.rotationQuarterTurns,
        filter: filter ?? this.filter,
      );

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'fileName': fileName,
    'width': width,
    'height': height,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'rotationQuarterTurns': rotationQuarterTurns,
    'filter': filter,
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
  }) : pages = List<ScannedPage>.unmodifiable(pages);

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ScannedPage> pages;

  ScannedDocument copyWith({
    String? name,
    DateTime? updatedAt,
    List<ScannedPage>? pages,
  }) => ScannedDocument(
    id: id,
    name: name ?? this.name,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pages: pages ?? this.pages,
  );

  Map<String, Object> toJson() => <String, Object>{
    'schemaVersion': 1,
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'pages': pages.map((ScannedPage page) => page.toJson()).toList(),
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
    );
  }
}
