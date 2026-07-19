class BusinessProfile {
  final String id;
  final String name;
  final String? logoPath;
  final String ownerName;
  final String address;
  final String phone;
  final String email;
  final String regNo;

  BusinessProfile({
    required this.id,
    required this.name,
    this.logoPath,
    required this.ownerName,
    required this.address,
    required this.phone,
    required this.email,
    required this.regNo,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'logo_path': logoPath,
      'owner_name': ownerName,
      'address': address,
      'phone': phone,
      'email': email,
      'reg_no': regNo,
    };
  }

  factory BusinessProfile.fromMap(Map<String, dynamic> map) {
    return BusinessProfile(
      id: map['id'] as String,
      name: map['name'] as String,
      logoPath: map['logo_path'] as String?,
      ownerName: map['owner_name'] as String? ?? '',
      address: map['address'] as String? ?? '',
      phone: map['phone'] as String? ?? '',
      email: map['email'] as String? ?? '',
      regNo: map['reg_no'] as String? ?? '',
    );
  }
}
