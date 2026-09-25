import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/enums/media_visibility.dart';
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
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
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

  /// True when the signed-in user is the owner AND the picture is still
  /// private AND the picture is NOT local-only. Only in that exact case
  /// the big publish CTA is shown — local-only pictures have no cloud
  /// version to publish, so the banner stays hidden for them.
  bool get _canPublishCurrent =>
      !_currentMedia.isLocalOnly &&
      _currentMedia.visibility == MediaVisibility.private &&
      supabase.auth.currentUser?.id != null &&
      supabase.auth.currentUser!.id == _currentMedia.userId;

  /// True when this picture lives only on this machine.
  bool get _isLocalOnly => _currentMedia.isLocalOnly;

  /// Publishes this picture to the General World in one tap. Skips the
  /// EditMediaView screen entirely (which is where the publish button
  /// used to be hidden away) and asks the category question directly.
  Future<void> _quickPublish() async {
    final chosen = await showModalBottomSheet<MediaCategory>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _QuickCategorySheet(),
    );
    if (chosen == null || !mounted) return;

    final updated = Media(
      id: _currentMedia.id,
      filePath: _currentMedia.filePath,
      type: _currentMedia.type,
      grading: _currentMedia.grading,
      mood: _currentMedia.mood,
      fileName: _currentMedia.fileName,
      title: _currentMedia.title,
      lastModification: _currentMedia.lastModification,
      tags: _currentMedia.tags,
      storyNote: _currentMedia.storyNote,
      remoteUrl: _currentMedia.remoteUrl,
      memoryBytes: _currentMedia.memoryBytes,
      travelDate: _currentMedia.travelDate,
      visibility: MediaVisibility.public,
      category: chosen,
      userId: _currentMedia.userId,
      ownerDisplayName: _currentMedia.ownerDisplayName,
      isLocalOnly: _currentMedia.isLocalOnly,
      localPath: _currentMedia.localPath,
    );

    try {
      await context.read<LocationManagingController>().updateMedia(updated);
      if (!mounted) return;
      setState(() => _currentMedia = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pubblicata nel General World · ${chosen.label}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Non sono riuscito a pubblicare: $e')),
      );
    }
  }

  /// Big horizontal banner shown above the photo when it's yours and
  /// still private. This is the visible, unmissable CTA the user asked
  /// for, not a tiny icon hidden inside the Edit screen.
  Widget _publishBanner() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.tertiary,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.lock_outline,
                  color: theme.colorScheme.onTertiary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Questa foto è privata — la vedi solo tu, in "My Work".',
                  style: TextStyle(
                    color: theme.colorScheme.onTertiary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _quickPublish,
                style: FilledButton.styleFrom(
                  backgroundColor: theme.colorScheme.onTertiary,
                  foregroundColor: theme.colorScheme.tertiary,
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.public, size: 18),
                label: const Text('PUBBLICA NEL GENERAL WORLD'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Info banner shown for pictures that live only on this machine.
  Widget _localOnlyBanner() {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.computer,
                  color: theme.colorScheme.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Questa foto è salvata solo su questo computer. '
                  'Non è nel cloud e non è visibile ad altri.',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    // are not allowed to take.
    final canManage = !loggedInAndNotOwner &&
        (supabase.auth.currentUser == null ||
            canManageMedia(_currentMedia, social));

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
      body: SafeArea(
        top: false,
        bottom: false,
        left: true,
        right: true,
        child: Column(
          children: [
            if (_isLocalOnly) _localOnlyBanner(),
            if (_canPublishCurrent) _publishBanner(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // "Wide" means big enough in BOTH directions: a phone in
                  // landscape has width > 800 but height < 400, and the
                  // two columns would overflow vertically if we treated
                  // it as wide. Small-screen layout (single scrollable
                  // column) is used whenever either dimension is tight.
                  final isWideScreen =
                      constraints.maxWidth >= 800 &&
                          constraints.maxHeight >= 500;

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
            ),
          ],
        ),
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
          child: Icon(Icons.broken_image_outlined,
              size: 64, color: Colors.white54),
        ),
      );
    } else {
      imageWidget = const Center(
        child: Icon(Icons.image_not_supported,
            size: 64, color: Colors.white54),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                backgroundImage: (author?.avatarUrl != null &&
                        author!.avatarUrl!.isNotEmpty)
                    ? NetworkImage(author.avatarUrl!)
                    : null,
                child: (author?.avatarUrl == null ||
                        author!.avatarUrl!.isEmpty)
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

/// Bottom sheet used by the quick-publish CTA in the PreviewView.
class _QuickCategorySheet extends StatelessWidget {
  const _QuickCategorySheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dove appartiene questo viaggio?',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Decide in quale sezione del General World apparirà.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 20),
            _QuickCategoryOption(
              icon: Icons.luggage_outlined,
              title: 'Personal trip',
              subtitle: 'Una vacanza, un weekend, un posto visitato per te.',
              onTap: () => Navigator.pop(context, MediaCategory.personalTrip),
            ),
            const SizedBox(height: 12),
            _QuickCategoryOption(
              icon: Icons.work_outline,
              title: 'Work / Portfolio',
              subtitle:
                  'Un viaggio di lavoro, uno shooting, contenuto portfolio.',
              onTap: () =>
                  Navigator.pop(context, MediaCategory.workPortfolio),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickCategoryOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _QuickCategoryOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(icon, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.hintColor)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}