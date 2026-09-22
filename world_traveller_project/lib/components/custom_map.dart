import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:world_traveller_project/services/geocoding_service.dart';
import 'package:world_traveller_project/views/add_media_view.dart';

class CustomMap extends StatefulWidget {
  final bool setMarkersAllowed;
  final bool addButtonVisible;
  final void Function(
    LatLng position,
    String? city,
    String? country,
  )? onLocationSelected;
  /// Same as [onLocationSelected] but with the full bilingual place
  /// (region, local names, country code...) resolved for the tapped point.
  final void Function(PlaceResult? place)? onPlaceResolved;

  final List<Marker>? initialMarkers;

  /// When set, the map programmatically jumps to this position and drops a
  /// pin there, without requiring the user to tap the map. Used to support
  /// jumping to a location chosen from a city search dropdown.
  final LatLng? focusPosition;
  final String? focusCity;
  final String? focusCountry;

  /// Optional: the place picked from the search dropdown. When given, the
  /// map zooms to fit it (a whole region or country, not just a point) and
  /// shows its bilingual name.
  final PlaceResult? focusPlace;

  const CustomMap({
    super.key,
    required this.setMarkersAllowed,
    required this.addButtonVisible,
    this.onLocationSelected,
    this.onPlaceResolved,
    this.initialMarkers,
    this.focusPosition,
    this.focusCity,
    this.focusCountry,
    this.focusPlace,
  });

  @override
  State<CustomMap> createState() => _CustomMapState();
}

class _CustomMapState extends State<CustomMap> {
  List<Marker> _markers = [];
  LatLng? _selectedPosition;
  String? _selectedCountry;
  String? _selectedCity;
  PlaceResult? _selectedPlace;
  bool _isLoadingLocation = false;
  int _tapRequestId = 0;

  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _markers = List.from(widget.initialMarkers ?? []);

    if (widget.focusPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _focusOnPosition(
          widget.focusPosition!,
          widget.focusCity,
          widget.focusCountry,
          widget.focusPlace,
        );
      });
    }
  }

  @override
  void didUpdateWidget(covariant CustomMap oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.initialMarkers != widget.initialMarkers) {
      setState(() {
        _markers = List.from(widget.initialMarkers ?? []);
      });
    }

    if (widget.focusPosition != null &&
        widget.focusPosition != oldWidget.focusPosition) {
      _focusOnPosition(
        widget.focusPosition!,
        widget.focusCity,
        widget.focusCountry,
        widget.focusPlace,
      );
    }
  }

  void _focusOnPosition(
    LatLng position,
    String? city,
    String? country, [
    PlaceResult? place,
  ]) {
    // After a tap the parent re-focuses the very same point; keep the
    // bilingual place we just resolved for it instead of dropping it.
    place ??= (position == _selectedPosition) ? _selectedPlace : null;

    _clearMarkers();

    setState(() {
      _selectedPosition = position;
      _selectedCity = city;
      _selectedCountry = country;
      _selectedPlace = place;
      _isLoadingLocation = false;

      _markers.add(
        Marker(
          point: position,
          width: 50,
          height: 50,
          child: const Icon(
            Icons.location_pin,
            size: 45,
            color: Colors.red,
          ),
        ),
      );
    });

    final b = place?.bounds;
    if (place != null && b != null && place.kind != PlaceKind.other) {
      // b = [south, north, west, east]: fit the whole region / country.
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds(LatLng(b[0], b[2]), LatLng(b[1], b[3])),
          padding: const EdgeInsets.all(40),
          maxZoom: 14,
        ),
      );
    } else {
      _mapController.move(position, 13);
    }
  }

  Future<void> _onMapTap(
    TapPosition tapPosition,
    LatLng position,
  ) async {
    final requestId = ++_tapRequestId;

    _clearMarkers();

    setState(() {
      _selectedPosition = position;
      _isLoadingLocation = true;

      _markers.add(
        Marker(
          point: position,
          width: 50,
          height: 50,
          child: const Icon(
            Icons.location_pin,
            size: 45,
            color: Colors.red,
          ),
        ),
      );
    });

    try {
      final place = await GeocodingService.instance.reverse(
        position.latitude,
        position.longitude,
      );

      if (!mounted || requestId != _tapRequestId) {
        return;
      }

      setState(() {
        _selectedPlace = place;
        _selectedCity = place?.city;
        _selectedCountry = place?.country;
        _isLoadingLocation = false;
      });

      widget.onPlaceResolved?.call(place);
      widget.onLocationSelected?.call(
        position,
        _selectedCity,
        _selectedCountry,
      );
    } catch (_) {
      if (!mounted || requestId != _tapRequestId) {
        return;
      }

      setState(() {
        _isLoadingLocation = false;
      });
    }
  }

  void _clearMarkers() {
    setState(() {
      if (widget.initialMarkers != null) {
        _markers.removeWhere(
          (marker) => !widget.initialMarkers!.contains(marker),
        );
      } else {
        _markers.clear();
      }

      _selectedPosition = null;
      _selectedCountry = null;
      _selectedCity = null;
      _selectedPlace = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: const LatLng(48.5, 10.0),
            initialZoom: 4.5,
            minZoom: 2,
            maxZoom: 18,
            cameraConstraint: CameraConstraint.contain(
              bounds: LatLngBounds(
                const LatLng(-90.0, 180.0),
                const LatLng(90.0, -180.0),
              ),
            ),
            onTap: widget.setMarkersAllowed ? _onMapTap : null,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName:
                  'com.example.world_traveller_project',
            ),
            MarkerLayer(markers: _markers),
            Positioned(
              right: 16,
              bottom: 12,
              child: Material(
                type: MaterialType.transparency,
                child: RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ),
            ),
          ],
        ),

        if (_selectedPosition != null)
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.topCenter,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  elevation: 3,
                  borderRadius: BorderRadius.circular(24),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: _isLoadingLocation
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Text('Finding the place...', style: TextStyle(fontSize: 13)),
                            ],
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.place, size: 16, color: Colors.redAccent),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  // Bilingual when known: "Rome (Roma), Lazio, Italy (Italia)".
                                  _selectedPlace?.fullLabel ??
                                      '${_selectedCity ?? "Unknown city"}, '
                                          '${_selectedCountry ?? "?"}',
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),

        if (widget.addButtonVisible)
          Positioned(
            right: 96,
            bottom: 16,
            child: FloatingActionButton(
              tooltip: 'Add memory',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AddMediaView(),
                  ),
                );
              },
              child: const Icon(Icons.add),
            ),
          ),
      ],
    );
  }
}
