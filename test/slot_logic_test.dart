import 'package:flutter_test/flutter_test.dart';
import 'package:barbearia/utils/slot_logic.dart';

void main() {
  group('SlotLogic.snap', () {
    test('rounds down to :00', () {
      final r = SlotLogic.snap(10, 10);
      expect(r.hour, 10);
      expect(r.minute, 0);
    });

    test('rounds to :30', () {
      final r = SlotLogic.snap(10, 20);
      expect(r.hour, 10);
      expect(r.minute, 30);
    });

    test('rolls over hour near :45+', () {
      final r = SlotLogic.snap(10, 50);
      expect(r.hour, 11);
      expect(r.minute, 0);
    });
  });

  group('SlotLogic.generateSlots', () {
    test('30-min steps without break', () {
      // 09:00 .. 10:00
      final slots = SlotLogic.generateSlots(
        startMinutes: 9 * 60,
        endMinutes: 10 * 60,
      );
      expect(slots, ['09:00', '09:30', '10:00']);
    });

    test('skips lunch break', () {
      final slots = SlotLogic.generateSlots(
        startMinutes: 11 * 60 + 30, // 11:30
        endMinutes: 14 * 60, // 14:00
        breakStartMinutes: 12 * 60,
        breakEndMinutes: 13 * 60,
      );
      expect(slots, ['11:30', '13:00', '13:30', '14:00']);
    });
  });

  group('SlotLogic.totalBlocks', () {
    test('sums duration blocks', () {
      expect(SlotLogic.totalBlocks([1, 2, 1]), 4);
    });

    test('treats zero as one', () {
      expect(SlotLogic.totalBlocks([0, 2]), 3);
    });
  });

  group('SlotLogic.hasConsecutiveFree', () {
    test('true for free range', () {
      expect(
        SlotLogic.hasConsecutiveFree(['free', 'free', 'client'], 0, 2),
        isTrue,
      );
    });

    test('false when blocked mid-range', () {
      expect(
        SlotLogic.hasConsecutiveFree(['free', 'blocked', 'free'], 0, 2),
        isFalse,
      );
    });

    test('false when overflows', () {
      expect(SlotLogic.hasConsecutiveFree(['free'], 0, 2), isFalse);
    });
  });

  group('SlotLogic.classifyState', () {
    test('blocked wins', () {
      expect(
        SlotLogic.classifyState(
          source: 'client',
          isReturningClient: true,
          isBlocked: true,
        ),
        'blocked',
      );
    });

    test('admin / walk_in / recurring = purple admin', () {
      expect(
        SlotLogic.classifyState(
          source: 'admin',
          isReturningClient: true,
          isBlocked: false,
        ),
        'admin',
      );
      expect(
        SlotLogic.classifyState(
          source: 'walk_in',
          isReturningClient: false,
          isBlocked: false,
        ),
        'admin',
      );
    });

    test('new client is light blue', () {
      expect(
        SlotLogic.classifyState(
          source: 'client',
          isReturningClient: false,
          isBlocked: false,
        ),
        'newClient',
      );
    });

    test('returning client is grey', () {
      expect(
        SlotLogic.classifyState(
          source: 'client',
          isReturningClient: true,
          isBlocked: false,
        ),
        'client',
      );
    });
  });

  group('SlotLogic.normalizePhone', () {
    test('strips mask', () {
      expect(SlotLogic.normalizePhone('(11) 98888-7777'), '11988887777');
    });
  });
}
