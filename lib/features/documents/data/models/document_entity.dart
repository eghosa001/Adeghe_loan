enum CustomerDocumentType {
  passport,
  ninSlip,
  driversLicense,
  internationalPassport,
  pvc,
  utilityBill,
  signedAgreement,
  guarantorDocument,
  other,
}

extension CustomerDocumentTypeLabel on CustomerDocumentType {
  String get label => switch (this) {
        CustomerDocumentType.passport => 'Passport photograph',
        CustomerDocumentType.ninSlip => 'NIN slip',
        CustomerDocumentType.driversLicense => "Driver's license",
        CustomerDocumentType.internationalPassport => 'International passport',
        CustomerDocumentType.pvc => 'PVC',
        CustomerDocumentType.utilityBill => 'Utility bill',
        CustomerDocumentType.signedAgreement => 'Signed agreement',
        CustomerDocumentType.guarantorDocument => 'Guarantor document',
        CustomerDocumentType.other => 'Other document',
      };

  static CustomerDocumentType fromValue(String? value) {
    return CustomerDocumentType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => CustomerDocumentType.other,
    );
  }

  static CustomerDocumentType strictFromValue(String? value) {
    for (final type in CustomerDocumentType.values) {
      if (type.name == value) return type;
    }
    throw FormatException('Unknown document type: $value');
  }
}

class CustomerDocument {
  const CustomerDocument({
    required this.id,
    required this.customerId,
    required this.type,
    required this.encryptedPath,
    required this.originalName,
    required this.mimeType,
    required this.uploadedAt,
    this.loanId,
  });

  final String id;
  final String customerId;
  final String? loanId;
  final CustomerDocumentType type;
  final String encryptedPath;
  final String originalName;
  final String mimeType;
  final DateTime uploadedAt;

  bool get isPdf => mimeType == 'application/pdf';
  bool get isImage => mimeType.startsWith('image/');

  Map<String, Object?> toMap() => {
        'id': id,
        'customer_id': customerId,
        'loan_id': loanId,
        'doc_type': type.name,
        'file_path': encryptedPath,
        'original_name': originalName,
        'mime_type': mimeType,
        'uploaded_at': uploadedAt.toIso8601String(),
      };

  factory CustomerDocument.fromMap(Map<String, Object?> map) {
    String requiredString(String key) {
      final value = map[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('Invalid document field: $key');
      }
      return value;
    }

    final uploadedRaw = requiredString('uploaded_at');
    final uploadedAt = DateTime.tryParse(uploadedRaw);
    if (uploadedAt == null) {
      throw FormatException('Invalid document date: $uploadedRaw');
    }

    final mimeType = requiredString('mime_type');
    const supportedMimeTypes = {
      'application/pdf',
      'image/png',
      'image/jpeg',
    };
    if (!supportedMimeTypes.contains(mimeType)) {
      throw FormatException('Unsupported document MIME type: $mimeType');
    }

    return CustomerDocument(
      id: requiredString('id'),
      customerId: requiredString('customer_id'),
      loanId: (map['loan_id'] as String?)?.trim().isEmpty == true
          ? null
          : map['loan_id'] as String?,
      type: CustomerDocumentTypeLabel.strictFromValue(map['doc_type'] as String?),
      encryptedPath: requiredString('file_path'),
      originalName: requiredString('original_name'),
      mimeType: mimeType,
      uploadedAt: uploadedAt,
    );
  }
}
