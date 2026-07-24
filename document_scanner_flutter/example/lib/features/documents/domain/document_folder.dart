final class DocumentFolder {
  const DocumentFolder({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int colorValue;
  final DateTime createdAt;
  final DateTime updatedAt;

  DocumentFolder copyWith({
    String? name,
    int? colorValue,
    DateTime? updatedAt,
  }) => DocumentFolder(
    id: id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object> toJson() => <String, Object>{
    'id': id,
    'name': name,
    'colorValue': colorValue,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  factory DocumentFolder.fromJson(Object? value) {
    if (value is! Map) {
      throw const FormatException('Document folder must be an object');
    }
    final String? id = value['id'] as String?;
    final String? name = value['name'] as String?;
    final int? colorValue = (value['colorValue'] as num?)?.toInt();
    final DateTime? createdAt = DateTime.tryParse(
      value['createdAt'] as String? ?? '',
    );
    final DateTime? updatedAt = DateTime.tryParse(
      value['updatedAt'] as String? ?? '',
    );
    if (id == null ||
        id.isEmpty ||
        name == null ||
        name.trim().isEmpty ||
        colorValue == null ||
        createdAt == null ||
        updatedAt == null) {
      throw const FormatException('Document folder metadata is invalid');
    }
    return DocumentFolder(
      id: id,
      name: name.trim(),
      colorValue: colorValue,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
