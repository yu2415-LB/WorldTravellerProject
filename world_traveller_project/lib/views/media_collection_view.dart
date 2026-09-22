import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/components/media_tile.dart';
import 'package:world_traveller_project/models/location.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/providers/location_managing_controller.dart';
import 'package:world_traveller_project/providers/social_controller.dart';
import 'package:world_traveller_project/views/preview_view.dart';
import 'package:world_traveller_project/views/user_profile_view.dart';

class MediaCollectionView extends StatefulWidget {
  const MediaCollectionView({super.key});

  @override
  State<MediaCollectionView> createState() => _MediaCollectionViewState();
}

/// Which part of a place's name the person tapped, so each can be
/// filtered independently instead of only ever filtering by city.
enum _GeoFilterType { city, region, country }

class _MediaCollectionViewState extends State<MediaCollectionView> {
  String _searchQuery = '';
  double? _minRatingFilter;
  String? _tagFilter;

  // Fase 3, punto 17 (migliorato): città, regione e nazione sono ora tre
  // filtri indipendenti — prima cliccare il nome applicava solo un
  // filtro testuale sulla città. _geoFilterType/_geoFilterValue tengono
  // traccia di QUALE dei tre è attivo (uno alla volta, per restare
  // semplice da capire), separato dalla barra di ricerca libera.
  _GeoFilterType? _geoFilterType;
  String? _geoFilterValue;

  final TextEditingController _searchController = TextEditingController();

  bool get _hasActiveFilters =>
      _minRatingFilter != null || _tagFilter != null || _geoFilterType != null;

  void _setSearch(String value) {
    setState(() => _searchQuery = value);
    _searchController.text = value;
    _searchController.selection = TextSelection.collapsed(offset: value.length);
  }

  void _toggleGeoFilter(_GeoFilterType type, String? value) {
    if (value == null || value.trim().isEmpty) return;
    setState(() {
      if (_geoFilterType == type && _geoFilterValue == value) {
        // Tapping the same chip again clears it.
        _geoFilterType = null;
        _geoFilterValue = null;
      } else {
        _geoFilterType = type;
        _geoFilterValue = value;
      }
    });
  }

  void _clearGeoFilter() {
    setState(() {
      _geoFilterType = null;
      _geoFilterValue = null;
    });
  }

  bool _matchesGeoFilter(Location loc) {
    switch (_geoFilterType) {
      case null:
        return true;
      case _GeoFilterType.city:
        return loc.city == _geoFilterValue;
      case _GeoFilterType.region:
        return (loc.region ?? '') == _geoFilterValue;
      case _GeoFilterType.country:
        return loc.country == _geoFilterValue;
    }
  }

