import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:world_traveller_project/enums/media_visibility.dart';
import 'package:world_traveller_project/models/location.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/services/supabase_storage_service.dart';

/// Thrown by [LocationManagingController.removeItem] when the caller is
/// not allowed to delete a picture: not its owner, and not an admin.
class MediaPermissionDeniedException implements Exception {
  final String message;
  const MediaPermissionDeniedException([
    this.message = 'You can only delete pictures you uploaded yourself.',
  ]);

  @override
  String toString() => message;
}

class LocationManagingController extends ChangeNotifier {
  Location? _location;
  final SupabaseStorageService _storageService = SupabaseStorageService();
  List<Location> _locations = [];
  bool _isLoading = false;

  /// "My Work" vs "General World" — the big toggle at the bottom of the
  /// app. Starts on the public feed, which is what a new visitor expects
  /// to see first.
  WorldScope _worldScope = WorldScope.generalWorld;

  /// Inside the public world, an optional extra filter between a
  /// traveller's personal trips and their work/portfolio content. Null
  /// means "show both".
  MediaCategory? _categoryFilter;

  // getters
  Location? get location => _location;
  List<Location> get locations => _locations;
  bool get isLoading => _isLoading;
  SupabaseStorageService get storageService => _storageService;
  WorldScope get worldScope => _worldScope;
  MediaCategory? get categoryFilter => _categoryFilter;

  /// Switches between "My Work" and "General World". This is the whole
  /// logic behind the big bottom toggle: nothing is re-fetched from the
  /// server, the same in-memory list of locations is simply re-filtered
  /// through [visibleLocations].
  void setWorldScope(WorldScope scope) {
    if (_worldScope == scope) return;
    _worldScope = scope;
    if (scope == WorldScope.myWork) {
      // The category split ("Viaggi personali" / "Lavori-Portfolio") only
      // exists inside the public world.
      _categoryFilter = null;
    }
    notifyListeners();
  }

  void setCategoryFilter(MediaCategory? category) {
    if (_categoryFilter == category) return;
    _categoryFilter = category;
    notifyListeners();
  }

  /// The actual "Switch" query logic requested in the brief:
  ///
  /// * **My Work** — only pictures the signed-in user uploaded, no matter
  ///   their [MediaVisibility] (an unpublished picture still belongs to
  ///   its owner's private library). Nobody else's pictures are ever
  ///   included here.
  /// * **General World** — every picture anyone has marked
  ///   [MediaVisibility.public], optionally narrowed down to one
  ///   [MediaCategory] ("Viaggi personali" vs "Lavori/Portfolio").
  ///
  /// Locations (map pins) are shared between users, so a pin can hold a
  /// mix of pictures that do and don't belong in the current world; this
  /// returns copies of each [Location] carrying only the matching
  /// pictures, and drops any pin left with none.
  List<Location> get visibleLocations {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final result = <Location>[];

    for (final loc in _locations) {
      final filtered = loc.mediaSet.where((media) => _mediaMatchesCurrentScope(
            media,
            currentUserId: currentUserId,
          ));

      if (filtered.isNotEmpty) {
        result.add(loc.withMedia(filtered));
      }
    }

    return result;
  }

  bool _mediaMatchesCurrentScope(Media media, {required String? currentUserId}) {
    if (_worldScope == WorldScope.myWork) {
      return currentUserId != null && media.userId == currentUserId;
    }

    if (!media.visibility.isPublic) return false;
    if (_categoryFilter != null && media.category != _categoryFilter) return false;
    return true;
  }

  // methods
  void createPlace({
    required String city,
    required String country,
    String? region,
    String? cityLocal,
    String? regionLocal,
    String? countryLocal,
    required double latitude,
    required double longitude,
  }) {
    _location = Location(
      userId: Supabase.instance.client.auth.currentUser?.id,
      city: city,
      country: country,
      region: region,
      cityLocal: cityLocal,
      regionLocal: regionLocal,
      countryLocal: countryLocal,
      latitude: latitude,
      longitude: longitude,
    );

    notifyListeners();
  }

  void addMedia(Media media) {
    _location?.addMedia(media);
    notifyListeners();
  }

  Future<void> updateMedia(Media updatedMedia, {String? oldFilePath}) async {
    for (var loc in _locations) {
      final hasMedia = loc.mediaSet.any((m) => m.id == updatedMedia.id);
      if (hasMedia) {
        loc.updateMedia(updatedMedia);
        await _storageService.saveLocation(loc);
        break;
      }
    }
    notifyListeners();
  }

  Future<Location?> findLocationForMedia(Media media) async {
    if (_locations.isEmpty) {
      await loadLocationsFromJSON();
    }
    for (var loc in _locations) {
      if (loc.mediaSet.any((m) => m.id == media.id || m.filePath == media.filePath)) {
        return loc;
      }
    }
    return null;
  }

