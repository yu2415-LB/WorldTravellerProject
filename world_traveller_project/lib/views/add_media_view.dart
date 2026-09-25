import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/components/custom_map.dart';
import 'package:world_traveller_project/components/photo_drop_zone.dart';
import 'package:world_traveller_project/models/location.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/providers/location_managing_controller.dart';
import 'package:world_traveller_project/services/geocoding_service.dart';
import 'package:world_traveller_project/services/image_validation_service.dart';
import 'package:world_traveller_project/services/moderation_service.dart';
import 'package:world_traveller_project/views/edit_media_view.dart';
// ignore: unused_import
import 'package:world_traveller_project/services/local_media_service.dart';

class _PickedFileItem {
  final XFile file;

  /// Bytes ready to upload (scaled to at most 2048 px when needed).
  final Uint8List bytes;

  /// Name matching [bytes]' real format (see PreparedImage.fileName).
  final String fileName;
  final bool wasResized;

  _PickedFileItem({
    required this.file,
    required this.bytes,
    required this.fileName,
    this.wasResized = false,
  });
}

class AddMediaView extends StatefulWidget {
  final LatLng? initialPosition;

  /// When set (e.g. after double-clicking a country on the map) the place is
  /// already known: the form opens filled in, at country level.
  final PlaceResult? initialPlace;

  /// When set, the new picture is added to a pin that already exists.
  /// The place cannot be changed: step 1 just shows it on the map and asks
  /// for confirmation, exactly like when creating a brand new memory.
  final Location? existingLocation;

  const AddMediaView({
    super.key,
    this.initialPosition,
    this.initialPlace,
    this.existingLocation,
  });

  @override
  State<AddMediaView> createState() => _AddMediaViewState();
}

class _AddMediaViewState extends State<AddMediaView> {
  final TextEditingController _cityController = TextEditingController();
  final TextEditingController _countryController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final ModerationService _moderationService = ModerationService();

  final List<_PickedFileItem> _pickedMedia = [];

  /// Files that were refused, already worded for the traveller.
  final List<String> _fileErrors = [];
  bool _preparing = false;

  // Upload progress shown while saving.
  int _uploadDone = 0;
  int _uploadTotal = 0;

  LatLng? _pickedPosition;
  bool _saving = false;
  int _step = 0;

  /// When true, the new pictures are saved only on this machine and
  /// never uploaded to Supabase. Only shown on desktop / mobile.
  bool _saveLocalOnly = false;

  // Place autocomplete (cities, regions, countries)
  Timer? _debounce;
  List<PlaceResult> _citySuggestions = [];
  bool _searchingCities = false;
  bool _suppressNextCityChange = false;
  int _searchRequestId = 0;

  /// Bilingual details of the chosen place (region + local-language names).
  /// Saved together with the memory.
  PlaceResult? _selectedPlace;

  /// Only set when the place was picked from the dropdown, so the map zooms
  /// to fit a whole region/country. Tapping the map clears it.
  PlaceResult? _focusPlace;

  /// True when we are adding to a pin that already exists.
  bool get _isExistingPlace => widget.existingLocation != null;

