import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/providers/social_controller.dart';

/// A single responsive picture thumbnail.
/// Shows images coming from a Supabase URL or from bytes held in memory.
class MediaTile extends StatefulWidget {
  final Media media;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onSelectionChanged;
  final VoidCallback? onTap;

  /// Shows the heart button in the top-left corner.
  final bool showFavouriteButton;

  /// Shows the uploader's name along the bottom edge.
  final bool showAuthor;

  /// Called when the author's name is tapped, to open that traveller's page.
  final void Function(String userId)? onAuthorTap;

  /// Masonry mode: the tile takes the picture's own proportions
  /// (full width, natural height) instead of filling a fixed box.
  final bool natural;

  const MediaTile({
    super.key,
    required this.media,
    required this.isSelected,
    required this.isSelecting,
    required this.onSelectionChanged,
    this.onTap,
    this.showFavouriteButton = true,
    this.showAuthor = true,
    this.onAuthorTap,
    this.natural = false,
  });

  @override
  State<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<MediaTile> {
  bool _isHovered = false;

  Future<void> _toggleFavourite() async {
    final social = context.read<SocialController>();
    final result = await social.toggleFavourite(widget.media.id);

    if (!mounted) return;

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to save pictures to your favourites.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: InkWell(
            onTap: widget.onTap,
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final media = widget.media;
    final url = media.publicUrl;
    final bytes = media.memoryBytes;

    Widget mediaWidget;

    if (bytes != null && bytes.isNotEmpty) {
      mediaWidget = Image.memory(
        bytes,
        fit: widget.natural ? BoxFit.fitWidth : BoxFit.cover,
        width: widget.natural ? double.infinity : null,
        errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(),
      );
    } else if (url != null && url.isNotEmpty) {
      mediaWidget = Image.network(
        url,
        fit: widget.natural ? BoxFit.fitWidth : BoxFit.cover,
        width: widget.natural ? double.infinity : null,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          final spinner = Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                  : null,
            ),
          );
          return widget.natural ? AspectRatio(aspectRatio: 1, child: spinner) : spinner;
        },
        errorBuilder: (context, error, stackTrace) => _buildFallbackIcon(),
      );
    } else {
      mediaWidget = _buildFallbackIcon();
    }

    final social = context.watch<SocialController>();
    final isFavourite = social.isFavourite(media.id);

    return Stack(
      fit: widget.natural ? StackFit.loose : StackFit.expand,
      children: [
        mediaWidget,

        // Hover overlay
        Positioned.fill(
          child: AnimatedOpacity(
          duration: const Duration(milliseconds: 150),
          opacity: _isHovered ? 1.0 : 0.0,
          child: IgnorePointer(
            child: Container(
              color: Colors.black.withValues(alpha: 0.45),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.open_in_full, color: Colors.white, size: 28),
                  SizedBox(height: 6),
                  Text(
                    'Open',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),

        // Favourite (like) button, top-left corner.
        // Fase 3, punto 16: l'icona si riempie subito al tap (già gestito
        // in modo ottimistico da SocialController.toggleFavourite, che
        // aggiorna lo stato locale prima ancora che la chiamata di rete
        // finisca) — qui aggiungiamo anche un piccolo "pop" per rendere
        // il cambiamento più evidente.
        if (widget.showFavouriteButton && !widget.isSelecting)
          Positioned(
            top: 4,
            left: 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.42),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: isFavourite ? 'Remove from favourites' : 'Add to favourites',
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                padding: EdgeInsets.zero,
                icon: TweenAnimationBuilder<double>(
                  key: ValueKey(isFavourite),
                  tween: Tween(begin: 0.6, end: 1.0),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Icon(
                    isFavourite ? Icons.favorite : Icons.favorite_border,
                    color: isFavourite ? Colors.redAccent : Colors.white,
                  ),
                ),
                onPressed: _toggleFavourite,
              ),
            ),
          ),

        // Multiple selection
        if (widget.isSelecting)
          Positioned(
            top: 6,
            left: 6,
            child: Checkbox(
              value: widget.isSelected,
              onChanged: (_) => widget.onSelectionChanged(),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              fillColor: WidgetStateProperty.resolveWith<Color>(
                (states) => states.contains(WidgetState.selected)
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black54,
              ),
              checkColor: Colors.white,
              side: const BorderSide(color: Colors.white, width: 2),
            ),
          ),

        // Star rating badge
        // Fase 3, punto 15: rimosso dalla vista a griglia per non coprire
        // l'immagine — resta solo il pulsante Preferiti in alto a
        // sinistra. Il voto è comunque visibile aprendo la foto.

        // Caption card: soft dark gradient along the bottom with the
        // picture's title (never the file name) and the star rating.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 28, 12, 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    media.displayTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      height: 1.15,
                    ),
                  ),
                  if (media.grading > 0) ...[
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                        const SizedBox(width: 2),
                        Text(
                          media.grading.toStringAsFixed(media.grading % 1 == 0 ? 0 : 1),
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),

        // Author name along the bottom.
        // Fase 3, punto 15: rimosso dalla vista a griglia per lo stesso
        // motivo; il nome dell'autore resta visibile nella preview a
        // schermo intero e nelle pagine profilo.
      ],
    );
  }

  Widget _buildFallbackIcon() {
    final box = Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Icon(Icons.image, size: 40, color: Colors.grey.shade400),
      ),
    );
    return widget.natural ? AspectRatio(aspectRatio: 1, child: box) : box;
  }
}
