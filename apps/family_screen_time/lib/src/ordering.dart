/// The order children and devices are shown in: by name, as a person
/// reads them (without regard to case or accents), whatever order they
/// were added in.
library;

import 'store.dart' show Child;

// Accented letters and the plain ones they sort with.
const _accented = 'àáâäãåçèéêëìíîïñòóôöõøùúûüýÿ';
const _plain = 'aaaaaaceeeeiiiinoooooouuuuyy';
const _pairs = {'æ': 'ae', 'œ': 'oe', 'ß': 'ss'};

/// [name] as it is sorted: lower case, without accents.
String sortKey(String name) {
  final b = StringBuffer();
  for (final ch in name.trim().toLowerCase().split('')) {
    final i = _accented.indexOf(ch);
    b.write(i >= 0 ? _plain[i] : _pairs[ch] ?? ch);
  }
  return b.toString();
}

/// Names in reading order; names that differ only by accents or case
/// keep a fixed order between them.
int compareNames(String a, String b) {
  final c = sortKey(a).compareTo(sortKey(b));
  return c != 0 ? c : a.compareTo(b);
}

/// [children] by name.
List<Child> childrenByName(Iterable<Child> children) =>
    [...children]..sort((a, b) {
      final c = compareNames(a.name, b.name);
      return c != 0 ? c : a.id.compareTo(b.id);
    });

/// The ids of [devices] (as the sync log holds them: name, role, child)
/// in the order shown: [here] first, then the parents' devices, then each
/// child's, children by name ([childName]), and by name within each.
List<String> devicesInOrder(
  Map<String, Map<String, Object?>> devices, {
  String? here,
  required String? Function(String? childId) childName,
}) {
  int rank(String id) {
    if (id == here) return 0;
    final childId = devices[id]?['childId'];
    return childId is String ? 2 : 1;
  }

  String child(String id) {
    final childId = devices[id]?['childId'] as String?;
    return childName(childId) ?? childId ?? '';
  }

  String name(String id) => devices[id]?['name'] as String? ?? id;

  return devices.keys.toList()..sort((a, b) {
    var c = rank(a).compareTo(rank(b));
    if (c == 0) c = compareNames(child(a), child(b));
    if (c == 0) c = compareNames(name(a), name(b));
    return c != 0 ? c : a.compareTo(b);
  });
}
