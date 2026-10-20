/// School levels first, then the numeric group (JA2 before JA10).
int compareClassNames(String? first, String? second) {
  final a = _normalize(first);
  final b = _normalize(second);
  if (a.isEmpty || b.isEmpty) {
    return a.isEmpty == b.isEmpty ? 0 : (a.isEmpty ? 1 : -1);
  }
  final aLevel = _level(a);
  final bLevel = _level(b);
  final levelOrder = aLevel.$1.compareTo(bLevel.$1);
  if (levelOrder != 0) return levelOrder;
  return _naturalCompare(aLevel.$2, bLevel.$2);
}

String _normalize(String? name) =>
    (name ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

final _levels = [
  RegExp(r'^(prejunior|pj)(?=\d|$)'),
  RegExp(r'^(juniora|ja)(?=\d|$)'),
  RegExp(r'^(juniorb|jb)(?=\d|$)'),
  RegExp(r'^(seniora|sa)(?=\d|$)'),
  RegExp(r'^(seniorb|sb)(?=\d|$)'),
  RegExp(r'^(seniorc|sc)(?=\d|$)'),
  RegExp(r'^(seniord|sd)(?=\d|$)'),
  RegExp(r'^(prelower|pl)(?=\d|$)'),
  RegExp(r'^lower(?=\d|$)'),
  RegExp(r'^advanced(?=\d|$)'),
  RegExp(r'^proficiency(?=\d|$)'),
];

(int, String) _level(String name) {
  for (var index = 0; index < _levels.length; index++) {
    final match = _levels[index].firstMatch(name);
    if (match != null) return (index, name.substring(match.end));
  }
  return (_levels.length, name);
}

int _naturalCompare(String a, String b) {
  final chunks = RegExp(r'\d+|\D+');
  final aParts = chunks.allMatches(a).map((m) => m[0]!).toList();
  final bParts = chunks.allMatches(b).map((m) => m[0]!).toList();
  for (var index = 0; index < aParts.length && index < bParts.length; index++) {
    final aNumber = int.tryParse(aParts[index]);
    final bNumber = int.tryParse(bParts[index]);
    final comparison = aNumber != null && bNumber != null
        ? aNumber.compareTo(bNumber)
        : aParts[index].compareTo(bParts[index]);
    if (comparison != 0) return comparison;
  }
  return aParts.length.compareTo(bParts.length);
}
