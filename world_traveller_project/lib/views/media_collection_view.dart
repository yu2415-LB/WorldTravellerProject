import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/components/masonry_grid.dart';
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

class _MediaCollectionViewState extends State<MediaCollectionView> {
  String _searchQuery = '';
  double? _minRatingFilter;
  String? _tagFilter;

  /// "How does it make you feel" filter: null = any, one of
  /// Media.standardMoods, or [_otherMoodFilter] = every picture whose
  /// mood is a custom text typed after choosing "Other...".
  String? _moodFilter;
  static const _otherMoodFilter = 'Other...';

  final TextEditingController _searchController = TextEditingController();

  bool get _hasActiveFilters =>
      _minRatingFilter != null || _tagFilter != null || _moodFilter != null;

  void _setSearch(String value) {
    setState(() => _searchQuery = value);
    _searchController.text = value;
    _searchController.selection = TextSelection.collapsed(offset: value.length);
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

    // One flat list of every picture that passes the filters, newest
    // first. The search box still finds pictures by city, region,
    // country or title, so places don't need a header of their own.
    final List<({Media media, Location loc})> results = [];

    for (final loc in locations) {
      final matchesQuery = _searchQuery.isEmpty || loc.matchesQuery(_searchQuery);

      for (final m in loc.mediaSet) {
        final matchesSearch = matchesQuery ||
            m.fileName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (m.title ?? '').toLowerCase().contains(_searchQuery.toLowerCase());
        final matchesRating = _minRatingFilter == null || m.grading >= _minRatingFilter!;
        final matchesTag = _tagFilter == null || m.tags.contains(_tagFilter);
        final matchesMood = _moodFilter == null ||
            (_moodFilter == _otherMoodFilter
                ? (m.emotionLabel != null && !m.isStandardMood)
                : m.mood == _moodFilter);
        if (matchesSearch && matchesRating && matchesTag && matchesMood) {
          results.add((media: m, loc: loc));
        }
      }
    }

    results.sort((a, b) => (b.media.travelDate ?? b.media.lastModification)
        .compareTo(a.media.travelDate ?? a.media.lastModification));

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
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _moodFilter,
                        hint: const Text('Feeling'),
                        borderRadius: BorderRadius.circular(8),
                        dropdownColor: Theme.of(context).colorScheme.surfaceContainerHigh,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        menuMaxHeight: 420,
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text('Any feeling'),
                          ),
                          ...Media.standardMoods.map(
                            (label) => DropdownMenuItem<String?>(value: label, child: Text(label)),
                          ),
                          const DropdownMenuItem<String?>(
                            value: _otherMoodFilter,
                            child: Text('\u2795 Other...'),
                          ),
                        ],
                        onChanged: (value) => setState(() => _moodFilter = value),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_hasActiveFilters)
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _minRatingFilter = null;
                          _tagFilter = null;
                          _moodFilter = null;
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
            child: results.isEmpty
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
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '${results.length} ${results.length == 1 ? 'memory' : 'memories'}',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                          ),
                        ),
                        MasonryGrid(
                          itemCount: results.length,
                          itemBuilder: (context, index) {
                            final item = results[index];
                            return MediaTile(
                              natural: true,
                              media: item.media,
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
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        PreviewView(media: item.media, location: item.loc),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
