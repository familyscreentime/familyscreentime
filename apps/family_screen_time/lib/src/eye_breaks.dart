/// When the monitor announces, starts and ends the child's eye breaks.
///
/// Every [EyeBreakPolicy.every] of screen use on this device, a notice says
/// a break is coming; the child may put it off by a minute a few times.
/// Then the screen is veiled for the break's length, which grows with the
/// use since the last rest. The time under the veil is not screen time.
library;

import 'package:screentime_engine/screentime_engine.dart';

enum EyeStepKind {
  /// Nothing to show or change.
  none,

  /// Announce the break, with [EyeStep.snoozesLeft] put-offs offered.
  notice,

  /// Veil the screen until [EyeStep.until].
  veil,

  /// Reminder only: say to look into the distance for [EyeStep.length].
  reminder,

  /// Take down the notice or the veil.
  hide,
}

class EyeStep {
  final EyeStepKind kind;
  final int snoozesLeft;
  final Duration length;
  final DateTime? until;

  const EyeStep._(
    this.kind, {
    this.snoozesLeft = 0,
    this.length = Duration.zero,
    this.until,
  });

  static const none = EyeStep._(EyeStepKind.none);
  static const hide = EyeStep._(EyeStepKind.hide);
}

/// While a call is on (or parent mode), the break waits this long before
/// trying again.
const eyeBusyWait = Duration(seconds: 30);

/// A limit ending this soon makes the break wait: the block comes first.
const eyeBlockSoon = Duration(minutes: 2);

class EyeBreaks {
  /// Start of the stretch of use the current state belongs to.
  DateTime? _stretch;

  /// Put-offs used in this stretch.
  int _snoozed = 0;

  /// No break before this (put off, or a call going on).
  DateTime? _waitUntil;

  /// End of the notice shown; the veil follows.
  DateTime? _noticeUntil;

  /// End of the veil shown.
  DateTime? _veilUntil;

  /// The eyes last rested then: end of the last break, or of a mandatory
  /// break or a break the child took.
  DateTime? restedAt;

  bool get noticeShown => _noticeUntil != null;

  /// End of the veil, while it is shown at [now].
  DateTime? veilUntil(DateTime now) {
    final until = _veilUntil;
    return until != null && now.isBefore(until) ? until : null;
  }

  /// What to do at [now], given the start of the stretch of use going on
  /// ([stretchStart], `null`: the eyes rested) and whether a limit ends
  /// soon ([blockSoon]).
  EyeStep step({
    required EyeBreakPolicy policy,
    required DateTime? stretchStart,
    required DateTime now,
    bool blockSoon = false,
  }) {
    final shown = _noticeUntil != null || _veilUntil != null;
    if (!policy.enabled) {
      _clear();
      return shown ? EyeStep.hide : EyeStep.none;
    }
    final veil = _veilUntil;
    if (veil != null) {
      if (now.isBefore(veil)) return EyeStep.none;
      // The break is over.
      _veilUntil = null;
      restedAt = veil;
      _snoozed = 0;
      _waitUntil = null;
      _stretch = null;
      return EyeStep.hide;
    }
    if (stretchStart == null) {
      _clear();
      return shown ? EyeStep.hide : EyeStep.none;
    }
    if (stretchStart != _stretch) {
      // A new stretch of use: put-offs start again.
      _stretch = stretchStart;
      _snoozed = 0;
      _waitUntil = null;
    }
    final use = now.difference(stretchStart);
    final wait = _waitUntil;
    if (use < policy.every || (wait != null && now.isBefore(wait))) {
      return EyeStep.none;
    }
    final notice = _noticeUntil;
    if (notice == null) {
      // A block is about to come: it is a break of its own.
      if (blockSoon) return EyeStep.none;
      if (!policy.veil) {
        restedAt = now;
        _stretch = null;
        return EyeStep._(EyeStepKind.reminder, length: policy.lengthAfter(use));
      }
      _noticeUntil = now.add(EyeBreakPolicy.notice);
      return EyeStep._(
        EyeStepKind.notice,
        snoozesLeft: snoozesLeft(policy),
        length: policy.lengthAfter(use),
      );
    }
    if (now.isBefore(notice)) return EyeStep.none;
    _noticeUntil = null;
    final length = policy.lengthAfter(use);
    final until = now.add(length);
    _veilUntil = until;
    return EyeStep._(EyeStepKind.veil, length: length, until: until);
  }

  int snoozesLeft(EyeBreakPolicy policy) =>
      policy.snoozes > _snoozed ? policy.snoozes - _snoozed : 0;

  /// Time until the next step is due after [now], if any.
  Duration? next({
    required EyeBreakPolicy policy,
    required DateTime? stretchStart,
    required DateTime now,
  }) {
    if (!policy.enabled) return null;
    final at = _veilUntil ?? _noticeUntil ?? _waitUntil;
    if (at != null && at.isAfter(now)) return at.difference(now);
    if (stretchStart == null) return null;
    // Overdue and waiting (a limit about to end): the monitor's own
    // schedule looks again.
    final due = stretchStart.add(policy.every);
    return due.isAfter(now) ? due.difference(now) : null;
  }

  /// The child put the break off: a minute more, if any put-off is left.
  bool snooze(EyeBreakPolicy policy, DateTime now) {
    if (_noticeUntil == null || snoozesLeft(policy) == 0) return false;
    _snoozed++;
    _noticeUntil = null;
    _waitUntil = now.add(EyeBreakPolicy.snooze);
    return true;
  }

  /// The child chose to take the break now.
  void startNow(DateTime now) {
    if (_noticeUntil != null) _noticeUntil = now;
  }

  /// The break could not be shown (a call, parent mode): tried again a
  /// little later, without using a put-off.
  void busy(DateTime now) {
    _noticeUntil = null;
    _veilUntil = null;
    _waitUntil = now.add(eyeBusyWait);
  }

  /// The screen went off, or a block came: what was shown goes. Whether
  /// anything was shown.
  bool cancel() {
    final shown = _noticeUntil != null || _veilUntil != null;
    _noticeUntil = null;
    _veilUntil = null;
    return shown;
  }

  void _clear() {
    _stretch = null;
    _snoozed = 0;
    _waitUntil = null;
    _noticeUntil = null;
    _veilUntil = null;
  }
}
