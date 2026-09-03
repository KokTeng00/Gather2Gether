class PlaceSuggestion {
  const PlaceSuggestion({
    required this.id,
    required this.formattedAddress,
    required this.latitude,
    required this.longitude,
    this.name,
    this.addressLine1,
    this.addressLine2,
    this.countryCode,
    this.resultType,
    this.timezone,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    final latitude = _requiredDouble(json['latitude'], 'latitude');
    final longitude = _requiredDouble(json['longitude'], 'longitude');
    if (latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw const FormatException('Place coordinates are invalid.');
    }
    return PlaceSuggestion(
      id: _requiredString(json['id'], 'id'),
      name: _optionalString(json['name']),
      formattedAddress: _requiredString(
        json['formatted_address'],
        'formatted_address',
      ),
      addressLine1: _optionalString(json['address_line1']),
      addressLine2: _optionalString(json['address_line2']),
      countryCode: _optionalString(json['country_code']),
      latitude: latitude,
      longitude: longitude,
      resultType: _optionalString(json['result_type']),
      timezone: _optionalString(json['timezone']),
    );
  }

  final String id;
  final String? name;
  final String formattedAddress;
  final String? addressLine1;
  final String? addressLine2;
  final String? countryCode;
  final double latitude;
  final double longitude;
  final String? resultType;
  final String? timezone;

  String get displayTitle => addressLine1 ?? name ?? formattedAddress;

  String? get displaySubtitle {
    final secondLine = addressLine2;
    if (secondLine != null && secondLine != displayTitle) return secondLine;
    if (formattedAddress != displayTitle) return formattedAddress;
    return null;
  }

  String? get suggestedVenueName {
    if (resultType != 'amenity') return null;
    final value = name?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

String _requiredString(Object? value, String field) {
  final normalized = _optionalString(value);
  if (normalized == null) throw FormatException('$field is invalid.');
  return normalized;
}

String? _optionalString(Object? value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

double _requiredDouble(Object? value, String field) {
  if (value is num && value.isFinite) return value.toDouble();
  throw FormatException('$field is invalid.');
}
