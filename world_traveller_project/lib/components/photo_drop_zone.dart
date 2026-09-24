import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:world_traveller_project/theme/app_tokens.dart';

/// Where pictures can be imported from. Today only the local computer
/// works; cloud providers (Google Drive, OneDrive, Dropbox) plug in later
/// by adding an entry with [available] = true and their own picker,
/// without touching the uploader itself.
class ImportSourceInfo {
  final IconData icon;
  final String label;
  final bool available;
  const ImportSourceInfo(this.icon, this.label, {this.available = true});
}

const List<ImportSourceInfo> kImportSources = [
  ImportSourceInfo(Icons.folder_outlined, 'Local files'),
  ImportSourceInfo(Icons.cloud_outlined, 'Google Drive', available: false),
];

/// A real drag & drop area (desktop and web). Wraps [child] when
/// pictures are already selected, so dropping more still works; shows the
/// big invitation when there is nothing yet.
class PhotoDropZone extends StatefulWidget {
  final bool enabled;
  final bool busy;
  final VoidCallback onBrowse;
  final void Function(List<XFile> files) onFilesDropped;

  /// Shown instead of the empty-state invitation once pictures exist.
  final Widget? child;

  const PhotoDropZone({
    super.key,
    required this.onBrowse,
    required this.onFilesDropped,
    this.enabled = true,
    this.busy = false,
    this.child,
  });

  @override
  State<PhotoDropZone> createState() => _PhotoDropZoneState();
}

class _PhotoDropZoneState extends State<PhotoDropZone> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DropTarget(
      enable: widget.enabled,
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        if (details.files.isNotEmpty) widget.onFilesDropped(details.files);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: _dragging ? theme.colorScheme.primary : theme.colorScheme.outlineVariant,
            width: _dragging ? 2.5 : 1.5,
          ),
          color: _dragging
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
              : Colors.transparent,
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Stack(
          children: [
            widget.child ?? _invitation(theme),
            if (_dragging && widget.child != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'Drop to add these pictures',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _invitation(ThemeData theme) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _dragging ? Icons.file_download_outlined : Icons.add_photo_alternate_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              _dragging ? 'Drop your photos here' : 'Drag your photos here',
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('or', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: widget.enabled && !widget.busy ? widget.onBrowse : null,
              icon: widget.busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.folder_open_outlined),
              label: Text(widget.busy ? 'Checking pictures...' : 'Choose from computer'),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              alignment: WrapAlignment.center,
              children: [
                for (final source in kImportSources)
                  Chip(
                    avatar: Icon(source.icon, size: 18),
                    label: Text(source.available ? source.label : '${source.label} \u00b7 soon'),
                    backgroundColor: source.available
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'JPG, PNG or WEBP \u00b7 larger pictures are scaled to 2048 px',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
