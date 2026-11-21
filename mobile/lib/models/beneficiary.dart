class Beneficiary {
  const Beneficiary({required this.id, required this.label});

  final String id;
  final String label;

  factory Beneficiary.fromJson(Map<String, dynamic> json) {
    return Beneficiary(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'label': label};
}

class AshaProfile {
  const AshaProfile({required this.id, required this.name, required this.area});

  final String id;
  final String name;
  final String area;

  static const List<AshaProfile> defaults = [
    AshaProfile(id: 'asha_001', name: 'Sunita Devi', area: 'Sub-center A (Synthetic)'),
    AshaProfile(id: 'asha_002', name: 'Meena Kumari', area: 'Sub-center B (Synthetic)'),
  ];

  static AshaProfile byId(String? id) {
    return defaults.firstWhere(
      (profile) => profile.id == id,
      orElse: () => defaults.first,
    );
  }
}
