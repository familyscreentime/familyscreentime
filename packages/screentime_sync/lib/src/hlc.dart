/// Hybrid logical clock: close to the wall clock, yet ordering every event
/// after those its device had seen, even when clocks disagree.
library;

/// A point of a hybrid logical clock. Ordered by time, then counter, then
/// device, so two devices never produce equal points.
class Hlc implements Comparable<Hlc> {
  /// Milliseconds since the epoch, UTC.
  final int millis;
  final int counter;

  /// The device that produced it.
  final String node;

  const Hlc(this.millis, this.counter, this.node);

  static const zero = Hlc(0, 0, '');

  /// Text form, sorting like the clock: `millis:counter:node`.
  String pack() =>
      '${millis.toString().padLeft(15, '0')}:'
      '${counter.toRadixString(16).padLeft(4, '0')}:$node';

  factory Hlc.parse(String s) {
    final first = s.indexOf(':');
    final second = s.indexOf(':', first + 1);
    if (first < 0 || second < 0) throw FormatException('Bad clock', s);
    return Hlc(
      int.parse(s.substring(0, first)),
      int.parse(s.substring(first + 1, second), radix: 16),
      s.substring(second + 1),
    );
  }

  @override
  int compareTo(Hlc other) {
    if (millis != other.millis) return millis.compareTo(other.millis);
    if (counter != other.counter) return counter.compareTo(other.counter);
    return node.compareTo(other.node);
  }

  bool operator >(Hlc other) => compareTo(other) > 0;
  bool operator <(Hlc other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.millis == millis &&
      other.counter == counter &&
      other.node == node;

  @override
  int get hashCode => Object.hash(millis, counter, node);

  @override
  String toString() => pack();
}

/// The clock of one device.
class HlcClock {
  final String node;
  Hlc _last;

  /// A remote clock this far ahead of the wall clock is not followed: a
  /// device set to next year must not drag the family's clocks along.
  static const maxDrift = Duration(hours: 24);

  HlcClock(this.node, [Hlc? last]) : _last = last ?? Hlc.zero;

  Hlc get last => _last;

  /// A new point, after every point seen so far.
  Hlc now([DateTime? wall]) {
    final w = (wall ?? DateTime.now()).millisecondsSinceEpoch;
    _last = w > _last.millis
        ? Hlc(w, 0, node)
        : Hlc(_last.millis, _last.counter + 1, node);
    return _last;
  }

  /// Takes in a point from another device.
  void receive(Hlc remote, [DateTime? wall]) {
    final w = (wall ?? DateTime.now()).millisecondsSinceEpoch;
    if (remote.millis > w + maxDrift.inMilliseconds) return;
    final m = [w, _last.millis, remote.millis].reduce((a, b) => a > b ? a : b);
    final int c;
    if (m == _last.millis && m == remote.millis) {
      c = (_last.counter > remote.counter ? _last.counter : remote.counter) + 1;
    } else if (m == _last.millis) {
      c = _last.counter + 1;
    } else if (m == remote.millis) {
      c = remote.counter + 1;
    } else {
      c = 0;
    }
    _last = Hlc(m, c, node);
  }
}
