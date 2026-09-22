import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// What kind of place a search result / map tap is.
enum PlaceKind { country, region, city, other }

/// "Rome (Roma)" when the local name differs from the English one,
/// otherwise just "Rome".
String bilingualLabel(String name, String? local) {
  final l = local?.trim();
  if (l == null || l.isEmpty) return name;
  if (l.toLowerCase() == name.trim().toLowerCase()) return name;
  return '$name ($l)';
}

/// One polygon of a country border: an outer ring plus optional holes.
class CountryPolygon {
  final List<LatLng> outer;
  final List<List<LatLng>> holes;
  const CountryPolygon(this.outer, this.holes);
}

/// A country together with its border, ready to be painted on the map.
class CountryShape {
  final PlaceResult place;
  final List<CountryPolygon> polygons;
  const CountryShape(this.place, this.polygons);
}

/// A place on Earth described in English AND in the local language.
///
/// It can be a city, a region (Crete, Washington state, Tuscany...) or a
/// whole country. [city] / [region] / [country] are the fields that end up
/// saved on a memory's `Location`.
class PlaceResult {
  /// Name of the place itself, in English (e.g. "Crete").
  final String name;

  /// Name of the place itself, in the local language (e.g. "Κρήτη").
  final String? nameLocal;

  final PlaceKind kind;

  final String city;
  final String? cityLocal;
  final String? region;
  final String? regionLocal;
  final String country;
  final String? countryLocal;
  final String? countryCode;

  final double lat;
  final double lon;

  /// [south, north, west, east] — used to zoom the map so that a whole
  /// region or country fits on screen.
  final List<double>? bounds;

  const PlaceResult({
    required this.name,
    this.nameLocal,
    required this.kind,
    required this.city,
    this.cityLocal,
    this.region,
    this.regionLocal,
    required this.country,
    this.countryLocal,
    this.countryCode,
    required this.lat,
    required this.lon,
    this.bounds,
  });

  /// "Rome (Roma)"
  String get title => bilingualLabel(name, nameLocal);

  /// "Lazio, Italy (Italia)" — the context around [title].
  String get subtitle {
    final parts = <String>[];
    final r = region;
    if (r != null && r.isNotEmpty && !_same(r, name)) {
      parts.add(bilingualLabel(r, regionLocal));
    }
    if (country.isNotEmpty && !_same(country, name)) {
      parts.add(bilingualLabel(country, countryLocal));
    }
    return parts.join(', ');
  }

  String get fullLabel => subtitle.isEmpty ? title : '$title, $subtitle';

  PlaceResult copyWith({
    String? nameLocal,
    String? cityLocal,
    String? regionLocal,
    String? countryLocal,
    double? lat,
    double? lon,
  }) {
    return PlaceResult(
      name: name,
      nameLocal: nameLocal ?? this.nameLocal,
      kind: kind,
      city: city,
      cityLocal: cityLocal ?? this.cityLocal,
      region: region,
      regionLocal: regionLocal ?? this.regionLocal,
      country: country,
      countryLocal: countryLocal ?? this.countryLocal,
      countryCode: countryCode,
      lat: lat ?? this.lat,
      lon: lon ?? this.lon,
      bounds: bounds,
    );
  }

  static bool _same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();
}

/// Talks to OpenStreetMap's Nominatim to find places and to turn map taps
/// into place names — always returning both the English and the local name.
///
/// How the two languages are obtained:
///  * English  → `accept-language=en` (+ `name:en`).
///  * Local    → the OSM `name` tag, which is by definition the name used
///    in the country itself ("Roma", "Paris", "Κρήτη"). For the address
///    parts (region, country) a second request is made in the country's
///    main language, see [resolveLocal].
class GeocodingService {
  GeocodingService._();
  static final GeocodingService instance = GeocodingService._();

  static const _host = 'nominatim.openstreetmap.org';
  static const _userAgent = 'WorldTravellerProject/2.0';

  static const _cityKeys = [
    'city', 'town', 'village', 'municipality', 'hamlet', 'city_district', 'suburb',
  ];
  static const _regionKeys = ['state', 'province', 'region', 'state_district', 'county'];

