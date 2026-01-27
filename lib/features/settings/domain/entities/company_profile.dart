import 'dart:convert';

class CompanyProfile {
  final String name;
  final String? address;
  final String? phone;
  final String? email;
  final String? taxNumber;
  final String? website;
  final String? logoBase64;

  const CompanyProfile({
    required this.name,
    this.address,
    this.phone,
    this.email,
    this.taxNumber,
    this.website,
    this.logoBase64,
  });

  CompanyProfile copyWith({
    String? name,
    String? address,
    String? phone,
    String? email,
    String? taxNumber,
    String? website,
    String? logoBase64,
  }) {
    return CompanyProfile(
      name: name ?? this.name,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      taxNumber: taxNumber ?? this.taxNumber,
      website: website ?? this.website,
      logoBase64: logoBase64 ?? this.logoBase64,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'phone': phone,
      'email': email,
      'taxNumber': taxNumber,
      'website': website,
      'logoBase64': logoBase64,
    };
  }

  String toJson() => jsonEncode(toMap());

  static CompanyProfile empty() => const CompanyProfile(name: '');

  static CompanyProfile fromMap(Map<String, dynamic> map) {
    return CompanyProfile(
      name: (map['name'] as String?) ?? '',
      address: map['address'] as String?,
      phone: map['phone'] as String?,
      email: map['email'] as String?,
      taxNumber: map['taxNumber'] as String?,
      website: map['website'] as String?,
      logoBase64: map['logoBase64'] as String?,
    );
  }

  static CompanyProfile? tryFromJson(String? json) {
    if (json == null || json.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) {
        return CompanyProfile.fromMap(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
