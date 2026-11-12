import 'dart:async';

import 'package:intl/intl.dart';

import 'xp_repository.dart';

/// In-memory XP för lokal UX-utveckling utan Firebase.
class DevXpRepository implements XpRepository {
  final Map<String, int> _xpByDay = {};
  final StreamController<void> _tick = StreamController<void>.broadcast();

  String _todayId() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  void _emit() {
    if (!_tick.isClosed) _tick.add(null);
  }

  @override
  Stream<int> watchXpTotal(String uid) {
    return Stream<void>.multi((listener) {
      listener.add(null);
      final sub = _tick.stream.listen((_) => listener.add(null));
      listener.onCancel = () => sub.cancel();
    }).map((_) => _xpByDay.values.fold(0, (a, b) => a + b));
  }

  @override
  Stream<Map<String, int>> watchXpByDay(String uid) {
    return Stream<void>.multi((listener) {
      listener.add(null);
      final sub = _tick.stream.listen((_) => listener.add(null));
      listener.onCancel = () => sub.cancel();
    }).map((_) => Map<String, int>.from(_xpByDay));
  }

  @override
  Future<void> addXp(String uid, int amount) async {
    if (amount <= 0) return;
    final id = _todayId();
    _xpByDay[id] = (_xpByDay[id] ?? 0) + amount;
    _emit();
  }
}
