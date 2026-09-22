import 'dart:collection';
import 'package:uuid/uuid.dart';
import 'package:world_traveller_project/models/media.dart';

class Location {
  // fields
  final String _id;
  final String? _userId;
  final String _city;
  final String _country;

  /// Region/state, e.g. "Tuscany". Optional: not every place needs one.
  final String? _region;

  // Bilingual names for the map: English (used by default) plus the
  // local-language name, e.g. city="Rome" / cityLocal="Roma".
  final String? _cityLocal;
  final String? _regionLocal;
  final String? _countryLocal;

  final double _latitude;
  final double _longitude;
  final SplayTreeSet<Media> _mediaSet;

  static SplayTreeSet<Media> _createMediaSet([Iterable<Media>? elements]) {
    final set = SplayTreeSet<Media>((a, b) {
      int comp = a.lastModification.compareTo(b.lastModification);
      if (comp != 0) return comp;
      return a.id.compareTo(b.id);
    });
    if (elements != null) {
      set.addAll(elements);
    }
    return set;
  }

  // constructor
  Location({
    String? id,
    String? userId,
    required String city,
    required String country,
    String? region,
    String? cityLocal,
    String? regionLocal,
    String? countryLocal,
    required double latitude,
    required double longitude,
    SplayTreeSet<Media>? mediaSet,
  })  : _id = id ?? const Uuid().v4(),
        _userId = userId,
        _city = city,
        _country = country,
        _region = region,
        _cityLocal = cityLocal,
        _regionLocal = regionLocal,
        _countryLocal = countryLocal,
        _latitude = latitude,
        _longitude = longitude,
        _mediaSet = mediaSet ?? _createMediaSet();

  // getters
  String get id => _id;

  /// Who created this pin. Used to decide who may move it, delete it, or
  /// add more pictures to it — nobody but the owner (or, for deleting a
  /// pin that only holds public content, the admin) may touch it.
  String? get userId => _userId;

  String get city => _city;
  String get country => _country;
  String? get region => _region;
  String? get cityLocal => _cityLocal;
  String? get regionLocal => _regionLocal;
  String? get countryLocal => _countryLocal;
  double get latitude => _latitude;
  double get longitude => _longitude;
  SplayTreeSet<Media> get mediaSet => _mediaSet;

  /// Label shown on the map: local name in parentheses when it differs
  /// from the English one, e.g. "Rome (Roma)".
  String get cityLabel =>
      (cityLocal != null && cityLocal!.trim().isNotEmpty && cityLocal != city)
          ? '$city ($cityLocal)'
          : city;

  String get countryLabel =>
      (countryLocal != null && countryLocal!.trim().isNotEmpty && countryLocal != country)
          ? '$country ($countryLocal)'
          : country;

  /// True for memories pinned on a whole country (city == country), as
  /// created by double-clicking a country on the map. Shown as blue pins.
  bool get isCountryLevel =>
      city.trim().isNotEmpty && city.trim().toLowerCase() == country.trim().toLowerCase();

  /// "Crete (Κρήτη)" — null when the place has no region.
  String? get regionLabel {
    final r = region;
    if (r == null || r.trim().isEmpty) return null;
    return (regionLocal != null && regionLocal!.trim().isNotEmpty && regionLocal != r)
        ? '$r ($regionLocal)'
        : r;
  }

  /// "Rome (Roma), Lazio, Italy (Italia)" — every part in both languages.
  String get fullLabel {
    final parts = <String>[cityLabel];
    final r = regionLabel;
    if (r != null && r != cityLabel) parts.add(r);
    if (country.trim().isNotEmpty && country != city) parts.add(countryLabel);
    return parts.join(', ');
  }

  /// True when [query] matches this place on ANY of its name fields —
  /// city, region or country, in either English or the local language.
  /// Centralised here so every search box (map sidebar, "All memories")
  /// benefits from the bilingual names added in Phase 1 instead of only
  /// ever matching the English city/country, as used to be the case.
  bool matchesQuery(String query) {
    final q = _fold(query.trim());
    if (q.isEmpty) return true;

    bool contains(String? value) => value != null && _fold(value).contains(q);

    return contains(city) ||
        contains(country) ||
        contains(region) ||
        contains(cityLocal) ||
        contains(regionLocal) ||
        contains(countryLocal);
  }

  /// Lower-cases and strips Latin accents so that "malaga" finds "Málaga"
  /// and "zurich" finds "Zürich".
  static String _fold(String input) {
    final buffer = StringBuffer();
    for (final rune in input.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      buffer.write(_accentMap[ch] ?? ch);
    }
    return buffer.toString();
  }

