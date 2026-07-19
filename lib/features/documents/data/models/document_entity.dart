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

  factory CustomerDocument.fromMap(Map<String, Object?> map) =>
      CustomerDocument(
        id: map['id']! as String,
        customerId: map['customer_id']! as String,
        loanId: map['loan_id'] as String?,
        type: CustomerDocumentTypeLabel.fromValue(map['doc_type'] as String?),
        encryptedPath: map['file_path']! as String,
        originalName: map['original_name'] as String? ?? 'Document',
        mimeType: map['mime_type'] as String? ?? 'application/octet-stream',
        uploadedAt: DateTime.parse(map['uploaded_at']! as String),
      );
}
