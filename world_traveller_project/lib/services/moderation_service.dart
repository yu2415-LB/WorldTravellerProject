/// Result of a (future) automatic content check.
class ModerationResult {
  final bool allowed;
  final String? reason;

  const ModerationResult.allowed()
      : allowed = true,
        reason = null;

  const ModerationResult.blocked(this.reason) : allowed = false;
}

/// Placeholder for the "Filtro AI" described in the Phase 4 brief:
/// "Integrazione futura di un controllo NSFW automatico per bloccare i
/// contenuti pornografici al momento dell'upload."
///
/// This is intentionally NOT implemented yet — the brief explicitly
/// calls it a future integration, not something to build now. What's
/// here is the seam it will plug into: [AddMediaView._save] already
/// calls [checkImage] for every picture right before upload, so wiring
/// in a real NSFW classifier later (an on-device model or a call to a
/// moderation API) means only changing the body of this one method —
/// no other file needs to know it happened.
///
/// Until then it always allows the upload.
class ModerationService {
  static final ModerationService _instance = ModerationService._internal();
  factory ModerationService() => _instance;
  ModerationService._internal();

  // ignore: unused_element
  Future<ModerationResult> checkImage(List<int> bytes) async {
    // TODO(phase-4-future): send `bytes` to an NSFW classifier (on-device
    // or a moderation API) and return ModerationResult.blocked(reason)
    // when the picture should not be allowed onto the platform.
    return const ModerationResult.allowed();
  }
}
