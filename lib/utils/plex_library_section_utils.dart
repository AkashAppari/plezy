import 'json_utils.dart';

final RegExp plexLibrarySectionPathPattern = RegExp(r'/(?:library|hubs)/sections/(\d+)');

int? plexLibrarySectionIdFromJson(Map<String, dynamic>? json) {
  if (json == null) return null;
  final direct = flexibleInt(json['librarySectionID']) ?? flexibleInt(json['targetLibrarySectionID']);
  if (direct != null) return direct;

  for (final key in const ['librarySectionKey', 'key', 'hubKey']) {
    final parsed = plexLibrarySectionIdFromString(json[key]?.toString());
    if (parsed != null) return parsed;
  }
  return null;
}

int? plexLibrarySectionIdFromString(String? value) {
  if (value == null || value == 'shared') return null;
  final direct = int.tryParse(value);
  if (direct != null) return direct;
  final match = plexLibrarySectionPathPattern.firstMatch(value);
  return match == null ? null : int.tryParse(match.group(1)!);
}

String? plexLibrarySectionTitleFromJson(Map<String, dynamic>? json) {
  return json?['librarySectionTitle']?.toString();
}
