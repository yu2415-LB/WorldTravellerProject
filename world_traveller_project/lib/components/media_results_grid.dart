import 'package:flutter/material.dart';
import 'package:world_traveller_project/components/media_tile.dart';
import 'package:world_traveller_project/models/location.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/views/preview_view.dart';

/// A picture together with the place it was taken, so a grid can open the
/// right preview screen.
class LocatedMedia {
  final Media media;
  final Location location;

  const LocatedMedia({required this.media, required this.location});
}

/// Shared grid used by Favourites, My memories and the traveller page.
class MediaResultsGrid extends StatelessWidget {
  final List<LocatedMedia> items;
  final String emptyTitle;
  final String emptySubtitle;
  final IconData emptyIcon;
  final void Function(String userId)? onAuthorTap;
  final VoidCallback? onChanged;

  const MediaResultsGrid({
    super.key,
    required this.items,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.emptyIcon = Icons.photo_library_outlined,
    this.onAuthorTap,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(emptyIcon, size: 72, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                emptyTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                emptySubtitle,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(10),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        // Fase 3, punto 13/14: margini ridotti per vedere più foto senza
        // scorrere troppo, coerente con il feed principale.
        maxCrossAxisExtent: 170,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final entry = items[index];
        return MediaTile(
          media: entry.media,
          isSelected: false,
          isSelecting: false,
          onSelectionChanged: () {},
          onAuthorTap: onAuthorTap,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PreviewView(
                  media: entry.media,
                  location: entry.location,
                ),
              ),
            );
            onChanged?.call();
          },
        );
      },
    );
  }
}
