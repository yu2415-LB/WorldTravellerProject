import 'package:flutter/material.dart';

/// Central design tokens: one place for spacing, radii and the colours
/// of the different notification kinds, so screens stop hard-coding
/// their own numbers. Brand colours and typography still come from the
/// ThemeData built in main.dart.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

class AppRadius {
  static const double chip = 10;
  static const double card = 16;
  static const double panel = 20;
}

/// Kinds of notification / mailbox entry, each with its own colour
/// (contact = blue, accepted = green, declined = orange, social = pink,
/// moderation = amber, critical = red, info = grey-blue).
enum AppNoticeKind { contact, accepted, declined, social, moderation, critical, info }

extension AppNoticeKindStyle on AppNoticeKind {
  Color get color => switch (this) {
        AppNoticeKind.contact => const Color(0xFF1E6FEB),
        AppNoticeKind.accepted => const Color(0xFF0E9F6E),
        AppNoticeKind.declined => const Color(0xFFE8590C),
        AppNoticeKind.social => const Color(0xFFD6336C),
        AppNoticeKind.moderation => const Color(0xFFF08C00),
        AppNoticeKind.critical => const Color(0xFFD92D20),
        AppNoticeKind.info => const Color(0xFF6B7A90),
      };

  IconData get icon => switch (this) {
        AppNoticeKind.contact => Icons.mail_outline,
        AppNoticeKind.accepted => Icons.check_circle_outline,
        AppNoticeKind.declined => Icons.do_not_disturb_alt_outlined,
        AppNoticeKind.social => Icons.favorite_border,
        AppNoticeKind.moderation => Icons.shield_outlined,
        AppNoticeKind.critical => Icons.report_gmailerrorred_outlined,
        AppNoticeKind.info => Icons.info_outline,
      };
}
