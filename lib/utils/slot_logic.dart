// Pure helpers for 30-min agenda slots (unit-testable, no Flutter/Supabase).

class SlotLogic {
  SlotLogic._();

  /// Snap a time to nearest xx:00 or xx:30.
  static ({int hour, int minute}) snap(int hour, int minute) {
    var h = hour;
    int m;
    if (minute < 15) {
      m = 0;
    } else if (minute < 45) {
      m = 30;
    } else {
      m = 0;
      h = (h + 1) % 24;
    }
    return (hour: h, minute: m);
  }

  static String labelOf(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Generate HH:mm labels from [start] inclusive to [end] inclusive, step 30m.
  /// Skips range [breakStart, breakEnd) when both non-null (minutes from midnight).
  static List<String> generateSlots({
    required int startMinutes,
    required int endMinutes,
    int? breakStartMinutes,
    int? breakEndMinutes,
  }) {
    final out = <String>[];
    var cur = startMinutes;
    while (cur <= endMinutes) {
      final duringBreak = breakStartMinutes != null &&
          breakEndMinutes != null &&
          cur >= breakStartMinutes &&
          cur < breakEndMinutes;
      if (!duringBreak) {
        final h = cur ~/ 60;
        final m = cur % 60;
        out.add(labelOf(h, m));
      }
      cur += 30;
    }
    return out;
  }

  /// How many consecutive free slots are needed for multi-service booking.
  static int totalBlocks(Iterable<int> durationBlocksPerService) {
    var n = 0;
    for (final b in durationBlocksPerService) {
      n += b < 1 ? 1 : b;
    }
    return n;
  }

  /// True if [startIndex] has [blocks] consecutive free labels in [states]
  /// where free means state == 'free'.
  static bool hasConsecutiveFree(
    List<String> states,
    int startIndex,
    int blocks,
  ) {
    if (startIndex < 0 || blocks < 1) return false;
    if (startIndex + blocks > states.length) return false;
    for (var i = 0; i < blocks; i++) {
      if (states[startIndex + i] != 'free') return false;
    }
    return true;
  }

  /// Classify appointment slot color state.
  /// source: client | admin | recurring | walk_in
  static String classifyState({
    required String source,
    required bool isReturningClient,
    required bool isBlocked,
  }) {
    if (isBlocked) return 'blocked';
    final s = source.toLowerCase();
    if (s == 'admin' || s == 'walk_in' || s == 'recurring') return 'admin';
    if (!isReturningClient) return 'newClient';
    return 'client';
  }

  static String normalizePhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');
}