  @override
  void initState() {
    super.initState();

    final existing = widget.existingLocation;
    if (existing != null) {
      _pickedPosition = LatLng(existing.latitude, existing.longitude);
      _cityController.text = existing.city;
      _countryController.text = existing.country;
      return;
    }

    final preset = widget.initialPlace;
    if (preset != null) {
      _pickedPosition = LatLng(preset.lat, preset.lon);
      _cityController.text = preset.city;
      _countryController.text = preset.country;
      _selectedPlace = preset;
      _focusPlace = preset;
      return;
    }

    if (widget.initialPosition != null) {
      _pickedPosition = widget.initialPosition;
      _reverseGeocodeInitialPosition(widget.initialPosition!);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _cityController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  Future<void> _reverseGeocodeInitialPosition(LatLng position) async {
    try {
      final place = await GeocodingService.instance.reverse(
        position.latitude,
        position.longitude,
      );

      if (place == null || !mounted) return;

      setState(() {
        _selectedPlace = place;
        if (place.city.isNotEmpty) _cityController.text = place.city;
        if (place.country.isNotEmpty) _countryController.text = place.country;
      });
    } catch (_) {}
  }

  void _onCityQueryChanged(String query) {
    if (_suppressNextCityChange) {
      _suppressNextCityChange = false;
      return;
    }

    _debounce?.cancel();

    if (query.trim().length < 2) {
      setState(() => _citySuggestions = []);
      return;
    }

    _debounce = Timer(
      const Duration(milliseconds: 350),
      () => _searchCities(query.trim()),
    );
  }

  Future<void> _searchCities(String query) async {
    final requestId = ++_searchRequestId;
    setState(() => _searchingCities = true);

    try {
      final results = await GeocodingService.instance.search(query);

      // Ignore answers to a query the user has already typed over.
      if (!mounted || requestId != _searchRequestId) return;

      setState(() {
        _citySuggestions = results;
        _searchingCities = false;
      });
    } catch (_) {
      if (mounted && requestId == _searchRequestId) {
        setState(() => _searchingCities = false);
      }
    }
  }

  Future<void> _selectSuggestion(PlaceResult suggestion) async {
    _suppressNextCityChange = true;

    setState(() {
      _cityController.text = suggestion.city;
      _countryController.text = suggestion.country;
      _pickedPosition = LatLng(suggestion.lat, suggestion.lon);
      _selectedPlace = suggestion;
      _focusPlace = suggestion;
      _citySuggestions = [];
    });

    FocusScope.of(context).unfocus();

    // Fetch the local-language names of region / country in the background.
    final resolved = await GeocodingService.instance.resolveLocal(suggestion);
    if (!mounted || !identical(_selectedPlace, suggestion)) return;
    setState(() => _selectedPlace = resolved);
  }

  void _onLocationSelected(LatLng position, String? city, String? country) {
    // The place is fixed when adding to an existing pin.
    if (_isExistingPlace) return;

    _suppressNextCityChange = true;

    setState(() {
      _pickedPosition = position;
      _citySuggestions = [];
      _focusPlace = null;

      if (city?.isNotEmpty ?? false) {
        _cityController.text = city!;
      }

      if (country?.isNotEmpty ?? false) {
        _countryController.text = country!;
      }
    });
  }

  Future<void> _pickPhotos() async {
    final files = await _picker.pickMultiImage();
    if (!mounted || files.isEmpty) return;
    await _addFiles(files);
  }

  /// Shared by the file chooser and drag & drop: validates every file,
  /// scales big ones down to 2048 px and lists what was refused and why.
  Future<void> _addFiles(List<XFile> files) async {
    if (files.isEmpty || _saving) return;

    setState(() {
      _preparing = true;
      _fileErrors.clear();
    });

    for (final file in files) {
      try {
        final raw = await file.readAsBytes();
        final prepared =
            await ImageValidationService.instance.prepare(raw, file.name);
        if (!mounted) return;
        setState(() => _pickedMedia.add(_PickedFileItem(
              file: file,
              bytes: prepared.bytes,
              fileName: prepared.fileName,
              wasResized: prepared.wasResized,
            )));
      } on ImageValidationException catch (e) {
        if (!mounted) return;
        setState(() => _fileErrors.add('${file.name}: ${e.message}'));
      } catch (e) {
        debugPrint('Could not read ${file.name}: $e');
        if (!mounted) return;
        setState(() => _fileErrors.add('${file.name}: could not be read.'));
      }
    }

    if (mounted) setState(() => _preparing = false);
  }

  Future<void> _replacePhoto(int index) async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null || !mounted) return;

    try {
      final raw = await file.readAsBytes();
      final prepared =
          await ImageValidationService.instance.prepare(raw, file.name);
      if (!mounted) return;
      setState(() {
        _fileErrors.clear();
        _pickedMedia[index] = _PickedFileItem(
          file: file,
          bytes: prepared.bytes,
          fileName: prepared.fileName,
          wasResized: prepared.wasResized,
        );
      });
    } on ImageValidationException catch (e) {
      if (!mounted) return;
      setState(() => _fileErrors
        ..clear()
        ..add('${file.name}: ${e.message}'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _fileErrors
        ..clear()
        ..add('${file.name}: could not be read.'));
    }
  }

  void _nextStep() {
    if (_pickedPosition == null) {
      _message('Search for a city or tap the map to set the location');
      return;
    }

    if (_cityController.text.trim().isEmpty ||
        _countryController.text.trim().isEmpty) {
      _message('Enter both the city and the country');
      return;
    }

    setState(() => _step = 1);
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save() async {
    if (_pickedMedia.isEmpty) {
      _message('Add at least one picture');
      return;
    }

    setState(() => _saving = true);

    try {
      final controller = context.read<LocationManagingController>();
      final existing = widget.existingLocation;

      // Either reuse the pin we were given, or create a brand new one.
      final Location targetLocation;
      if (existing != null) {
        targetLocation = existing;
      } else {
        final cityText = _cityController.text.trim();
        final countryText = _countryController.text.trim();
        final place = _selectedPlace;

        // Use the bilingual data only while it still matches what is in the
        // text fields (the user may have edited them by hand afterwards).
        bool same(String a, String? b) =>
            b != null && a.trim().toLowerCase() == b.trim().toLowerCase();

        controller.createPlace(
          city: cityText,
          country: countryText,
          region: place?.region,
          cityLocal: (place != null && same(cityText, place.city)) ? place.cityLocal : null,
          regionLocal: place?.regionLocal,
          countryLocal:
              (place != null && same(countryText, place.country)) ? place.countryLocal : null,
          latitude: _pickedPosition!.latitude,
          longitude: _pickedPosition!.longitude,
        );
        targetLocation = controller.location!;
      }

      final items = <Media>[];
      _uploadTotal = _pickedMedia.length;
      _uploadDone = 0;

      for (final item in _pickedMedia) {
        // Future NSFW/AI filter hook (Phase 4, point 21) — a no-op
        // today, see ModerationService for what plugs in here later.
        final moderation = await _moderationService.checkImage(item.bytes);
        if (!moderation.allowed) {
          _message(moderation.reason ?? 'This picture cannot be uploaded.');
          continue;
        }

        final media = await controller.uploadAndCreateMedia(
          location: targetLocation,
          fileName: item.fileName,
          rawBytes: item.bytes,
          type: MediaType.image,
          localOnly: _saveLocalOnly,
        );
        items.add(media);

        if (existing != null) {
          await controller.addMediaToLocation(targetLocation, media);
        } else {
          controller.addMedia(media);
        }
        if (mounted) setState(() => _uploadDone++);
      }

      if (existing == null) {
        await controller.saveLocationToJSON();
      }

      if (!mounted) return;

      // Step 3: fill in the details of every picture that was just added.
      for (final item in items) {
        if (!mounted) break;
        await Navigator.push<bool>(
          context,
          MaterialPageRoute<bool>(
            builder: (_) => EditMediaView(media: item),
          ),
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (mounted) {
        _message('Could not save: $error');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocationStep = _step == 0;

    final title = _isExistingPlace
        ? (isLocationStep
            ? 'Add to this place \u00b7 1. Confirm'
            : 'Add to this place \u00b7 2. Pictures')
        : (isLocationStep
            ? 'New memory \u00b7 1. Location'
            : 'New memory \u00b7 2. Pictures');

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideScreen = constraints.maxWidth >= 780;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: isWideScreen
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _buildPanels(),
                  )
                : ListView(children: _buildPanels(vertical: true)),
          );
        },
      ),
    );
  }

  List<Widget> _buildPanels({bool vertical = false}) {
    final Widget leftPanel = _step == 0
        ? (vertical ? SizedBox(height: 420, child: _mapPanel()) : _mapPanel())
        : (vertical ? SizedBox(height: 420, child: _mediaPanel()) : _mediaPanel());

    final rightPanel =
        _step == 0 ? _locationInformationPanel() : _mediaInformationPanel();

    if (vertical) {
      return [leftPanel, const SizedBox(height: 20), rightPanel];
    }

    return [
      Expanded(flex: 6, child: leftPanel),
      const SizedBox(width: 24),
      Expanded(flex: 4, child: rightPanel),
    ];
  }

  Widget _mapPanel() {
    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: CustomMap(
        // Tapping the map must not move an existing pin.
        setMarkersAllowed: !_isExistingPlace,
        addButtonVisible: false,
        onLocationSelected: _onLocationSelected,
        onPlaceResolved: (place) {
          if (_isExistingPlace || place == null) return;
          setState(() => _selectedPlace = place);
        },
        focusPlace: _focusPlace,
        focusPosition: _pickedPosition,
        focusCity: _cityController.text.isEmpty ? null : _cityController.text,
        focusCountry:
            _countryController.text.isEmpty ? null : _countryController.text,
      ),
    );
  }