  static const _regionTypes = {
    'state', 'region', 'province', 'state_district', 'county', 'island',
    'archipelago', 'department', 'district',
  };
  static const _cityTypes = {
    'city', 'town', 'village', 'municipality', 'hamlet', 'suburb',
    'city_district', 'borough', 'quarter', 'neighbourhood',
  };

  /// Main language of countries that have a single dominant one. For all
  /// the others (Belgium, Switzerland, India...) [_undetermined] is used,
  /// which makes Nominatim fall back to the plain OSM `name` tag — i.e. the
  /// genuinely local spelling.
  static const _countryLanguage = {
    'it': 'it', 'fr': 'fr', 'de': 'de', 'es': 'es', 'pt': 'pt', 'gr': 'el',
    'nl': 'nl', 'at': 'de', 'pl': 'pl', 'cz': 'cs', 'sk': 'sk', 'hu': 'hu',
    'ro': 'ro', 'bg': 'bg', 'hr': 'hr', 'si': 'sl', 'rs': 'sr', 'tr': 'tr',
    'ru': 'ru', 'ua': 'uk', 'se': 'sv', 'no': 'no', 'dk': 'da', 'fi': 'fi',
    'is': 'is', 'gb': 'en', 'us': 'en', 'au': 'en', 'nz': 'en', 'jp': 'ja',
    'cn': 'zh', 'tw': 'zh', 'kr': 'ko', 'th': 'th', 'vn': 'vi', 'id': 'id',
    'my': 'ms', 'il': 'he', 'eg': 'ar', 'ma': 'ar', 'tn': 'ar', 'sa': 'ar',
    'ae': 'ar', 'jo': 'ar', 'lb': 'ar', 'ge': 'ka', 'am': 'hy', 'az': 'az',
    'ee': 'et', 'lv': 'lv', 'lt': 'lt', 'al': 'sq', 'mk': 'mk', 'cl': 'es',
    'ar': 'es', 'mx': 'es', 'co': 'es', 'pe': 'es', 'br': 'pt', 'uy': 'es',
    'ec': 'es', 'cu': 'es', 'cr': 'es', 'pa': 'es', 'bo': 'es', 've': 'es',
    'kh': 'km', 'la': 'lo', 'mm': 'my', 'np': 'ne', 'bd': 'bn', 'mn': 'mn',
    'uz': 'uz',
  };
  static const _undetermined = 'und';

  final Map<String, List<PlaceResult>> _searchCache = {};

  // ---------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------

  /// Free-text search: cities, regions, countries and landmarks, matched
  /// on English AND local names ("Rome" and "Roma", "Greece" and "Ελλάδα").
  ///
  /// Names in the results are already bilingual for the place itself; the
  /// local names of its region/country are added by [resolveLocal] once the
  /// user actually picks a result (saves one request per result).
  Future<List<PlaceResult>> search(String query) async {
    final q = query.trim();
    if (q.length < 2) return [];

    final cacheKey = q.toLowerCase();
    final cached = _searchCache[cacheKey];
    if (cached != null) return cached;

    final data = await _getJson('/search', {
      'q': q,
      'format': 'jsonv2',
      'addressdetails': '1',
      'namedetails': '1',
      'limit': '10',
      'dedupe': '1',
      'accept-language': 'en',
    });

    if (data is! List) return [];

    final results = <PlaceResult>[];
    final seen = <String>{};

    for (final raw in data) {
      if (raw is! Map) continue;
      final item = raw.cast<String, dynamic>();
      if (item['category'] == 'highway') continue;

      final place = _parse(item);
      if (place == null) continue;

      final key = '${place.name}|${place.region}|${place.country}|${place.kind}'.toLowerCase();
      if (!seen.add(key)) continue;

      results.add(place);
    }

    _searchCache[cacheKey] = results;
    return results;
  }

