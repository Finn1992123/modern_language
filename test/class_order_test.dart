import 'package:flutter_test/flutter_test.dart';
import 'package:modern_language/class_order.dart';

void main() {
  test('school level order and numeric group order', () {
    final expected = [
      'Pre Junior',
      'Pre Junior 2',
      'JA1',
      'JA2',
      'JA10',
      'JB1',
      'JB2',
      'SA1',
      'SB1',
      'SC1',
      'SD1',
      'Pre-Lower1',
      'Lower1',
      'Advanced1',
      'Proficiency1',
      'Proficiency2',
      'Proficiency10',
    ];
    final actual = expected.reversed.toList()..sort(compareClassNames);
    expect(actual, expected);
  });

  test('level aliases, case and separators are equivalent', () {
    for (final pair in [
      ['pre_junior 1', 'PJ1'],
      ['Junior A 2', 'ja2'],
      ['junior-b 3', 'JB3'],
      ['Senior A1', 'SA1'],
      ['senior_c 2', 'SC2'],
      ['Pre Lower 1', 'PL1'],
    ]) {
      expect(compareClassNames(pair[0], pair[1]), 0);
    }
  });

  test(
    'unrecognized levels sort naturally last, with missing names at end',
    () {
      final names = <String?>[
        null,
        'Other10',
        ' ',
        'Other2',
        'Proficiency1',
        'JA1',
      ]..sort(compareClassNames);
      expect(names.take(4), ['JA1', 'Proficiency1', 'Other2', 'Other10']);
      expect(
        names.skip(4).every((name) => name == null || name.trim().isEmpty),
        isTrue,
      );
    },
  );
}