  String get _geoFilterLabel {
    switch (_geoFilterType) {
      case null:
        return '';
      case _GeoFilterType.city:
        return 'City';
      case _GeoFilterType.region:
        return 'Region';
      case _GeoFilterType.country:
        return 'Country';
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Look up who posted each picture, so every tile can show "@username".
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final locations = context.read<LocationManagingController>().visibleLocations;
      await context.read<SocialController>().resolveUsernames(
            locations.expand((loc) => loc.mediaSet),
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = Provider.of<LocationManagingController>(context);
    final locations = controller.visibleLocations;

    final Set<String> allTags = {};
    for (final loc in locations) {
      for (final m in loc.mediaSet) {
        allTags.addAll(m.tags);
      }
    }
    final sortedTags = allTags.toList()..sort();

    final Map<Location, List<Media>> groupedMedia = {};

    for (var loc in locations) {
      if (!_matchesGeoFilter(loc)) continue;

      // Improvement: also matches region and the local-language names
      // added in Phase 1 (before, only the English city/country were
      // ever checked here).
      final matchesQuery = _searchQuery.isEmpty || loc.matchesQuery(_searchQuery);

      final matchedList = loc.mediaSet.where((m) {
        final matchesSearch =
            matchesQuery || m.fileName.toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesRating = _minRatingFilter == null || m.grading >= _minRatingFilter!;
        final matchesTag = _tagFilter == null || m.tags.contains(_tagFilter);
        return matchesSearch && matchesRating && matchesTag;
      }).toList();

      if (matchedList.isNotEmpty) {
        groupedMedia[loc] = matchedList;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('All memories'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search by city, region, country or title...',
              leading: const Icon(Icons.search),
              trailing: _searchQuery.isNotEmpty
                  ? [
                      IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => _setSearch(''),
                      )
                    ]
                  : null,
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
            ),
          ),
          // The one geographic filter that's active right now, shown as
          // a removable chip so it stays visible even once the person
          // has scrolled past the location header they tapped.
          if (_geoFilterType != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: InputChip(
                  avatar: const Icon(Icons.place, size: 16, color: Colors.redAccent),
                  label: Text('$_geoFilterLabel: $_geoFilterValue'),
                  onDeleted: _clearGeoFilter,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...List.generate(5, (i) {
                      final threshold = (i + 1).toDouble();
                      final isSelected = _minRatingFilter == threshold;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: ChoiceChip(
                          avatar: const Icon(Icons.star, size: 14, color: Colors.amber),
                          label: Text('${threshold.toInt()}+'),
                          selected: isSelected,
                          onSelected: (_) => setState(
                            () => _minRatingFilter = isSelected ? null : threshold,
                          ),
                        ),
                      );
                    }),
                    if (sortedTags.isNotEmpty) ...[
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String?>(
                          value: _tagFilter,
                          hint: const Text('Tag'),
                          borderRadius: BorderRadius.circular(8),
                          // Fase 2, punto 12: colore del menu e del testo
                          // espliciti per restare leggibili in ogni tema.
                          dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                          // A tall menu: whoever opens it wants to browse.
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
                      const SizedBox(width: 8),
                    ],
                    if (_hasActiveFilters)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _minRatingFilter = null;
                          _tagFilter = null;
                          _geoFilterType = null;
                          _geoFilterValue = null;
                        }),
                        icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                        label: const Text('Clear filters'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: groupedMedia.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.search_off_rounded, size: 80, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          'No memory found',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        if (_hasActiveFilters || _searchQuery.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Try changing your search or the active filters',
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    children: groupedMedia.entries.map((entry) {
                      final loc = entry.key;
                      final mediaItems = entry.value;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8.0),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4.0),
                              child: Row(
                                children: [
                                  const Icon(Icons.place, color: Colors.redAccent, size: 20),
                                  const SizedBox(width: 6),
                                  // Fase 3, punto 17 (migliorato): città,
                                  // regione e nazione sono tre elementi
                                  // cliccabili indipendenti invece di un
                                  // unico testo — la regione compare solo
                                  // quando la località ne ha una.
                                  Flexible(
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 2,
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        _GeoFilterChip(
                                          label: loc.cityLabel,
                                          selected: _geoFilterType == _GeoFilterType.city &&
                                              _geoFilterValue == loc.city,
                                          onTap: () =>
                                              _toggleGeoFilter(_GeoFilterType.city, loc.city),
                                        ),
                                        if (loc.region != null && loc.region!.trim().isNotEmpty) ...[
                                          Text('·', style: TextStyle(color: Colors.grey.shade400)),
                                          _GeoFilterChip(
                                            label: loc.regionLabel ?? loc.region!,
                                            selected: _geoFilterType == _GeoFilterType.region &&
                                                _geoFilterValue == loc.region,
                                            onTap: () => _toggleGeoFilter(
                                                _GeoFilterType.region, loc.region),
                                          ),
                                        ],
                                        Text('·', style: TextStyle(color: Colors.grey.shade400)),
                                        _GeoFilterChip(
                                          label: loc.countryLabel,
                                          selected: _geoFilterType == _GeoFilterType.country &&
                                              _geoFilterValue == loc.country,
                                          onTap: () => _toggleGeoFilter(
                                              _GeoFilterType.country, loc.country),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Spacer(),
                                  Text(
                                    '${mediaItems.length} memories',
                                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              // Fase 3, punto 13/14: margini e dimensione
                              // minima ridotti per mostrare più foto a
                              // schermo senza scorrere troppo.
                              maxCrossAxisExtent: 170,
                              crossAxisSpacing: 4,
                              mainAxisSpacing: 4,
                              childAspectRatio: 1,
                            ),
                            itemCount: mediaItems.length,
                            itemBuilder: (context, index) {
                              final item = mediaItems[index];
                              return MediaTile(
                                media: item,
                                isSelected: false,
                                isSelecting: false,
                                onSelectionChanged: () {},
                                onAuthorTap: (userId) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          UserProfileView(userId: userId),
                                    ),
                                  );
                                },
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => PreviewView(media: item, location: loc),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One tappable "City" / "Region" / "Country" pill shown above a group
/// of photos — filled + bold when it is the active geographic filter,
/// a dotted underline otherwise (same visual hint the old single-label
/// header used, kept for continuity).
class _GeoFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _GeoFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: selected ? 'Clear this filter' : 'Show only $label',
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: selected
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
              : EdgeInsets.zero,
          decoration: selected
              ? BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(6),
                )
              : null,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: selected ? theme.colorScheme.onPrimaryContainer : null,
              decoration: selected ? null : TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
            ),
          ),
        ),
      ),
    );
  }
}
