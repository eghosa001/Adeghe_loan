enum CustomerStatus { active, closed, blacklisted, archived }

extension CustomerStatusValue on CustomerStatus {
  String get value => name;

  static CustomerStatus fromValue(String? value) {
    return CustomerStatus.values.firstWhere(
      (status) => status.value == value,
      orElse: () => CustomerStatus.active,
    );
  }
}

class Customer {
  const Customer({
    required this.id,
    required this.fullName,
    required this.phone,
    required this.dateRegistered,
    this.passportPath,
    this.gender,
    this.dateOfBirth,
    this.altPhone,
    this.email,
    this.residentialAddress,
    this.businessAddress,
    this.occupation,
    this.employer,
    this.maritalStatus,
    this.nationality,
    this.state,
    this.lga,
    this.nextOfKin,
    this.nextOfKinRelation,
    this.nextOfKinPhone,
    this.guarantor1Name,
    this.guarantor2Name,
    this.guarantorPhone,
    this.guarantorAddress,
    this.guarantorPassportPath,
    this.nin,
    this.bvn,
    this.idType,
    this.idNumber,
    this.signaturePath,
    this.notes,
    this.status = CustomerStatus.active,
    this.creditScore = 0,
    this.groupId,
  });

  final String id;
  final String? passportPath;
  final String fullName;
  final String? gender;
  final String? dateOfBirth;
  final String phone;
  final String? altPhone;
  final String? email;
  final String? residentialAddress;
  final String? businessAddress;
  final String? occupation;
  final String? employer;
  final String? maritalStatus;
  final String? nationality;
  final String? state;
  final String? lga;
  final String? nextOfKin;
  final String? nextOfKinRelation;
  final String? nextOfKinPhone;
  final String? guarantor1Name;
  final String? guarantor2Name;
  final String? guarantorPhone;
  final String? guarantorAddress;
  final String? guarantorPassportPath;
  final String? nin;
  final String? bvn;
  final String? idType;
  final String? idNumber;
  final String? signaturePath;
  final String dateRegistered;
  final String? notes;
  final CustomerStatus status;
  final double creditScore;
  final String? groupId;

  Customer copyWith({
    String? passportPath,
    String? fullName,
    String? phone,
    CustomerStatus? status,
    String? groupId,
    bool clearGroupId = false,
  }) =>
      Customer(
        id: id,
        passportPath: passportPath ?? this.passportPath,
        fullName: fullName ?? this.fullName,
        gender: gender,
        dateOfBirth: dateOfBirth,
        phone: phone ?? this.phone,
        altPhone: altPhone,
        email: email,
        residentialAddress: residentialAddress,
        businessAddress: businessAddress,
        occupation: occupation,
        employer: employer,
        maritalStatus: maritalStatus,
        nationality: nationality,
        state: state,
        lga: lga,
        nextOfKin: nextOfKin,
        nextOfKinRelation: nextOfKinRelation,
        nextOfKinPhone: nextOfKinPhone,
        guarantor1Name: guarantor1Name,
        guarantor2Name: guarantor2Name,
        guarantorPhone: guarantorPhone,
        guarantorAddress: guarantorAddress,
        guarantorPassportPath: guarantorPassportPath,
        nin: nin,
        bvn: bvn,
        idType: idType,
        idNumber: idNumber,
        signaturePath: signaturePath,
        dateRegistered: dateRegistered,
        notes: notes,
        status: status ?? this.status,
        creditScore: creditScore,
        groupId: clearGroupId ? null : (groupId ?? this.groupId),
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'passport_path': passportPath,
        'full_name': fullName,
        'gender': gender,
        'dob': dateOfBirth,
        'phone': phone,
        'alt_phone': altPhone,
        'email': email,
        'residential_address': residentialAddress,
        'business_address': businessAddress,
        'occupation': occupation,
        'employer': employer,
        'marital_status': maritalStatus,
        'nationality': nationality,
        'state': state,
        'lga': lga,
        'next_of_kin': nextOfKin,
        'next_of_kin_relation': nextOfKinRelation,
        'next_of_kin_phone': nextOfKinPhone,
        'guarantor_1_name': guarantor1Name,
        'guarantor_2_name': guarantor2Name,
        'guarantor_phone': guarantorPhone,
        'guarantor_address': guarantorAddress,
        'guarantor_passport_path': guarantorPassportPath,
        'nin': nin,
        'bvn': bvn,
        'id_type': idType,
        'id_number': idNumber,
        'signature_path': signaturePath,
        'date_registered': dateRegistered,
        'notes': notes,
        'status': status.value,
        'credit_score': creditScore,
        'group_id': groupId,
      };

  factory Customer.fromMap(Map<String, Object?> map) => Customer(
        id: map['id']! as String,
        passportPath: map['passport_path'] as String?,
        fullName: map['full_name']! as String,
        gender: map['gender'] as String?,
        dateOfBirth: map['dob'] as String?,
        phone: map['phone']! as String,
        altPhone: map['alt_phone'] as String?,
        email: map['email'] as String?,
        residentialAddress: map['residential_address'] as String?,
        businessAddress: map['business_address'] as String?,
        occupation: map['occupation'] as String?,
        employer: map['employer'] as String?,
        maritalStatus: map['marital_status'] as String?,
        nationality: map['nationality'] as String?,
        state: map['state'] as String?,
        lga: map['lga'] as String?,
        nextOfKin: map['next_of_kin'] as String?,
        nextOfKinRelation: map['next_of_kin_relation'] as String?,
        nextOfKinPhone: map['next_of_kin_phone'] as String?,
        guarantor1Name: map['guarantor_1_name'] as String?,
        guarantor2Name: map['guarantor_2_name'] as String?,
        guarantorPhone: map['guarantor_phone'] as String?,
        guarantorAddress: map['guarantor_address'] as String?,
        guarantorPassportPath: map['guarantor_passport_path'] as String?,
        nin: map['nin'] as String?,
        bvn: map['bvn'] as String?,
        idType: map['id_type'] as String?,
        idNumber: map['id_number'] as String?,
        signaturePath: map['signature_path'] as String?,
        dateRegistered: map['date_registered']! as String,
        notes: map['notes'] as String?,
        status: CustomerStatusValue.fromValue(map['status'] as String?),
        creditScore: (map['credit_score'] as num?)?.toDouble() ?? 0,
        groupId: map['group_id'] as String?,
      );
}
