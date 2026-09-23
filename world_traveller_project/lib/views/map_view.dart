import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/components/app_navigation.dart';
import 'package:world_traveller_project/components/media_tile.dart';
import 'package:world_traveller_project/enums/media_visibility.dart';
import 'package:world_traveller_project/models/location.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/providers/location_managing_controller.dart';
import 'package:world_traveller_project/main.dart';
import 'package:world_traveller_project/providers/social_controller.dart';
import 'package:world_traveller_project/services/geocoding_service.dart';
import 'package:world_traveller_project/views/about_view.dart';
import 'package:world_traveller_project/views/add_media_view.dart';
import 'package:world_traveller_project/views/favourites_view.dart';
import 'package:world_traveller_project/views/mailbox_view.dart';
import 'package:world_traveller_project/views/media_collection_view.dart';
import 'package:world_traveller_project/views/my_memories_view.dart';
import 'package:world_traveller_project/views/preview_view.dart';
import 'package:world_traveller_project/views/user_profile_view.dart';
import 'package:world_traveller_project/views/user_search_view.dart';
import 'package:world_traveller_project/views/my_account_view.dart';

const double _kSidebarWidth = 340;

/// How wide the side panel gets once expanded. Whoever opens it wants to
/// actually look at the pictures, so it takes a big slice of the window.
const double _kSidebarExpandedWidth = 820;

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  final ScrollController _sidebarScrollController = ScrollController();
  final Map<String, GlobalKey> _sectionKeys = {};

  String? _selectedLocationId;
  Location? _pinnedLocation;
  bool _sidebarExpanded = false;
  bool _sidebarVisibleOnMobile = false;
  Location? _locationBeingMoved;

  /// Whether the main navigation sidebar (not the photo gallery panel
  /// above) is showing its text labels or collapsed down to icons.
  bool _navExpanded = true;

  /// Lets nav destinations close the Drawer on mobile before navigating,
  /// without accidentally popping the map screen itself off the stack.
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Set by a plain tap on empty map: a temporary pin waiting for
  /// confirmation (long-press) before a new memory is actually created.
  LatLng? _pendingLocation;

  /// Brief "hold to confirm" feedback shown between the long-press and the
  /// confirmation dialog.
  bool _preparingNewMemory = false;

  // World place search (cities, regions, countries) shown under the search
  // box, on top of the filter that narrows down the saved memories.
  Timer? _placeDebounce;
  List<PlaceResult> _placeResults = [];
  bool _searchingPlaces = false;
  int _placeRequestId = 0;

  // Double-click on the map selects (and paints orange) a whole country.
  CountryShape? _selectedCountry;
  bool _loadingCountry = false;
  int _countryRequestId = 0;
  DateTime? _lastClickTime;
  Offset? _lastClickPos;
  bool _ignoreNextTap = false;

  // Filtri & ricerca
  String _searchQuery = '';
  double? _minRatingFilter;
  String? _tagFilter;

  /// Fase 2, punto 12: la barra di ricerca/filtri laterale parte
  /// minimizzata (piccolo bottone) ed espande l'area solo su richiesta.
  bool _searchExpanded = false;

  /// Fase 2, punto 12 (parte "Favorites" laterale): stesso pattern del
  /// bottone di ricerca — parte come piccolo bottone a forma di cuore ed
  /// espande una striscia orizzontale di anteprime solo su richiesta,
  /// invece di occupare sempre spazio nella sidebar.
  bool _favouritesExpanded = false;

  bool get _hasActiveFilters => _minRatingFilter != null || _tagFilter != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final locations = await context
          .read<LocationManagingController>()
          .loadLocationsFromJSON();

      if (!mounted) return;
      // Look up who posted each picture so the grids can show their name.
      // Resolved for every location regardless of the current world scope,
      // so switching "My Work" <-> "General World" never has to re-fetch.
      await context.read<SocialController>().resolveUsernames(
            locations.expand((loc) => loc.mediaSet),
          );
    });
  }

  @override
  void dispose() {
    _placeDebounce?.cancel();
    _sidebarScrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------
  // World place search (cities, regions, countries — English + local names)
  // ---------------------------------------------------------------------

  void _onPlaceQueryChanged(String value) {
    _placeDebounce?.cancel();

    if (value.trim().length < 2) {
      _placeRequestId++;
      setState(() {
        _placeResults = [];
        _searchingPlaces = false;
      });
      return;
    }

    _placeDebounce = Timer(const Duration(milliseconds: 500), () async {
      final requestId = ++_placeRequestId;
      if (!mounted) return;
      setState(() => _searchingPlaces = true);

      try {
        final results = await GeocodingService.instance.search(value);
        // Drop answers to a query the user has already typed over.
        if (!mounted || requestId != _placeRequestId) return;
        setState(() {
          _placeResults = results;
          _searchingPlaces = false;
        });
      } catch (_) {
        if (mounted && requestId == _placeRequestId) {
          setState(() => _searchingPlaces = false);
        }
      }
    });
  }

  void _clearPlaceSearch() {
    _placeDebounce?.cancel();
    _placeRequestId++;
    _placeResults = [];
    _searchingPlaces = false;
  }

  /// Flies the map to a searched place, zooming so that a whole region or
  /// country fits on screen (Crete, Washington state, Italy...).
  void _goToPlace(PlaceResult place) {
    FocusScope.of(context).unfocus();

    setState(() {
      _placeResults = [];
      // On phones the side panel covers the map: close it so the result
      // is actually visible.
      _sidebarVisibleOnMobile = false;

      // For a town / landmark, also drop the usual temporary pin so it can
      // be turned into a memory with a long-press.
      if (place.kind == PlaceKind.city || place.kind == PlaceKind.other) {
        _pendingLocation = LatLng(place.lat, place.lon);
      }
    });

    // Wait one frame: on mobile the map widget is rebuilt after the panel
    // closes, and the controller must be attached before it can move.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final b = place.bounds; // [south, north, west, east]
      try {
        if (b != null) {
          _mapController.fitCamera(
            CameraFit.bounds(
              bounds: LatLngBounds(LatLng(b[0], b[2]), LatLng(b[1], b[3])),
              padding: const EdgeInsets.all(48),
              maxZoom: 14,
            ),
          );
        } else {
          _mapController.move(LatLng(place.lat, place.lon), 11);
        }
      } catch (_) {
        _mapController.move(LatLng(place.lat, place.lon), 8);
      }
    });
  }

  // ---------------------------------------------------------------------
  // Gestione Tap sulla mappa
  // ---------------------------------------------------------------------

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    // The second click of a double-click already selected a country.
    if (_ignoreNextTap) {
      _ignoreNextTap = false;
      return;
    }

    final locationToMove = _locationBeingMoved;
    if (locationToMove != null) {
      setState(() => _locationBeingMoved = null);

      context
          .read<LocationManagingController>()
          .moveLocation(locationToMove, point.latitude, point.longitude);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${locationToMove.city}" moved to its new position.')),
      );
      return;
    }

    // A single click elsewhere dismisses a selected country.
    if (_selectedCountry != null) {
      setState(() => _selectedCountry = null);
    }

    // A plain tap (not a drag) on the empty map drops a temporary marker.
    // Pressing and holding it confirms creating a memory there; tapping
    // somewhere else moves it.
    setState(() => _pendingLocation = point);
  }

  /// Raw pointer listener: unlike the map's own onTap it is not affected by
  /// flutter_map's double-tap gesture handling, so double-clicks are always
  /// seen. Two left-clicks within 400 ms and 24 px = select a country.
  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;

    final now = DateTime.now();
    final last = _lastClickTime;
    final lastPos = _lastClickPos;

    final isDouble = last != null &&
        lastPos != null &&
        now.difference(last) < const Duration(milliseconds: 400) &&
        (event.localPosition - lastPos).distance < 24;

    if (!isDouble) {
      _lastClickTime = now;
      _lastClickPos = event.localPosition;
      return;
    }

    _lastClickTime = null;
    _lastClickPos = null;

    // While moving a pin, clicks belong to that action.
    if (_locationBeingMoved != null) return;

    // Swallow the onTap that the same click will still deliver.
    _ignoreNextTap = true;
    Future.delayed(const Duration(milliseconds: 600), () => _ignoreNextTap = false);

    final point = _mapController.camera.screenOffsetToLatLng(event.localPosition);
    _selectCountryAt(point);
  }

  Future<void> _selectCountryAt(LatLng point) async {
    final requestId = ++_countryRequestId;

    setState(() {
      _pendingLocation = null; // the first click of the double-click
      _loadingCountry = true;
    });

    try {
      final shape = await GeocodingService.instance.countryAt(
        point.latitude,
        point.longitude,
      );
      if (!mounted || requestId != _countryRequestId) return;

      setState(() {
        _selectedCountry = shape;
        _loadingCountry = false;
      });

      if (shape == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No country found here (open sea?).')),
        );
      }
    } catch (_) {
      if (!mounted || requestId != _countryRequestId) return;
      setState(() => _loadingCountry = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load the country. Try again.')),
      );
    }
  }

  Future<void> _addMemoryToCountry() async {
    final shape = _selectedCountry;
    if (shape == null) return;

    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMediaView(initialPlace: shape.place),
      ),
    );

    if (mounted) setState(() => _selectedCountry = null);
  }

  void _cancelPendingLocation() {
    setState(() => _pendingLocation = null);
  }

  Future<void> _confirmPendingLocation() async {
    final point = _pendingLocation;
    if (point == null) return;

    setState(() => _preparingNewMemory = true);
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    setState(() => _preparingNewMemory = false);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New memory here?'),
        content: const Text('Do you want to add a picture at this spot on the map?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.add_a_photo_outlined),
            label: const Text('Add'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    setState(() => _pendingLocation = null);

    if (confirmed == true) {
      if (!await ensureLoggedIn(context)) return;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddMediaView(initialPosition: point),
        ),
      );
    }
  }

  Future<void> _handleMapSecondaryTap(
    TapPosition tapPosition,
    LatLng point,
  ) async {
    final selected = await _showContextMenu(tapPosition.global, [
      const PopupMenuItem(
        value: 'add',
        child: ListTile(
          dense: true,
          leading: Icon(Icons.add_location_alt_outlined),
          title: Text('Add a memory here'),
        ),
      ),
    ]);

    if (selected == 'add' && mounted) {
      if (!await ensureLoggedIn(context)) return;
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AddMediaView(initialPosition: point),
        ),
      );
    }
  }

  /// True when the signed-in traveller is allowed to add/move a memory
  /// at [location], or (when [forDelete] is true) to delete it.
  /// The owner can always manage their own locations; for deletion,
  /// an admin can also step in (moderation), even on locations they
  /// don't own.
  bool canManageLocation(
    Location location,
    SocialController social, {
    bool forDelete = false,
  }) {
    final currentUserId = social.myProfile?.id;
    if (currentUserId == null) return false;

    final isOwner = location.userId == currentUserId;
    if (isOwner) return true;

    if (forDelete && social.isCurrentUserAdmin) return true;

    return false;
  }

  // ---------------------------------------------------------------------
  // Menu contestuale pin
  // ---------------------------------------------------------------------

  Future<void> _showPinContextMenu(
    Offset globalPosition,
    Location location,
  ) async {
    final social = context.read<SocialController>();
    final canAdd = canManageLocation(location, social);
    final canMove = canManageLocation(location, social);
    final canDelete = canManageLocation(location, social, forDelete: true);

    final selected = await _showContextMenu(globalPosition, [
      const PopupMenuItem(
        value: 'view',
        child: ListTile(
          dense: true,
          leading: Icon(Icons.photo_library_outlined),
          title: Text('View memories'),
        ),
      ),
      // "Add pictures here" / "Move this pin" / "Delete place" only show
      // up for the pin's own owner (delete also for the admin, to clear
      // an offending pin from the public feed) — someone else never even
      // sees these options, exactly like the per-picture Edit/Delete.
      if (canAdd)
        const PopupMenuItem(
          value: 'add_photo',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.add_photo_alternate_outlined),
            title: Text('Add pictures here'),
          ),
        ),
      if (canMove)
        const PopupMenuItem(
          value: 'move',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.open_with),
            title: Text('Move this pin'),
          ),
        ),
      if (canDelete)
        const PopupMenuItem(
          value: 'delete',
          child: ListTile(
            dense: true,
            leading: Icon(Icons.delete_outline, color: Colors.red),
            title: Text('Delete place', style: TextStyle(color: Colors.red)),
          ),
        ),
    ]);

    if (!mounted) return;

    switch (selected) {
      case 'view':
        _focusLocation(location);
        break;
      case 'add_photo':
        _addPhotosToExistingLocation(location);
        break;
      case 'move':
        if (!await ensureLoggedIn(context)) return;
        if (!mounted) return;
        setState(() => _locationBeingMoved = location);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tap anywhere on the map to move "${location.city}".'),
          ),
        );
        break;
      case 'delete':
        _confirmDeleteLocation(location);
        break;
    }
  }

  Future<String?> _showContextMenu(
    Offset globalPosition,
    List<PopupMenuEntry<String>> items,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

    return showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: items,
    );
  }

  Future<void> _confirmDeleteLocation(Location location) async {
    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this place?'),
        content: Text(
          '"${location.city}, ${location.country}" and all '
          '${location.mediaSet.length} pictures saved there will be deleted '
          'for good. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final social = context.read<SocialController>();
      try {
        await context.read<LocationManagingController>().deleteLocation(
              location,
              requestedByAdmin: social.isCurrentUserAdmin,
            );
        if (mounted) {
          if (_selectedLocationId == location.id) {
            setState(() => _selectedLocationId = null);
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${location.city}" has been deleted.')),
          );
        }
      } on MediaPermissionDeniedException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
  }

  /// Adding a picture to a pin that already exists now goes through the
  /// very same guided flow as a brand new memory: map + confirmation,
  /// then picking the pictures, then the details screen.
  Future<void> _addPhotosToExistingLocation(Location location) async {
    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddMediaView(existingLocation: location),
      ),
    );

    if (mounted) setState(() {});
  }

  void _focusLocation(Location location) {
    setState(() {
      _selectedLocationId = location.id;
      _pinnedLocation = location;
      _sidebarVisibleOnMobile = true;
    });

    _mapController.move(
      LatLng(location.latitude, location.longitude),
      (_mapController.camera.zoom < 7 ? 8 : _mapController.camera.zoom),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _sectionKeys[location.id];
      final sectionContext = key?.currentContext;
      if (sectionContext != null) {
        Scrollable.ensureVisible(
          sectionContext,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          alignment: 0.05,
        );
      }
    });
  }

  void _clearPinnedLocation() {
    setState(() {
      _pinnedLocation = null;
      _selectedLocationId = null;
    });
  }

  /// Dropdown with the world places matching the search text. Every entry
  /// shows both languages: "Rome (Roma)" / "Lazio, Italy (Italia)".
  Widget _buildPlaceResults() {
    final theme = Theme.of(context);

    IconData iconFor(PlaceKind kind) {
      switch (kind) {
        case PlaceKind.country:
          return Icons.flag_outlined;
        case PlaceKind.region:
          return Icons.map_outlined;
        case PlaceKind.city:
          return Icons.location_city_outlined;
        case PlaceKind.other:
          return Icons.place_outlined;
      }
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: _placeResults.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Searching the world...', style: TextStyle(fontSize: 13)),
                ],
              ),
            )
          : ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: _placeResults.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final place = _placeResults[index];
                return ListTile(
                  dense: true,
                  leading: Icon(iconFor(place.kind), size: 20),
                  title: Text(
                    place.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: place.subtitle.isEmpty
                      ? null
                      : Text(
                          place.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () => _goToPlace(place),
                );
              },
            ),
    );
  }

  List<MapEntry<Location, List<Media>>> _filteredSections(List<Location> locations) {
    final pinnedId = _pinnedLocation?.id;

    final result = <MapEntry<Location, List<Media>>>[];

    final sourceLocations = pinnedId == null
        ? locations
        : locations.where((loc) => loc.id == pinnedId);

    for (final location in sourceLocations) {
      // Improvement: matches city/country AND region/local names now
      // (Fase 1 added those fields specifically so bilingual names and
      // regions could be searched, but the search here never used them).
      final matchesQuery =
          pinnedId != null || _searchQuery.isEmpty || location.matchesQuery(_searchQuery);

      if (!matchesQuery) continue;

      final media = location.mediaSet.where((m) {
        final matchesRating = _minRatingFilter == null || m.grading >= _minRatingFilter!;
        final matchesTag = _tagFilter == null || m.tags.contains(_tagFilter);
        return matchesRating && matchesTag;
      }).toList();

      if (media.isNotEmpty || location.id == pinnedId) {
        result.add(MapEntry(location, media));
      }
    }

    return result;
  }

  Widget _buildSidebar(List<Location> locations) {
    final Set<String> allTags = {};
    for (final loc in locations) {
      for (final m in loc.mediaSet) {
        allTags.addAll(m.tags);
      }
    }
    final sortedTags = allTags.toList()..sort();
    final sections = _filteredSections(locations);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.collections_bookmark_outlined, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Memories',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          // Fase 2, punto 12: ricerca e filtri partono minimizzati come un
          // piccolo bottone cliccabile; espandono l'area sotto solo quando
          // servono, invece di occupare sempre spazio nella sidebar.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Tooltip(
                  message: _searchExpanded ? 'Hide search & filters' : 'Search & filter',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _searchExpanded = !_searchExpanded),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (_searchExpanded || _searchQuery.isNotEmpty || _hasActiveFilters)
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _searchExpanded ? Icons.search_off : Icons.search,
                        size: 20,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                if (!_searchExpanded && (_searchQuery.isNotEmpty || _hasActiveFilters)) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _searchQuery.isNotEmpty ? '"$_searchQuery"' : 'Filters active',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                // Fase 2, punto 12 ("Favorites" laterale): stesso pattern
                // del bottone di ricerca — piccolo bottone a forma di
                // cuore che espande una striscia di anteprime.
                Tooltip(
                  message: _favouritesExpanded ? 'Hide favourites' : 'Favourites',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => setState(() => _favouritesExpanded = !_favouritesExpanded),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _favouritesExpanded
                            ? Theme.of(context).colorScheme.primaryContainer
                            : Theme.of(context).colorScheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _favouritesExpanded ? Icons.favorite : Icons.favorite_border,
                        size: 20,
                        color: Colors.redAccent,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState:
                _favouritesExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: _buildFavouritesStrip(),
            secondChild: const SizedBox(width: double.infinity),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 180),
            crossFadeState: _searchExpanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Search a city, region or country...',
                      isDense: true,
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: 'Clear search',
                              onPressed: () => setState(() {
                                _searchQuery = '';
                                _clearPlaceSearch();
                              }),
                            ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    ),
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                      _onPlaceQueryChanged(value);
                    },
                  ),
                  if (_searchingPlaces || _placeResults.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _buildPlaceResults(),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (sortedTags.isNotEmpty)
                        DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _tagFilter,
                            hint: const Text('Tag', style: TextStyle(fontSize: 12)),
                            borderRadius: BorderRadius.circular(8),
                            // Fase 2, punto 12: colore di sfondo del menu e
                            // stile del testo espliciti, così le voci
                            // restano leggibili sia in tema chiaro che
                            // scuro (prima: testo nero su sfondo scuro).
                            dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                            style: TextStyle(
                              fontSize: 13,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                            // Show plenty of tags at once instead of a tiny box.
                            menuMaxHeight: 420,
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All tags'),
                              ),
                              ...sortedTags.map(
                                (t) => DropdownMenuItem<String?>(value: t, child: Text(t)),
                              ),
                            ],
                            onChanged: (value) => setState(() => _tagFilter = value),
                          ),
                        ),
                      if (_hasActiveFilters)
                        IconButton(
                          tooltip: 'Clear filters',
                          onPressed: () => setState(() {
                            _minRatingFilter = null;
                            _tagFilter = null;
                          }),
                          icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
          if (_pinnedLocation != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place, color: Colors.redAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pinnedLocation!.fullLabel,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '${_pinnedLocation!.mediaSet.length} memories here',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Show all places',
                      icon: const Icon(Icons.close, size: 16),
                      visualDensity: VisualDensity.compact,
                      onPressed: _clearPinnedLocation,
                    ),
                  ],
                ),
              ),
            ),
          const Divider(height: 16),
          Expanded(
            child: sections.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.landscape_outlined, size: 56, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            locations.isEmpty
                                ? 'No memories saved yet.\nTap the "+" button or right-click the map to get started!'
                                : 'No memory matches your search.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _sidebarScrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    itemCount: sections.length,
                    itemBuilder: (context, index) {
                      final entry = sections[index];
                      return _buildLocationSection(entry.key, entry.value);
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const MediaCollectionView(),
                  ),
                );
              },
              icon: const Icon(Icons.grid_view_rounded, size: 18),
              label: const Text('Open the full gallery'),
            ),
          ),
        ],
      ),
    );
  }

  /// The "Favorites" side panel from Fase 2, punto 12: a horizontal
  /// strip of the traveller's liked pictures, minimised behind the
  /// heart button above and only built while it's expanded. Pulls from
  /// ALL locations (not just the currently visible My Work / General
  /// World subset) so it always matches what the full Favourites
  /// screen would show.
  Widget _buildFavouritesStrip() {
    final social = context.watch<SocialController>();
    final allLocations = context.watch<LocationManagingController>().locations;

    if (supabase.auth.currentUser == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          'Sign in to save and see your favourites here.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      );
    }

    final favourites = <MapEntry<Media, Location>>[];
    for (final location in allLocations) {
      for (final media in location.mediaSet) {
        if (social.isFavourite(media.id)) {
          favourites.add(MapEntry(media, location));
        }
      }
    }

    if (favourites.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          "No favourites yet — tap the heart on a picture to save it here.",
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: favourites.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final media = favourites[index].key;
                final location = favourites[index].value;
                final url = media.publicUrl;
                final bytes = media.memoryBytes;

                return Tooltip(
                  message: location.fullLabel,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PreviewView(media: media, location: location),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: (bytes != null && bytes.isNotEmpty)
                            ? Image.memory(bytes, fit: BoxFit.cover)
                            : (url != null && url.isNotEmpty)
                                ? Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                      child: const Icon(Icons.image_outlined),
                                    ),
                                  )
                                : Container(
                                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                    child: const Icon(Icons.image_outlined),
                                  ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const FavouritesView()),
                );
                if (mounted) setState(() {});
              },
              child: Text('See all ${favourites.length}'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationSection(Location location, List<Media> media) {
    final key = _sectionKeys.putIfAbsent(location.id, () => GlobalKey());
    final isSelected = _selectedLocationId == location.id;

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: isSelected
          ? BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary,
                width: 1.5,
              ),
              color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.15),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Builder(builder: (context) {
              final social = context.watch<SocialController>();
              final canAddHere = canManageLocation(location, social);
              final canDeleteHere = canManageLocation(location, social, forDelete: true);

              return Row(
                children: [
                  Expanded(
                    child: Text(
                      location.fullLabel,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  // Adding pictures to someone else's pin isn't offered at
                  // all: pins are personal, only their own owner may add
                  // to them (Supabase rejects it too, as a second line of
                  // defence).
                  if (canAddHere)
                    IconButton(
                      tooltip: 'Add pictures to this place',
                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _addPhotosToExistingLocation(location),
                    ),
                  if (canDeleteHere)
                    IconButton(
                      tooltip: 'Delete place',
                      icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _confirmDeleteLocation(location),
                    ),
                ],
              );
            }),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: _sidebarExpanded ? 5 : 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1,
              ),
              itemCount: media.length,
              itemBuilder: (context, index) {
                final item = media[index];
                return MediaTile(
                  media: item,
                  isSelected: false,
                  isSelecting: false,
                  onSelectionChanged: () {},
                  onAuthorTap: (userId) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => UserProfileView(userId: userId),
                      ),
                    );
                  },
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PreviewView(
                          media: item,
                          location: location,
                        ),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _closeDrawerIfOpen() {
    final state = _scaffoldKey.currentState;
    if (state != null && state.isDrawerOpen) {
      state.closeDrawer();
    }
  }

  /// The app's whole main menu, in one place: same destinations shown as
  /// a collapsible sidebar on wide screens and as a Drawer on phones, so
  /// the two can never drift out of sync with each other.
  List<AppNavDestination> _buildNavDestinations(
    BuildContext context, {
    required SocialController social,
  }) {
    final signedIn = supabase.auth.currentUser != null;

    return [
      AppNavDestination(
        icon: Icons.map_outlined,
        label: 'Locations',
        selected: true,
        onTap: _closeDrawerIfOpen,
      ),
      AppNavDestination(
        icon: Icons.grid_view_rounded,
        label: 'All photos',
        onTap: () {
          _closeDrawerIfOpen();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MediaCollectionView()),
          );
        },
      ),
      AppNavDestination(
        icon: Icons.favorite_border,
        label: 'Favourites',
        onTap: () async {
          _closeDrawerIfOpen();
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FavouritesView()),
          );
          if (mounted) setState(() {});
        },
      ),
      AppNavDestination(
        icon: Icons.collections_bookmark_outlined,
        label: 'My work',
        onTap: () async {
          _closeDrawerIfOpen();
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyMemoriesView()),
          );
          if (mounted) setState(() {});
        },
      ),
      AppNavDestination(
        icon: Icons.travel_explore,
        label: 'People',
        onTap: () {
          _closeDrawerIfOpen();
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const UserSearchView()),
          );
        },
      ),
      AppNavDestination(
        icon: Icons.mail_outline,
        label: 'Messages',
        badgeCount: social.unreadMailboxCount,
        onTap: () async {
          _closeDrawerIfOpen();
          if (!await ensureLoggedIn(context)) return;
          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MailboxView()),
          );
          if (mounted) setState(() {});
        },
      ),
      AppNavDestination(
        icon: signedIn ? Icons.account_circle : Icons.login,
        label: signedIn ? 'My profile' : 'Sign in',
        onTap: () async {
          _closeDrawerIfOpen();
          if (signedIn) {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyAccountView()),
            );
            if (mounted) setState(() {});
          } else {
            await ensureLoggedIn(context);
            if (!mounted) return;
            await context.read<SocialController>().refreshForCurrentUser();
            if (mounted) setState(() {});
          }
        },
      ),
      AppNavDestination(
        icon: Icons.info_outline,
        label: 'About',
        onTap: () {
          _closeDrawerIfOpen();
          showAboutCreditsDialog(context);
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocationManagingController>();
    final social = context.watch<SocialController>();
    // "My Work" / "General World" — already filtered (and, inside the
    // public world, further narrowed to one MediaCategory when the
    // person picked one in the bottom bar).
    final locations = controller.visibleLocations;
    final isMoving = _locationBeingMoved != null;
    final isMobile = MediaQuery.of(context).size.width < 720;

    final navDestinations = _buildNavDestinations(context, social: social);

    return Scaffold(
      key: _scaffoldKey,
      // On a phone-sized screen the whole menu lives in this Drawer,
      // opened with the hamburger button below — same destinations,
      // same order, as the desktop sidebar.
      drawer: isMobile ? AppNavDrawer(destinations: navDestinations) : null,
      appBar: AppBar(
        leading: isMobile
            ? Builder(
                builder: (context) => IconButton(
                  tooltip: 'Menu',
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.public, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Text('World Traveller', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          if (isMobile)
            IconButton(
              tooltip: 'Side gallery',
              icon: Icon(_sidebarVisibleOnMobile ? Icons.map_outlined : Icons.photo_library_outlined),
              onPressed: () => setState(() => _sidebarVisibleOnMobile = !_sidebarVisibleOnMobile),
            ),
        ],
      ),
      // The single most important action on this screen, always visible,
      // always labelled — no guessing what the icon means.
      floatingActionButton: FloatingActionButton.extended(
        tooltip: 'Add photos to the map',
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Add photos'),
        onPressed: () async {
          if (!await ensureLoggedIn(context)) return;
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const AddMediaView(),
            ),
          );
        },
      ),
      body: isMobile && _sidebarVisibleOnMobile
          ? _buildSidebar(locations)
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isMobile)
                  AppNavSidebar(
                    destinations: navDestinations,
                    expanded: _navExpanded,
                    onToggleExpanded: () => setState(() => _navExpanded = !_navExpanded),
                  ),
                if (!isMobile)
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Never grow wider than the window itself, otherwise
                      // the map would be squeezed out of existence.
                      final maxWidth = MediaQuery.of(context).size.width * 0.72;
                      final width = _sidebarExpanded
                          ? (_kSidebarExpandedWidth < maxWidth
                              ? _kSidebarExpandedWidth
                              : maxWidth)
                          : _kSidebarWidth;

                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOut,
                            width: width,
                            child: _buildSidebar(locations),
                          ),
                          Positioned(
                            top: 0,
                            bottom: 0,
                            right: -20,
                            child: Center(
                              child: Tooltip(
                                message: _sidebarExpanded
                                    ? 'Shrink the panel'
                                    : 'Expand the panel',
                                child: Material(
                                  // Filled with the accent colour so the
                                  // handle is impossible to miss.
                                  color: Theme.of(context).colorScheme.primary,
                                  elevation: 4,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(22),
                                  ),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(22),
                                    onTap: () => setState(
                                      () => _sidebarExpanded = !_sidebarExpanded,
                                    ),
                                    child: SizedBox(
                                      width: 40,
                                      height: 96,
                                      child: Center(
                                        child: AnimatedRotation(
                                          duration: const Duration(milliseconds: 200),
                                          turns: _sidebarExpanded ? 0.5 : 0,
                                          child: Icon(
                                            Icons.chevron_right,
                                            size: 30,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onPrimary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                Expanded(
                  child: Stack(
                    children: [
                      Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _handlePointerDown,
                        child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: const LatLng(41.9028, 12.4964),
                          initialZoom: 5,
                          // Double-click selects a country instead of zooming.
                          interactionOptions: InteractionOptions(
                            flags: InteractiveFlag.all & ~InteractiveFlag.doubleTapZoom,
                          ),
                          onTap: _handleMapTap,
                          onSecondaryTap: _handleMapSecondaryTap,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.worldtraveller.app',
                          ),
                          if (_selectedCountry != null)
                            PolygonLayer(
                              polygons: [
                                for (final poly in _selectedCountry!.polygons)
                                  Polygon(
                                    points: poly.outer,
                                    holePointsList: poly.holes,
                                    color: Colors.blue.withValues(alpha: 0.35),
                                    borderColor: Colors.blue.shade800,
                                    borderStrokeWidth: 2,
                                  ),
                              ],
                            ),
                          MarkerLayer(
                            markers: [
                              ...locations.map((location) {
                                final isSelected = _selectedLocationId == location.id;

                                return Marker(
                                  point: LatLng(location.latitude, location.longitude),
                                  width: isSelected ? 58 : 44,
                                  height: isSelected ? 58 : 44,
                                  child: _LocationMarker(
                                    selected: isSelected,
                                    isCountry: location.isCountryLevel,
                                    onTap: () => _focusLocation(location),
                                    onSecondaryTapDown: (globalPosition) {
                                      _showPinContextMenu(globalPosition, location);
                                    },
                                  ),
                                );
                              }),
                              if (_pendingLocation != null)
                                Marker(
                                  point: _pendingLocation!,
                                  width: 60,
                                  height: 60,
                                  child: _preparingNewMemory
                                      // Fase 2, punto 11: barra/anello di
                                      // caricamento sovrapposto alla puntina
                                      // stessa, invece del solo box in alto.
                                      ? const _LoadingPinOverlay()
                                      : _PendingLocationMarker(
                                          onTap: () {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Press and hold to add a picture here, '
                                                  'or tap somewhere else to move it.',
                                                ),
                                              ),
                                            );
                                          },
                                          onLongPress: _confirmPendingLocation,
                                        ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      ),

                      if (controller.isLoading)
                        const Positioned(
                          top: 16,
                          right: 16,
                          child: Card(
                            child: Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(width: 10),
                                  Text('Syncing with the cloud...', style: TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),

                      if (_pendingLocation != null && !isMoving)
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          // Fase 2, punto 11: testo "tieni premuto" reso più
                          // evidente — colore acceso, icona animata, testo
                          // più grande, invece del banner grigio discreto.
                          child: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(14),
                            color: Colors.deepOrange,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(
                                children: [
                                  const _PulsingHoldIcon(),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Text(
                                      'Press and hold the marker to add a picture here',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _cancelPendingLocation,
                                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                                    child: const Text('Cancel'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      if (_loadingCountry)
                        Positioned(
                          top: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(20),
                              color: Theme.of(context).colorScheme.primaryContainer,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 10),
                                    Text('Selecting country...', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      if (_selectedCountry != null)
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Center(
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(20),
                              color: Theme.of(context).colorScheme.surface,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.flag, color: Colors.blue.shade700, size: 20),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        _selectedCountry!.place.title,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    FilledButton.icon(
                                      onPressed: _addMemoryToCountry,
                                      icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                                      label: const Text('Add memory to this country'),
                                    ),
                                    IconButton(
                                      tooltip: 'Deselect',
                                      icon: const Icon(Icons.close, size: 18),
                                      onPressed: () => setState(() => _selectedCountry = null),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      if (_preparingNewMemory)
                        Positioned(
                          top: 16,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(20),
                              color: Theme.of(context).colorScheme.primaryContainer,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                    SizedBox(width: 10),
                                    Text('One moment...', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                      if (isMoving)
                        Positioned(
                          top: 16,
                          left: 16,
                          right: 16,
                          child: Material(
                            elevation: 4,
                            borderRadius: BorderRadius.circular(12),
                            color: Theme.of(context).colorScheme.primaryContainer,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  const Icon(Icons.open_with),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Tap anywhere on the map to move '
                                      '"${_locationBeingMoved!.city}".',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () => setState(() => _locationBeingMoved = null),
                                    child: const Text('Cancel'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      Positioned(
                        left: 16,
                        bottom: 30,
                        child: FloatingActionButton.extended(
                          heroTag: 'add_memory_btn',
                          tooltip: 'Add a memory',
                          onPressed: () async {
                            if (!await ensureLoggedIn(context)) return;
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AddMediaView(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.add_location_alt_outlined),
                          label: const Text('Add'),
                        ),
                      ),

                      Positioned(
                        right: 16,
                        bottom: 30,
                        child: Column(
                          children: [
                            FloatingActionButton.small(
                              heroTag: 'zoom_in_btn',
                              onPressed: () {
                                _mapController.move(
                                  _mapController.camera.center,
                                  _mapController.camera.zoom + 1,
                                );
                              },
                              child: const Icon(Icons.add),
                            ),
                            const SizedBox(height: 8),
                            FloatingActionButton.small(
                              heroTag: 'zoom_out_btn',
                              onPressed: () {
                                _mapController.move(
                                  _mapController.camera.center,
                                  _mapController.camera.zoom - 1,
                                );
                              },
                              child: const Icon(Icons.remove),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      bottomNavigationBar: _buildWorldToggleBar(controller),
    );
  }

  // ---------------------------------------------------------------------
  // "My Work" / "General World" toggle
  // ---------------------------------------------------------------------

  /// The big, always-visible switch at the bottom of the app (brief point
  /// 5-6): "My Work" (private, only the signed-in traveller's own
  /// pictures) vs "General World" (the public feed). Inside the public
  /// world, a second row lets the person narrow it down further to
  /// "Viaggi personali" or "Lavori/Portfolio".
  Widget _buildWorldToggleBar(LocationManagingController controller) {
    final theme = Theme.of(context);
    final scope = controller.worldScope;

    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _WorldToggleButton(
                      label: 'My Work',
                      icon: Icons.lock_outline,
                      selected: scope == WorldScope.myWork,
                      onTap: () => controller.setWorldScope(WorldScope.myWork),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _WorldToggleButton(
                      label: 'General World',
                      icon: Icons.public,
                      selected: scope == WorldScope.generalWorld,
                      onTap: () => controller.setWorldScope(WorldScope.generalWorld),
                    ),
                  ),
                ],
              ),
              if (scope == WorldScope.generalWorld) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('All'),
                        selected: controller.categoryFilter == null,
                        onSelected: (_) => controller.setCategoryFilter(null),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Personal trips'),
                        selected: controller.categoryFilter == MediaCategory.personalTrip,
                        onSelected: (_) =>
                            controller.setCategoryFilter(MediaCategory.personalTrip),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ChoiceChip(
                        label: const Text('Work / Portfolio'),
                        selected: controller.categoryFilter == MediaCategory.workPortfolio,
                        onSelected: (_) =>
                            controller.setCategoryFilter(MediaCategory.workPortfolio),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One half of the bottom toggle. A plain, unmissable pill: filled and
/// coloured when active, outlined when not.
class _WorldToggleButton extends StatelessWidget {
  const _WorldToggleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: selected ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: selected ? theme.colorScheme.onPrimary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pulsing "hold" glyph shown next to the "press and hold" banner
/// so the call to action reads as more than plain grey text.
class _PulsingHoldIcon extends StatefulWidget {
  const _PulsingHoldIcon();

  @override
  State<_PulsingHoldIcon> createState() => _PulsingHoldIconState();
}

class _PulsingHoldIconState extends State<_PulsingHoldIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween(begin: 0.85, end: 1.15).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: const Icon(Icons.touch_app, color: Colors.white, size: 26),
    );
  }
}

/// Loading ring drawn directly over the pending pin while the new memory
/// is being saved, so the feedback sits exactly where the person's
/// attention already is instead of only in a banner elsewhere.
class _LoadingPinOverlay extends StatelessWidget {
  const _LoadingPinOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        const SizedBox(
          width: 54,
          height: 54,
          child: CircularProgressIndicator(strokeWidth: 3.5, color: Colors.deepOrange),
        ),
        Icon(Icons.location_on, color: Colors.deepOrange.shade700, size: 24),
      ],
    );
  }
}

class _PendingLocationMarker extends StatefulWidget {
  const _PendingLocationMarker({
    required this.onTap,
    required this.onLongPress,
  });

  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<_PendingLocationMarker> createState() => _PendingLocationMarkerState();
}

class _PendingLocationMarkerState extends State<_PendingLocationMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Tooltip(
        message: 'Press and hold to add a picture here',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: Stack(
            alignment: Alignment.center,
            children: [
              ScaleTransition(
                scale: Tween(begin: 0.9, end: 1.3).animate(
                  CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
                ),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.deepOrange.withValues(alpha: 0.25),
                  ),
                ),
              ),
              const Icon(
                Icons.add_location_alt,
                color: Colors.deepOrange,
                size: 36,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LocationMarker extends StatefulWidget {
  const _LocationMarker({
    required this.selected,
    required this.isCountry,
    required this.onTap,
    required this.onSecondaryTapDown,
  });

  final bool selected;

  /// Country-level memories get a blue pin, city ones stay black/orange.
  final bool isCountry;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onSecondaryTapDown;

  @override
  State<_LocationMarker> createState() => _LocationMarkerState();
}

class _LocationMarkerState extends State<_LocationMarker> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selected || _hovered;

    // Idle pins are black so they stand out against the map tiles; the
    // active one turns orange. A white outline underneath keeps both
    // readable over dark satellite-like areas.
    final color = widget.isCountry
        ? (active ? Colors.lightBlue.shade400 : Colors.blue.shade700)
        : (active ? Colors.deepOrange : Colors.black);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Tooltip(
        // Fase 2, punto 10: hover tooltip su ogni pulsante/puntina.
        message: 'View photos here',
        waitDuration: const Duration(milliseconds: 400),
        child: GestureDetector(
          onTap: widget.onTap,
          onSecondaryTapDown: (details) => widget.onSecondaryTapDown(details.globalPosition),
          onLongPressStart: (details) => widget.onSecondaryTapDown(details.globalPosition),
          child: AnimatedScale(
            duration: const Duration(milliseconds: 160),
            scale: active ? 1.25 : 1,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.location_on,
                  color: Colors.white,
                  size: active ? 48 : 40,
                ),
                Icon(
                  Icons.location_on,
                  color: color,
                  size: active ? 44 : 36,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
