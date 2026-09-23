import 'package:flutter/material.dart';

/// One entry in the app's main navigation.
///
/// Every entry always carries an icon AND a label — the whole point of
/// this component is to replace icon-only buttons with something anyone
/// can understand at a glance, per the "big buttons, explicit text"
/// style used across the app. The same list of destinations is rendered
/// as a persistent sidebar on wide screens and as a [Drawer] on narrow
/// ones, so the two never drift out of sync.
class AppNavDestination {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool selected;

  /// Small number shown next to the icon (e.g. unread messages). Zero
  /// means "don't show a badge".
  final int badgeCount;

  /// A section title ("Administration") rather than a tappable entry.
  final bool isHeader;

  const AppNavDestination({
    required this.icon,
    required this.label,
    this.onTap,
    this.selected = false,
    this.badgeCount = 0,
  }) : isHeader = false;

  const AppNavDestination.header(this.label)
      : icon = Icons.circle,
        onTap = null,
        selected = false,
        badgeCount = 0,
        isHeader = true;
}

/// Renders [destinations] as a scrollable column, either with their
/// labels (expanded sidebar / drawer) or as icon-only tiles with a
/// tooltip (collapsed desktop sidebar).
class AppNavList extends StatelessWidget {
  final List<AppNavDestination> destinations;
  final bool showLabels;

  const AppNavList({
    super.key,
    required this.destinations,
    this.showLabels = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final destination in destinations)
          if (destination.isHeader)
            showLabels
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                    child: Text(
                      destination.label.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  )
                : const Divider(height: 20, indent: 16, endIndent: 16)
          else
            _NavTile(destination: destination, showLabel: showLabels),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  final AppNavDestination destination;
  final bool showLabel;

  const _NavTile({required this.destination, required this.showLabel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = destination.selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    final icon = destination.badgeCount > 0
        ? Badge(
            label: Text('${destination.badgeCount}'),
            child: Icon(destination.icon, color: color),
          )
        : Icon(destination.icon, color: color);

    final background =
        destination.selected ? theme.colorScheme.primaryContainer : Colors.transparent;

    if (!showLabel) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Tooltip(
          message: destination.label,
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: destination.onTap,
              child: SizedBox(height: 48, child: Center(child: icon)),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: destination.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    destination.label,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: destination.selected ? FontWeight.bold : FontWeight.w500,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavHeader extends StatelessWidget {
  final bool compact;
  const _NavHeader({this.compact = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A small gradient accent instead of a flat neutral bar: this is the
    // one spot in the sidebar/drawer that is always on screen, so it is
    // where a bit of colour reads best without competing with the map
    // or the photo grid underneath it.
    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [theme.colorScheme.primary, theme.colorScheme.tertiary],
    );
    const logo = Icon(Icons.public, color: Colors.white, size: 28);

    return Container(
      decoration: BoxDecoration(gradient: gradient),
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 20, vertical: 20),
      child: compact
          ? const Center(child: logo)
          : Row(
              children: [
                logo,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'World Traveller',
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The navigation shown on narrow (phone-width) screens: a standard
/// [Drawer], opened from a hamburger button, with the exact same
/// destinations the desktop sidebar shows.
class AppNavDrawer extends StatelessWidget {
  final List<AppNavDestination> destinations;

  const AppNavDrawer({super.key, required this.destinations});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const _NavHeader(),
            const Divider(height: 1),
            Expanded(child: AppNavList(destinations: destinations)),
          ],
        ),
      ),
    );
  }
}

/// The navigation shown on wide (desktop/tablet) screens: a sidebar
/// docked to the left edge that the traveller can collapse down to
/// icons-only to leave more room for the map/gallery, and expand back
/// whenever they want the text labels again.
class AppNavSidebar extends StatelessWidget {
  final List<AppNavDestination> destinations;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  static const double expandedWidth = 248;
  static const double collapsedWidth = 72;

  const AppNavSidebar({
    super.key,
    required this.destinations,
    required this.expanded,
    required this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      width: expanded ? expandedWidth : collapsedWidth,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(right: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        children: [
          _NavHeader(compact: !expanded),
          const Divider(height: 1),
          Expanded(child: AppNavList(destinations: destinations, showLabels: expanded)),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Tooltip(
              message: expanded ? 'Collapse the menu' : 'Expand the menu',
              child: IconButton(
                icon: Icon(expanded ? Icons.chevron_left : Icons.chevron_right),
                onPressed: onToggleExpanded,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
