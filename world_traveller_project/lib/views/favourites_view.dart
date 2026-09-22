import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:world_traveller_project/components/media_results_grid.dart';
import 'package:world_traveller_project/main.dart';
import 'package:world_traveller_project/providers/location_managing_controller.dart';
import 'package:world_traveller_project/providers/social_controller.dart';
import 'package:world_traveller_project/views/user_profile_view.dart';

/// Every picture the signed in traveller has liked.
class FavouritesView extends StatefulWidget {
  const FavouritesView({super.key});

  @override
  State<FavouritesView> createState() => _FavouritesViewState();
}

class _FavouritesViewState extends State<FavouritesView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final social = context.read<SocialController>();
      await social.refreshForCurrentUser();

      if (!mounted) return;
      final locations = context.read<LocationManagingController>().locations;
      await social.resolveUsernames(
        locations.expand((loc) => loc.mediaSet),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<LocationManagingController>();
    final social = context.watch<SocialController>();
    final isSignedIn = supabase.auth.currentUser != null;

    final favourites = <LocatedMedia>[];
    for (final location in controller.locations) {
      for (final media in location.mediaSet) {
        if (social.isFavourite(media.id)) {
          favourites.add(LocatedMedia(media: media, location: location));
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.favorite, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Favourites'),
          ],
        ),
      ),
      body: !isSignedIn
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 72, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Sign in to see your favourites',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in'),
                      onPressed: () async {
                        await ensureLoggedIn(context);
                        if (!mounted) return;
                        await context.read<SocialController>().refreshForCurrentUser();
                        if (mounted) setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                if (favourites.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${favourites.length} picture${favourites.length == 1 ? '' : 's'} you liked',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ),
                  ),
                Expanded(
                  child: MediaResultsGrid(
                    items: favourites,
                    emptyIcon: Icons.favorite_border,
                    emptyTitle: 'No favourites yet',
                    emptySubtitle:
                        'Tap the heart in the top-left corner of any picture to save it here.',
                    onChanged: () => setState(() {}),
                    onAuthorTap: (userId) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => UserProfileView(userId: userId),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