  static const Map<String, String> _accentMap = {
    'ß': 'ss',
    'à': 'a', 'á': 'a', 'â': 'a', 'ã': 'a', 'ä': 'a', 'å': 'a', 'æ': 'ae',
    'ç': 'c',
    'è': 'e', 'é': 'e', 'ê': 'e', 'ë': 'e',
    'ì': 'i', 'í': 'i', 'î': 'i', 'ï': 'i',
    'ð': 'd', 'ñ': 'n',
    'ò': 'o', 'ó': 'o', 'ô': 'o', 'õ': 'o', 'ö': 'o', 'ø': 'o',
    'ù': 'u', 'ú': 'u', 'û': 'u', 'ü': 'u',
    'ý': 'y', 'þ': 'th', 'ÿ': 'y',
    'ā': 'a', 'ă': 'a', 'ą': 'a',
    'ć': 'c', 'ĉ': 'c', 'ċ': 'c', 'č': 'c',
    'ď': 'd', 'đ': 'd',
    'ē': 'e', 'ĕ': 'e', 'ė': 'e', 'ę': 'e', 'ě': 'e',
    'ĝ': 'g', 'ğ': 'g', 'ġ': 'g', 'ģ': 'g',
    'ĥ': 'h',
    'ĩ': 'i', 'ī': 'i', 'ĭ': 'i', 'į': 'i', 'ı': 'i',
    'ĵ': 'j', 'ķ': 'k',
    'ĺ': 'l', 'ļ': 'l', 'ľ': 'l', 'ł': 'l',
    'ń': 'n', 'ņ': 'n', 'ň': 'n',
    'ō': 'o', 'ŏ': 'o', 'ő': 'o', 'œ': 'oe',
    'ŕ': 'r', 'ŗ': 'r', 'ř': 'r',
    'ś': 's', 'ŝ': 's', 'ş': 's', 'š': 's',
    'ţ': 't', 'ť': 't',
    'ũ': 'u', 'ū': 'u', 'ŭ': 'u', 'ů': 'u', 'ű': 'u', 'ų': 'u',
    'ŵ': 'w', 'ŷ': 'y',
    'ź': 'z', 'ż': 'z', 'ž': 'z',
  };

  // methods
  void addMedia(Media media) {
    _mediaSet.removeWhere((item) => item.id == media.id);
    _mediaSet.add(media);
  }

  void removeMedia(Media media) {
    _mediaSet.removeWhere((item) => item.id == media.id);
  }

  void updateMedia(Media updatedMedia) {
    _mediaSet.removeWhere((item) => item.id == updatedMedia.id);
    _mediaSet.add(updatedMedia);
  }

  /// Returns a copy of this place carrying only [media] — used to build
  /// the "My Work" / "General World" filtered views without mutating the
  /// original data held by the controller.
  Location withMedia(Iterable<Media> media) {
    return Location(
      id: _id,
      userId: _userId,
      city: _city,
      country: _country,
      region: _region,
      cityLocal: _cityLocal,
      regionLocal: _regionLocal,
      countryLocal: _countryLocal,
      latitude: _latitude,
      longitude: _longitude,
      mediaSet: _createMediaSet(media),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'city': city,
      'country': country,
      'region': region,
      'cityLocal': cityLocal,
      'regionLocal': regionLocal,
      'countryLocal': countryLocal,
      'latitude': latitude,
      'longitude': longitude,
      'media': mediaSet.map((item) => item.toJson()).toList(),
    };
  }

  factory Location.fromJson(Map<String, dynamic> json) {
    final mediaRaw = json['media'] as List? ?? [];
    final mediaList = mediaRaw.map((item) => Media.fromJson(item as Map<String, dynamic>));

    return Location(
      id: json['id'] as String?,
      userId: json['userId'] as String?,
      city: json['city'] as String? ?? 'Unknown',
      country: json['country'] as String? ?? 'Unknown',
      region: json['region'] as String?,
      cityLocal: json['cityLocal'] as String?,
      regionLocal: json['regionLocal'] as String?,
      countryLocal: json['countryLocal'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      mediaSet: _createMediaSet(mediaList),
    );
  }

  factory Location.fromSupabase(Map<String, dynamic> row, [Iterable<Media>? mediaList]) {
    return Location(
      id: row['id'] as String?,
      userId: row['user_id']?.toString(),
      city: row['city'] as String? ?? 'Unknown',
      country: row['country'] as String? ?? 'Unknown',
      region: row['region'] as String?,
      cityLocal: row['city_local'] as String?,
      regionLocal: row['region_local'] as String?,
      countryLocal: row['country_local'] as String?,
      latitude: (row['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (row['longitude'] as num?)?.toDouble() ?? 0.0,
      mediaSet: _createMediaSet(mediaList),
    );
  }

  Map<String, dynamic> toSupabase(String userId) {
    return {
      'id': id,
      'user_id': userId,
      'city': city,
      'country': country,
      'region': region,
      'city_local': cityLocal,
      'region_local': regionLocal,
      'country_local': countryLocal,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}