  Future<List<Location>> loadLocationsFromJSON() async {
    _isLoading = true;
    notifyListeners();

    try {
      final loaded = await _storageService.loadLocations();
      _locations = loaded;
    } catch (e) {
      debugPrint('Could not load places: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
    return _locations;
  }

  Future<void> saveLocationToJSON() async {
    if (_location == null) return;

    final index = _locations.indexWhere((loc) => loc.id == _location!.id);
    if (index != -1) {
      _locations[index] = _location!;
    } else {
      _locations.add(_location!);
    }

    await _storageService.saveLocation(_location!);
    notifyListeners();
  }

  /// Deletes a picture, enforcing the rule from the brief: only the
  /// picture's own uploader, or an administrator, may delete it. Anyone
  /// else gets [MediaPermissionDeniedException] and nothing happens.
  ///
  /// This client-side check is a first line of defence for a snappy UI;
  /// the same rule is also enforced by the database's Row Level Security
  /// policies (see SUPABASE_SETUP_PHASE1.sql), so it cannot be bypassed
  /// even if this check were skipped.
  Future<void> removeItem(Media media, {required bool requestedByAdmin}) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwner = currentUserId != null && media.userId == currentUserId;

    if (!isOwner && !requestedByAdmin) {
      throw const MediaPermissionDeniedException();
    }

    Location? parentLoc;
    for (final loc in _locations) {
      if (loc.mediaSet.any((m) => m.id == media.id)) {
        parentLoc = loc;
        break;
      }
    }

    if (parentLoc != null) {
      try {
        await _storageService.deleteMedia(media, parentLoc);
      } catch (e) {
        // The database refused (or the network failed): nothing was
        // deleted, so tell the user instead of silently pretending.
        final reason = e.toString().replaceFirst('Exception: ', '');
        throw MediaPermissionDeniedException('Could not delete this picture. $reason');
      }
      if (parentLoc.mediaSet.isEmpty) {
        // Already validated above: pass the same permission along so an
        // admin clearing out someone else's last public picture doesn't
        // get blocked again here.
        await deleteLocation(parentLoc, requestedByAdmin: requestedByAdmin);
      } else {
        notifyListeners();
      }
    }
  }

  /// Permanently deletes a place and every picture in it. Only the pin's
  /// own owner may do this; an admin may too (to clear an offending pin
  /// from the public "General World" feed). Anyone else is refused.
  Future<void> deleteLocation(Location location, {bool requestedByAdmin = false}) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwner = currentUserId != null &&
        location.userId != null &&
        location.userId == currentUserId;

    if (!isOwner && !requestedByAdmin) {
      throw const MediaPermissionDeniedException(
        'You can only delete places you created yourself.',
      );
    }

    _locations.removeWhere((loc) => loc.id == location.id);
    notifyListeners();
    await _storageService.deleteLocation(location);
  }

  /// Moves a pin without touching the pictures attached to it. Only the
  /// pin's own owner may move it.
  Future<void> moveLocation(
    Location location,
    double newLatitude,
    double newLongitude,
  ) async {
    final index = _locations.indexWhere((loc) => loc.id == location.id);
    if (index == -1) return;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwner = currentUserId != null &&
        location.userId != null &&
        location.userId == currentUserId;
    if (!isOwner) {
      throw const MediaPermissionDeniedException(
        'You can only move places you created yourself.',
      );
    }

    final moved = Location(
      id: location.id,
      userId: location.userId,
      city: location.city,
      country: location.country,
      region: location.region,
      cityLocal: location.cityLocal,
      regionLocal: location.regionLocal,
      countryLocal: location.countryLocal,
      latitude: newLatitude,
      longitude: newLongitude,
      mediaSet: _locations[index].mediaSet,
    );

    _locations[index] = moved;
    notifyListeners();
    await _storageService.saveLocation(moved);
  }

  /// Adds a picture to an existing place and syncs it.
  Future<void> addMediaToLocation(Location location, Media media) async {
    final index = _locations.indexWhere((loc) => loc.id == location.id);

    if (index == -1) {
      location.addMedia(media);
      _locations.add(location);
    } else {
      _locations[index].addMedia(media);
    }

    notifyListeners();
    await _storageService.saveLocation(index != -1 ? _locations[index] : location);
  }

  /// Uploads bytes to Supabase and builds the matching Media object.
  Future<Media> uploadAndCreateMedia({
    required Location location,
    required String fileName,
    required Uint8List rawBytes,
    required MediaType type,
  }) async {
    final processedBytes = await _storageService.prepareImageBytes(rawBytes, fileName);

    final uploadResult = await _storageService.uploadMediaFile(
      bytes: processedBytes,
      fileName: fileName,
      locationId: location.id,
      type: type,
    );

    final media = Media(
      filePath: uploadResult.storagePath,
      type: type,
      grading: 0,
      fileName: fileName,
      lastModification: DateTime.now(),
      tags: const [],
      remoteUrl: uploadResult.publicUrl,
      memoryBytes: processedBytes,
      // Remember who uploaded it, so "My memories" and the edit/delete
      // permissions work straight away without a reload.
      userId: Supabase.instance.client.auth.currentUser?.id,
    );

    return media;
  }
}