  /// Turns a tapped point on the map into a bilingual place.
  Future<PlaceResult?> reverse(double lat, double lon) async {
    final data = await _getJson('/reverse', {
      'format': 'jsonv2',
      'lat': lat.toString(),
      'lon': lon.toString(),
      'zoom': '10',
      'addressdetails': '1',
      'namedetails': '1',
      'accept-language': 'en',
    });

    if (data is! Map || data['error'] != null) return null;

    final base = _parse(data.cast<String, dynamic>(), fromReverse: true);
    if (base == null) return null;

    // Keep the exact point the user tapped, not the centre of the town.
    return resolveLocal(base.copyWith(lat: lat, lon: lon));
  }

  /// The country containing a point, with its border polygon.
  ///
  /// The returned [PlaceResult.lat]/[PlaceResult.lon] are the country's own
  /// reference point, so every memory saved "on a country" ends up at
  /// exactly the same spot. Returns null over the sea.
  Future<CountryShape?> countryAt(double lat, double lon) async {
    final data = await _getJson('/reverse', {
      'format': 'jsonv2',
      'lat': lat.toString(),
      'lon': lon.toString(),
      'zoom': '3',
      'addressdetails': '1',
      'namedetails': '1',
      'polygon_geojson': '1',
      // Simplify the border (degrees) to keep the download small.
      'polygon_threshold': '0.03',
      'accept-language': 'en',
    });

    if (data is! Map || data['error'] != null) return null;
    final item = data.cast<String, dynamic>();

    final base = _parse(item);
    if (base == null || base.country.isEmpty) return null;

    // Force a country-level place, whatever OSM called the feature.
    final place = PlaceResult(
      name: base.country,
      nameLocal: base.kind == PlaceKind.country ? base.nameLocal : null,
      kind: PlaceKind.country,
      city: base.country,
      cityLocal: base.kind == PlaceKind.country ? base.nameLocal : null,
      country: base.country,
      countryLocal: base.kind == PlaceKind.country ? base.nameLocal : null,
      countryCode: base.countryCode,
      lat: base.lat,
      lon: base.lon,
      bounds: base.bounds,
    );

    return CountryShape(place, _parseGeoJson(item['geojson']));
  }

