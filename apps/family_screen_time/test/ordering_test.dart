import 'package:family_screen_time/src/ordering.dart';
import 'package:family_screen_time/src/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('children by name, without regard to case or accents', () {
    final sorted = childrenByName(const [
      Child(id: '1', name: 'zoé'),
      Child(id: '2', name: 'Léo'),
      Child(id: '3', name: 'Emma'),
      Child(id: '4', name: 'Élise'),
      Child(id: '5', name: 'lea'),
    ]);
    expect(sorted.map((c) => c.name), ['Élise', 'Emma', 'lea', 'Léo', 'zoé']);
  });

  test('devices: this one, the parents\', then each child\'s', () {
    const names = {'e': 'Emma', 'l': 'Léo'};
    final order = devicesInOrder(
      {
        'tabL': {'name': 'Tablette', 'role': 'child', 'childId': 'l'},
        'pcE': {'name': 'PC', 'role': 'child', 'childId': 'e'},
        'mum': {'name': 'Maman', 'role': 'parent'},
        'tabE': {'name': 'Tablette', 'role': 'child', 'childId': 'e'},
        'dad': {'name': 'Papa', 'role': 'parent'},
        'phoneL': {'name': 'Ancien téléphone', 'role': 'child', 'childId': 'l'},
      },
      here: 'tabE',
      childName: (id) => names[id],
    );
    expect(order, ['tabE', 'mum', 'dad', 'pcE', 'phoneL', 'tabL']);
  });
}
