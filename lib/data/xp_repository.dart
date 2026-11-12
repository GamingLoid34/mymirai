abstract class XpRepository {
  /// Ström av totalt antal XP.
  Stream<int> watchXpTotal(String uid);

  /// Ström av XP per dag (`yyyy-MM-dd` → xp), för veckoberäkning m.m.
  Stream<Map<String, int>> watchXpByDay(String uid);

  /// Lägger till [amount] XP för idag och ökar totalen.
  Future<void> addXp(String uid, int amount);
}