  static List<LatLng> _ring(dynamic raw) {
    final points = <LatLng>[];
    if (raw is List) {
      for (final c in raw) {
        if (c is List && c.length >= 2 && c[0] is num && c[1] is num) {
          // GeoJSON order is [longitude, latitude].
          points.add(LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()));
        }
      }
    }
    return points;
  }

  static List<CountryPolygon> _parseGeoJson(dynamic geo) {
    if (geo is! Map) return [];
    final type = geo['type'];
    final coords = geo['coordinates'];
    if (coords is! List) return [];

    CountryPolygon? fromRings(dynamic rings) {
      if (rings is! List || rings.isEmpty) return null;
      final outer = _ring(rings.first);
      if (outer.length < 3) return null;
      final holes = rings.skip(1).map(_ring).where((r) => r.length >= 3).toList();
      return CountryPolygon(outer, holes);
    }

    if (type == 'Polygon') {
      final poly = fromRings(coords);
      return poly == null ? [] : [poly];
    }
    if (type == 'MultiPolygon') {
      return coords.map(fromRings).whereType<CountryPolygon>().toList();
    }
    return [];
  }

  /// Fills in the local-language names of the region and the country
  /// (and of the city itself when still missing). Never throws: if the
  /// request fails the place is returned unchanged.
  Future<PlaceResult> resolveLocal(PlaceResult place) async {
    try {
      final data = await _getJson('/reverse', {
        'format': 'jsonv2',
        'lat': place.lat.toString(),
        'lon': place.lon.toString(),
        'zoom': place.kind == PlaceKind.country ? '3' : '10',
        'addressdetails': '1',
        'namedetails': '1',
        'accept-language': _localLanguage(place.countryCode),
      });

      if (data is! Map || data['error'] != null) return place;

      final address = (data['address'] as Map?)?.cast<String, dynamic>() ?? {};

      final localCountry = _pick(address, ['country']);
      final localRegion = _pick(address, _regionKeys);
      final localCity = _pick(address, _cityKeys);

      // copyWith keeps the existing value whenever we pass null, so names
      // already read from OSM (`name` tag) always win over these ones.
      final isCity = place.kind == PlaceKind.city;
      final isRegion = place.kind == PlaceKind.region;

      return place.copyWith(
        countryLocal: place.countryLocal == null ? localCountry : null,
        regionLocal: (!isRegion && place.regionLocal == null) ? localRegion : null,
        cityLocal: (isCity && place.cityLocal == null) ? localCity : null,
        nameLocal: (isCity && place.nameLocal == null) ? localCity : null,
      );
    } catch (_) {
      return place;
    }
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  String _localLanguage(String? countryCode) =>
      _countryLanguage[countryCode?.toLowerCase()] ?? _undetermined;

  Future<dynamic> _getJson(String path, Map<String, String> params) async {
    final uri = Uri.https(_host, path, params);
    final response = await http.get(uri, headers: {'User-Agent': _userAgent});

    if (response.statusCode != 200) {
      throw Exception('Nominatim error: ${response.statusCode}');
    }

    // Decode the raw bytes so Greek / Cyrillic / CJK names never get garbled.
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  static String? _pick(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  static PlaceKind _kindOf(Map<String, dynamic> item) {
    final t = '${item['addresstype'] ?? item['type'] ?? ''}'.toLowerCase();
    if (t == 'country') return PlaceKind.country;
    if (_regionTypes.contains(t)) return PlaceKind.region;
    if (_cityTypes.contains(t)) return PlaceKind.city;
    return PlaceKind.other;
  }

  static bool _same(String a, String b) => a.trim().toLowerCase() == b.trim().toLowerCase();

  PlaceResult? _parse(Map<String, dynamic> item, {bool fromReverse = false}) {
    final lat = double.tryParse('${item['lat']}');
    final lon = double.tryParse('${item['lon']}');
    if (lat == null || lon == null) return null;

    final address = (item['address'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final names = (item['namedetails'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};

    final addrCity = _pick(address, _cityKeys);
    final addrRegion = _pick(address, _regionKeys);
    final addrCountry = _pick(address, ['country']);
    final countryCode = (address['country_code'] as String?)?.toLowerCase();

    var kind = _kindOf(item);

    String? name = _pick(names, ['name:en']) ??
        _pick(item, ['name']) ??
        _pick(names, ['name']);
    String? nameLocal = _pick(names, ['name']);

    // A tap on the map: the "place" is the town around the tapped point.
    if (fromReverse && addrCity != null) {
      name = addrCity;
      nameLocal = null; // filled in by resolveLocal
      kind = PlaceKind.city;
    }

    name ??= addrCity ?? addrRegion ?? addrCountry;
    if (name == null || name.isEmpty) return null;

    // City field saved on the memory.
    String cityName;
    String? cityLocal;
    switch (kind) {
      case PlaceKind.other:
        cityName = addrCity ?? name;
        cityLocal = (addrCity == null || _same(addrCity, name)) ? nameLocal : null;
        break;
      default:
        cityName = name;
        cityLocal = nameLocal;
    }

    // Region field.
    String? region = addrRegion;
    String? regionLocal;
    if (kind == PlaceKind.region) {
      region = name;
      regionLocal = nameLocal;
    } else if (kind == PlaceKind.country) {
      region = null;
    }

    final country = addrCountry ?? (kind == PlaceKind.country ? name : '');
    final countryLocal = kind == PlaceKind.country ? nameLocal : null;

    // boundingbox = [south, north, west, east], as strings.
    List<double>? bounds;
    final bb = item['boundingbox'];
    if (bb is List && bb.length == 4) {
      final parsed = bb.map((v) => double.tryParse('$v')).toList();
      if (!parsed.contains(null)) {
        bounds = parsed.cast<double>();
      }
    }

    return PlaceResult(
      name: name,
      nameLocal: nameLocal,
      kind: kind,
      city: cityName,
      cityLocal: cityLocal,
      region: region,
      regionLocal: regionLocal,
      country: country,
      countryLocal: countryLocal,
      countryCode: countryCode,
      lat: lat,
      lon: lon,
      bounds: bounds,
    );
  }
}
