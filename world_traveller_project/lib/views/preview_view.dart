import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/main.dart';
import 'package:world_traveller_project/models/location.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/models/user_profile.dart';
import 'package:world_traveller_project/providers/location_managing_controller.dart';
import 'package:world_traveller_project/providers/social_controller.dart';
import 'package:world_traveller_project/views/edit_media_view.dart';
import 'package:world_traveller_project/views/fullscreen_image_view.dart';
import 'package:world_traveller_project/views/user_profile_view.dart';

class PreviewView extends StatefulWidget {
  final Media media;
  final Location location;

  const PreviewView({
    super.key,
    required this.media,
    required this.location,
  });

  @override
  State<PreviewView> createState() => _PreviewViewState();
}

class _PreviewViewState extends State<PreviewView> {
  final ScrollController _scrollController = ScrollController();
  late Media _currentMedia;
  UserProfile? _author;

  @override
  void initState() {
    super.initState();
    _currentMedia = widget.media;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userId = _currentMedia.userId;
      if (userId == null || userId.isEmpty || !mounted) return;

      final profile = await context.read<SocialController>().loadProfile(userId);
      if (!mounted) return;
      setState(() {
        _author = profile;
        _currentMedia.ownerDisplayName = profile?.fullName;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;

    final social = context.read<SocialController>();
    if (!canManageMedia(_currentMedia, social)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only delete pictures you uploaded yourself.'),
        ),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete memory'),
        content: Text(
          'Do you really want to delete "${_currentMedia.displayTitle}"? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      try {
        await context.read<LocationManagingController>().removeItem(
              _currentMedia,
              requestedByAdmin: social.isCurrentUserAdmin,
            );
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } on MediaPermissionDeniedException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
  }

  Future<void> _handleEditPressed() async {
    if (!await ensureLoggedIn(context)) return;
    if (!mounted) return;

    if (!canManageMedia(_currentMedia, context.read<SocialController>())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You can only edit pictures you uploaded yourself.'),
        ),
      );
      return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EditMediaView(media: _currentMedia),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleFavourite() async {
    final result = await context.read<SocialController>().toggleFavourite(
          _currentMedia.id,
        );

    if (!mounted) return;

    if (result == null) {
      final signedIn = await ensureLoggedIn(context);
      if (!mounted) return;
      if (signedIn) {
        await context.read<SocialController>().refreshForCurrentUser();
        if (!mounted) return;
        await context.read<SocialController>().toggleFavourite(_currentMedia.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // While signed out we do not know "who you are", so the icons stay
    // visible: the real check happens on tap (ensureLoggedIn +
    // canManageMedia), which is also where we explain the refusal.
    final social = context.watch<SocialController>();
    final loggedInAndNotOwner =
        supabase.auth.currentUser != null && !canManageMedia(_currentMedia, social);
    final isFavourite = social.isFavourite(_currentMedia.id);

    // Edit/Delete are not just disabled for a non-owner: they are removed
    // from the screen entirely, so nobody sees a button for an action they
    // are not allowed to take. While signed out we still cannot tell "who
    // you are" yet, so the icons stay hidden until a sign-in is attempted
    // via the favourite/contact flow — canManageMedia() then re-runs with
    // the right user id.
    final canManage = !loggedInAndNotOwner &&
        (supabase.auth.currentUser == null || canManageMedia(_currentMedia, social));

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentMedia.displayTitle),
        actions: [
          IconButton(
            tooltip: isFavourite ? 'Remove from favourites' : 'Add to favourites',
            icon: Icon(
              isFavourite ? Icons.favorite : Icons.favorite_border,
              color: isFavourite ? Colors.redAccent : null,
            ),
            onPressed: _toggleFavourite,
          ),
          if (canManage) ...[
            IconButton(
              tooltip: 'Edit details',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _handleEditPressed,
            ),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _confirmDelete,
            ),
          ],
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideScreen = constraints.maxWidth >= 800;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: isWideScreen
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 6, child: _mediaPanel()),
                      const SizedBox(width: 24),
                      Expanded(flex: 4, child: _detailsPanel()),
                    ],
                  )
                : ListView(
                    controller: _scrollController,
                    children: [
                      SizedBox(height: 360, child: _mediaPanel()),
                      const SizedBox(height: 20),
                      _detailsPanel(),
                    ],
                  ),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Picture panel
  // ---------------------------------------------------------------------

  Widget _mediaPanel() {
    final media = _currentMedia;

    Widget imageWidget;
    if (media.memoryBytes != null && media.memoryBytes!.isNotEmpty) {
      imageWidget = Image.memory(media.memoryBytes!, fit: BoxFit.contain);
    } else if (media.publicUrl != null && media.publicUrl!.isNotEmpty) {
      imageWidget = Image.network(
        media.publicUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator());
        },
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image_outlined, size: 64, color: Colors.white54),
        ),
      );
    } else {
      imageWidget = const Center(
        child: Icon(Icons.image_not_supported, size: 64, color: Colors.white54),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Material(
        color: Colors.black,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => FullscreenImageView(
                  imageUrl: media.publicUrl,
                  memoryBytes: media.memoryBytes,
                  title: media.displayTitle,
                ),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              imageWidget,
              Positioned(
                right: 12,
                bottom: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.fullscreen, color: Colors.white, size: 18),
                      SizedBox(width: 6),
                      Text('Full screen',
                          style: TextStyle(color: Colors.white, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Details panel
  // ---------------------------------------------------------------------

  Widget _detailsPanel() {
    final media = _currentMedia;
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAuthorRow(theme),
              const Divider(height: 32),

              // Rating and mood
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (index) => Icon(
                        index < media.grading
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: Colors.amber,
                        size: 26,
                      ),
                    ),
                  ),
                  Chip(
                    avatar: const Icon(Icons.mood, size: 16),
                    label: Text(media.emotionLabel ?? 'No feeling set'),
                    backgroundColor:
                        theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                  ),
                ],
              ),
              const Divider(height: 32),

              // Place
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Icon(Icons.place, color: theme.colorScheme.primary),
                ),
                title: Text(
                  widget.location.fullLabel,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16),
                ),
                subtitle: Text(
                  'Coordinates: ${widget.location.latitude.toStringAsFixed(4)}, '
                  '${widget.location.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 32),

              // Story
              if (media.storyNote != null && media.storyNote!.isNotEmpty) ...[
                Text(
                  'The story behind this memory',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    media.storyNote!,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Tags
              if (media.tags.isNotEmpty) ...[
                Text(
                  'Tags',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: media.tags
                      .map((tag) => Chip(
                            label: Text(tag),
                            visualDensity: VisualDensity.compact,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Name of whoever posted the picture, with a button to contact them.
  Widget _buildAuthorRow(ThemeData theme) {
    final author = _author;
    final displayName = author?.fullName ?? _currentMedia.ownerDisplayName;

    if (displayName == null || displayName.trim().isEmpty) {
      return Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.person_outline, size: 20),
          ),
          const SizedBox(width: 12),
          Text(
            'Unknown traveller',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      );
    }

    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: author == null
              ? null
              : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => UserProfileView(
                        userId: author.id,
                        preloadedProfile: author,
                      ),
                    ),
                  ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: theme.colorScheme.primaryContainer,
                backgroundImage: (author?.avatarUrl != null && author!.avatarUrl!.isNotEmpty)
                    ? NetworkImage(author.avatarUrl!)
                    : null,
                child: (author?.avatarUrl == null || author!.avatarUrl!.isEmpty)
                    ? Text(
                        displayName[0].toUpperCase(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    displayName,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  Text(
                    'Posted this memory',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        if (author != null)
          FilledButton.tonalIcon(
            onPressed: () => showContactDialog(context, author),
            icon: const Icon(Icons.mail_outline, size: 16),
            label: const Text('Contact'),
          ),
      ],
    );
  }
}
