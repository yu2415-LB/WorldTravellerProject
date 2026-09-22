import 'package:flutter/material.dart';

/// One person credited for working on the app.
class Contributor {
  final String name;
  final String role;
  final IconData icon;

  const Contributor({
    required this.name,
    required this.role,
    required this.icon,
  });
}

/// The people behind World Traveller.
const List<Contributor> appContributors = [
  Contributor(
    name: 'Antonis Karakonstantakis',
    role: 'Founder & Original Idea',
    icon: Icons.lightbulb_outline,
  ),
  Contributor(
    name: 'Florian Kaltenbrunner',
    role: 'Developer (Version 1)',
    icon: Icons.code,
  ),
  Contributor(
    name: 'Lorenzo Baravelli',
    role: 'Developer (Version 2)',
    icon: Icons.code,
  ),
];

/// Opens a small, friendly window that shows who made the app.
Future<void> showAboutCreditsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(28.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.travel_explore,
                    size: 32,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'World Traveller',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Made by the people below.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 20),
              ...appContributors.map(
                (person) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          person.icon,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              person.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                            Text(
                              person.role,
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
