import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/enums/media_visibility.dart';
import 'package:world_traveller_project/models/media.dart';
import 'package:world_traveller_project/providers/location_managing_controller.dart';
import 'package:world_traveller_project/views/fullscreen_image_view.dart';

class EditMediaView extends StatefulWidget {
  final Media media;

  const EditMediaView({super.key, required this.media});

  @override
  State<EditMediaView> createState() => _EditMediaViewState();
}

class _EditMediaViewState extends State<EditMediaView> {
  final ScrollController _scrollController = ScrollController();
  final ScrollController _detailsScrollController = ScrollController();
  late TextEditingController _titleController;
  late TextEditingController _storyController;
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _customMoodController = TextEditingController();

  late double _rating;

  /// null = no mood chosen. One of Media.standardMoods, or _otherMoodOption
  /// when the person picked "Other..." -- in that case the actual text
  /// they typed lives in _customMoodController.
  String? _selectedMood;
  static const _otherMoodOption = 'Other...';

  late List<String> _tags;
  bool _isSaving = false;

  /// "My Work" (private) vs "General World" (public) — publishing a
  /// picture is an explicit choice the owner makes here.
  late MediaVisibility _visibility;

  /// Only meaningful once [_visibility] is public.
  late MediaCategory _category;

  late DateTime _travelDate;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.media.title ?? '');
    _storyController = TextEditingController(text: widget.media.storyNote ?? '');
    _rating = widget.media.grading;
    if (widget.media.mood == null) {
      _selectedMood = null;
    } else if (widget.media.isStandardMood) {
      _selectedMood = widget.media.mood;
    } else {
      _selectedMood = _otherMoodOption;
      _customMoodController.text = widget.media.mood!;
    }
    _tags = List.from(widget.media.tags);
    _visibility = widget.media.visibility;
    _category = widget.media.category ?? MediaCategory.personalTrip;
    _travelDate = widget.media.travelDate ?? widget.media.lastModification;
  }

  /// The text that will actually be saved as the mood.
  String? get _resolvedMood {
    if (_selectedMood == _otherMoodOption) {
      final custom = _customMoodController.text.trim();
      return custom.isEmpty ? null : custom;
    }
    return _selectedMood;
  }

  Future<void> _pickTravelDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _travelDate,
      firstDate: DateTime(1970),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _travelDate = picked);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _detailsScrollController.dispose();
    _titleController.dispose();
    _storyController.dispose();
    _tagController.dispose();
    _customMoodController.dispose();
    super.dispose();
  }

  void _addTag() {
    final text = _tagController.text.trim();
    if (text.isNotEmpty && !_tags.contains(text)) {
      setState(() {
        _tags.add(text);
        _tagController.clear();
      });
    }
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _saveChanges() async {
    setState(() => _isSaving = true);

    final updatedMedia = Media(
      id: widget.media.id,
      filePath: widget.media.filePath,
      type: widget.media.type,
      grading: _rating,
      mood: _resolvedMood,
      // The technical file name is never touched by editing -- only the
      // caption (title) the person writes changes here.
      fileName: widget.media.fileName,
      title: _titleController.text.trim().isEmpty ? null : _titleController.text.trim(),
      lastModification: widget.media.lastModification,
      tags: _tags,
      storyNote: _storyController.text.trim(),
      remoteUrl: widget.media.remoteUrl,
      memoryBytes: widget.media.memoryBytes,
      travelDate: _travelDate,
      visibility: _visibility,
      // The category split only means something once the picture is
      // public; keep it null while it is still private "My Work".
      category: _visibility.isPublic ? _category : null,
      userId: widget.media.userId,
      ownerDisplayName: widget.media.ownerDisplayName,
    );

    try {
      await context.read<LocationManagingController>().updateMedia(updatedMedia);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save your changes: $error')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit memory details'),
        actions: [
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: 'Save',
            onPressed: _isSaving ? null : _saveChanges,
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWideScreen = constraints.maxWidth >= 760;

          return Padding(
            padding: const EdgeInsets.all(24),
            child: isWideScreen
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: _mediaPreviewPanel()),
                      const SizedBox(width: 24),
                      Expanded(flex: 5, child: _detailsPanel(scrollable: true)),
                    ],
                  )
                : ListView(
                    controller: _scrollController,
                    children: [
                      SizedBox(height: 320, child: _mediaPreviewPanel()),
                      const SizedBox(height: 20),
                      _detailsPanel(scrollable: false),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _mediaPreviewPanel() {
    final media = widget.media;

    Widget previewWidget;
    if (media.memoryBytes != null && media.memoryBytes!.isNotEmpty) {
      previewWidget = Image.memory(media.memoryBytes!, fit: BoxFit.contain);
    } else if (media.publicUrl != null && media.publicUrl!.isNotEmpty) {
      previewWidget = Image.network(
        media.publicUrl!,
        fit: BoxFit.contain,
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : const Center(child: CircularProgressIndicator()),
        errorBuilder: (context, error, stackTrace) => const Center(
          child: Icon(Icons.broken_image, size: 60, color: Colors.white54),
        ),
      );
    } else {
      previewWidget = const Center(
        child: Icon(Icons.image_not_supported, size: 60, color: Colors.white54),
      );
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              previewWidget,
              const Positioned(
                  right: 12,
                  bottom: 12,
                  child: Chip(
                    avatar: Icon(Icons.fullscreen, size: 16),
                    label: Text('Enlarge', style: TextStyle(fontSize: 12)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailsPanel({required bool scrollable}) {
    final theme = Theme.of(context);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(
            labelText: 'Title',
            hintText: 'e.g. Sunset over the hills',
            helperText: "Just a caption — it won't rename the picture file.",
            prefixIcon: Icon(Icons.label_outline),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),

        // When the trip happened
        Text(
          'Travel date',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _pickTravelDate,
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text(
            '${_travelDate.year}-${_travelDate.month.toString().padLeft(2, '0')}-'
            '${_travelDate.day.toString().padLeft(2, '0')}',
          ),
        ),
        const SizedBox(height: 24),

        // Publishing: a single, unmistakable action instead of two small
        // toggle chips that looked equally "on" — a private picture gets
        // one big call-to-action button, a published one gets a clear
        // status line plus a small way to change its mind.
        _PublishSection(
          visibility: _visibility,
          category: _category,
          onPublish: (category) {
            setState(() {
              _visibility = MediaVisibility.public;
              _category = category;
            });
          },
          onUnpublish: () => setState(() => _visibility = MediaVisibility.private),
        ),
        const SizedBox(height: 24),

        // Rating
        Text(
          'Rating',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Row(
              children: List.generate(5, (index) {
                final starValue = index + 1.0;
                return IconButton(
                  iconSize: 32,
                  icon: Icon(
                    _rating >= starValue ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: Colors.amber,
                  ),
                  onPressed: () => setState(() => _rating = starValue),
                );
              }),
            ),
            const SizedBox(width: 12),
            Text(
              '${_rating.toStringAsFixed(0)} / 5',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Mood / Emozione
        Text(
          'How does it make you feel?',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'The feeling this moment or place brings back',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _selectedMood,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.mood_outlined),
          ),
          hint: const Text('Choose a feeling'),
          items: [
            for (final label in Media.standardMoods)
              DropdownMenuItem(value: label, child: Text(label)),
            const DropdownMenuItem(value: _otherMoodOption, child: Text('\u2795 Other...')),
          ],
          onChanged: (value) => setState(() => _selectedMood = value),
        ),
        if (_selectedMood == _otherMoodOption) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _customMoodController,
            decoration: const InputDecoration(
              labelText: 'Your own feeling',
              hintText: 'e.g. Homesick, Adventurous...',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 24),

        // Storia
        Text(
          'The story behind this memory',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          'What inspired you? What did you see or experience here?',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _storyController,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'e.g. Taken at sunrise after a two-hour scenic hike...',
            border: OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 24),

        // Tag
        Text(
          'Tag',
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tagController,
                decoration: const InputDecoration(
                  hintText: 'Add a tag...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.local_offer_outlined),
                ),
                onSubmitted: (_) => _addTag(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: _addTag,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              ),
              child: const Text('Add'),
            ),
          ],
        ),
        if (_tags.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _tags.map((tag) {
              return Chip(
                label: Text(tag),
                deleteIcon: const Icon(Icons.close, size: 16),
                onDeleted: () => _removeTag(tag),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 32),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _saveChanges,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save changes', style: TextStyle(fontSize: 16)),
          ),
        ),
      ],
    );

    if (!scrollable) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: content,
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Scrollbar(
        controller: _detailsScrollController,
        thumbVisibility: true,
        child: SingleChildScrollView(
          controller: _detailsScrollController,
          padding: const EdgeInsets.all(24.0),
          child: content,
        ),
      ),
    );
  }
}

/// The "publish this picture" call to action. A private picture gets one
/// big, unmistakable button; a published one gets a clear status line
/// plus small, secondary ways to change category or un-publish.
class _PublishSection extends StatelessWidget {
  final MediaVisibility visibility;
  final MediaCategory category;
  final void Function(MediaCategory category) onPublish;
  final VoidCallback onUnpublish;

  const _PublishSection({
    required this.visibility,
    required this.category,
    required this.onPublish,
    required this.onUnpublish,
  });

  Future<void> _openCategoryPicker(BuildContext context) async {
    final chosen = await showModalBottomSheet<MediaCategory>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CategoryPickerSheet(),
    );
    if (chosen != null) onPublish(chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!visibility.isPublic) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ready to share it?',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Right now only you can see this picture, in "My Work".',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.tertiary,
                foregroundColor: theme.colorScheme.onTertiary,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: () => _openCategoryPicker(context),
              icon: const Icon(Icons.public, size: 22),
              label: const Text('PUBLISH TO GENERAL WORLD'),
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.tertiary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public, color: theme.colorScheme.tertiary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Published to General World \u00b7 ${category.label}',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openCategoryPicker(context),
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('Change category'),
              ),
              TextButton.icon(
                onPressed: onUnpublish,
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Move back to My Work'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The sheet opened by the big publish button (and by "Change category"):
/// asking the question at the exact moment it matters, instead of showing
/// it as an always-visible toggle most people would ignore.
class _CategoryPickerSheet extends StatelessWidget {
  const _CategoryPickerSheet();

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
              'Where does this trip belong?',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'This decides which section of General World shows it.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            ),
            const SizedBox(height: 20),
            _CategoryOptionCard(
              icon: Icons.luggage_outlined,
              title: 'Personal trip',
              subtitle: 'A holiday, a weekend away, a place you visited for yourself.',
              onTap: () => Navigator.pop(context, MediaCategory.personalTrip),
            ),
            const SizedBox(height: 12),
            _CategoryOptionCard(
              icon: Icons.work_outline,
              title: 'Work / Portfolio',
              subtitle: 'A work trip, a shoot, or anything meant to showcase your work.',
              onTap: () => Navigator.pop(context, MediaCategory.workPortfolio),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CategoryOptionCard({
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
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
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