  Widget _locationInformationPanel() {
    // ---- Adding to a pin that already exists: just confirm the place. ----
    if (_isExistingPlace) {
      final theme = Theme.of(context);

      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Is this the right place?',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Your picture will be added to the pin shown on the map.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: theme.colorScheme.primary),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place, color: Colors.redAccent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_cityController.text}, ${_countryController.text}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${widget.existingLocation!.mediaSet.length} '
                            'memories already here',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton.icon(
                  onPressed: () => setState(() => _step = 1),
                  icon: const Icon(Icons.check),
                  label: const Text('Yes, continue to pictures',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ---- Brand new memory: pick the place. ----
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '1. Where was it taken?',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Search for a city, region or country (in English or in the local '
              'language), or tap directly on the map to drop the pin.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _cityController,
              onChanged: _onCityQueryChanged,
              decoration: InputDecoration(
                labelText: 'City, region or country',
                hintText: 'e.g. Rome / Roma, Crete, Washington, Toscana...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchingCities
                    ? const Padding(
                        padding: EdgeInsets.all(12.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            if (_citySuggestions.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 280),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _citySuggestions.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final suggestion = _citySuggestions[index];
                    return ListTile(
                      dense: true,
                      leading: Icon(_iconForKind(suggestion.kind)),
                      // "Rome (Roma)" / "Lazio, Italy (Italia)"
                      title: Text(suggestion.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: suggestion.subtitle.isEmpty
                          ? Text(_labelForKind(suggestion.kind))
                          : Text('${_labelForKind(suggestion.kind)} \u00b7 ${suggestion.subtitle}'),
                      onTap: () => _selectSuggestion(suggestion),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _countryController,
              decoration: InputDecoration(
                labelText: 'Country',
                prefixIcon: const Icon(Icons.flag_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _nextStep,
                icon: const Icon(Icons.arrow_forward),
                label: const Text('Continue to pictures',
                    style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForKind(PlaceKind kind) {
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

  String _labelForKind(PlaceKind kind) {
    switch (kind) {
      case PlaceKind.country:
        return 'Country';
      case PlaceKind.region:
        return 'Region';
      case PlaceKind.city:
        return 'City';
      case PlaceKind.other:
        return 'Place';
    }
  }

  Widget _mediaPanel() {
    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_fileErrors.isNotEmpty)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final e in _fileErrors)
                            Text(e,
                                style: TextStyle(
                                    color: theme.colorScheme.onErrorContainer)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => setState(_fileErrors.clear),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: PhotoDropZone(
                enabled: !_saving,
                busy: _preparing,
                onBrowse: _pickPhotos,
                onFilesDropped: _addFiles,
                child: _pickedMedia.isEmpty ? null : _photoGrid(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _photoGrid() {
    return GridView.builder(
      itemCount: _pickedMedia.length + 1,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 200,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        // Last tile: add more pictures.
        if (index == _pickedMedia.length) {
          return OutlinedButton.icon(
            onPressed: _saving || _preparing ? null : _pickPhotos,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add more'),
            style: OutlinedButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }

        final item = _pickedMedia[index];

        return Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(item.bytes, fit: BoxFit.cover),
              ),
            ),
            if (item.wasResized)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Scaled to 2048 px',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                ),
              ),
            Positioned(
              top: 6,
              right: 6,
              child: Row(
                children: [
                  IconButton.filledTonal(
                    tooltip: 'Replace',
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    onPressed: _saving ? null : () => _replacePhoto(index),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed:
                        _saving ? null : () => setState(() => _pickedMedia.removeAt(index)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _mediaInformationPanel() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '2. Choose your pictures',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${_cityController.text}, ${_countryController.text}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _pickPhotos,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Choose pictures'),
              ),
            ),
            const SizedBox(height: 16),
            if (_saving && _uploadTotal > 0) ...[
              LinearProgressIndicator(
                value: _uploadDone / _uploadTotal,
                minHeight: 8,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 6),
              Text('Uploading $_uploadDone of $_uploadTotal'),
              const SizedBox(height: 12),
            ],
            Text(
              '${_pickedMedia.length} picture(s) selected',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'After saving you will be asked for the title, rating, mood, '
              'story and tags of each picture.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),

            // Desktop / mobile only: let the user keep pictures off the
            // cloud entirely. Hidden on the web (nowhere to store them).
            if (LocalMediaService.instance.isAvailable) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.computer,
                      size: 20,
                      color: _saveLocalOnly
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade600,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Tieni solo su questo computer',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _saveLocalOnly
                                ? 'Le foto NON andranno sul cloud. Solo tu, '
                                    'solo su questo PC.'
                                : 'Spostale sul cloud per condividerle con gli '
                                    'altri viaggiatori.',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _saveLocalOnly,
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _saveLocalOnly = v),
                    ),
                  ],
                ),
              ),
            ],
            const Spacer(),
            TextButton.icon(
              onPressed: _saving ? null : () => setState(() => _step = 0),
              icon: const Icon(Icons.arrow_back),
              label: Text(_isExistingPlace ? 'Back' : 'Change location'),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload_outlined),
                label: Text(
                  _saving ? 'Saving...' : 'Save & continue',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
