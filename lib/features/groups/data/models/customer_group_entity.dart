class CustomerGroup {
  const CustomerGroup({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? description;
  final String createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'created_at': createdAt,
      };

  factory CustomerGroup.fromMap(Map<String, Object?> map) => CustomerGroup(
        id: map['id']! as String,
        name: map['name']! as String,
        description: map['description'] as String?,
        createdAt: map['created_at']! as String,
      );

  CustomerGroup copyWith({String? name, String? description, bool clearDescription = false}) => CustomerGroup(
        id: id,
        name: name ?? this.name,
        description: clearDescription ? null : (description ?? this.description),
        createdAt: createdAt,
      );
}
