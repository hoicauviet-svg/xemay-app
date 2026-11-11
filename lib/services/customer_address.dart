/// Avoid appending the locality twice when an old customer was already edited.
String mergedCustomerAddress(dynamic detail, dynamic locality) {
  final address = '${detail ?? ''}'.trim();
  final place = '${locality ?? ''}'.trim();
  if (place.isEmpty) return address;
  if (address.isEmpty) return place;
  final normalized = address.toLowerCase();
  final suffix = place.toLowerCase();
  if (normalized == suffix || normalized.endsWith(', $suffix')) return address;
  return '$address, $place';
}
