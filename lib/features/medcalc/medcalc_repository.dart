import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:my_mirai/features/medcalc/medcalc_engine.dart';

class MedcalcRepository {
  static const localFormulaVersion = 'v1-local';

  final FirebaseFirestore _firestore;
  final MedcalcEngine _engine;

  MedcalcRepository({
    FirebaseFirestore? firestore,
    MedcalcEngine? engine,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _engine = engine ?? MedcalcEngine.instance;

  Future<String> fetchActiveFormulaVersion() async {
    try {
      final query = await _firestore
          .collection('medcalc_formula_versions')
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();

      if (query.docs.isEmpty) return localFormulaVersion;

      final data = query.docs.first.data();
      final version = data['version']?.toString();
      if (version != null && version.trim().isNotEmpty) {
        return version.trim();
      }

      return query.docs.first.id;
    } catch (_) {
      return localFormulaVersion;
    }
  }

  Future<List<MedcalcExamQuestion>> fetchExamQuestions({
    int count = 8,
  }) async {
    try {
      final query = await _firestore
          .collection('medcalc_question_bank')
          .where('active', isEqualTo: true)
          .get();

      final candidates = <MedcalcExamQuestion>[];
      for (final doc in query.docs) {
        final data = doc.data();
        final formulaType = medcalcFormulaTypeFromCode(
          data['formulaType']?.toString() ?? '',
        );
        if (formulaType == null) continue;

        final rawMap = data['rawInputs'];
        if (rawMap is! Map) continue;

        final rawInputs = <String, String>{};
        rawMap.forEach((key, value) {
          if (key == null || value == null) return;
          final normalizedKey = key.toString().trim();
          final normalizedValue = value.toString().trim();
          if (normalizedKey.isEmpty || normalizedValue.isEmpty) return;
          rawInputs[normalizedKey] = normalizedValue;
        });

        if (rawInputs.isEmpty) continue;

        try {
          final result = _engine.calculate(formulaType, rawInputs);

          final expectedValueRaw = data['expectedValue']?.toString();
          if (expectedValueRaw != null && expectedValueRaw.trim().isNotEmpty) {
            final expectedValue = ExactDecimal.parse(expectedValueRaw);
            final matches = expectedValue.equalsRounded(
              result.finalValue,
              result.template.displayDecimals,
            );
            if (!matches) continue;
          }

          final expectedUnitRaw = data['expectedUnit']?.toString();
          if (expectedUnitRaw != null &&
              expectedUnitRaw.trim().isNotEmpty &&
              expectedUnitRaw.trim() != result.template.resultUnit) {
            continue;
          }

          final prompt = data['prompt']?.toString().trim();
          candidates.add(
            MedcalcExamQuestion(
              id: doc.id,
              formulaType: formulaType,
              prompt: (prompt == null || prompt.isEmpty)
                  ? _fallbackPrompt(formulaType, rawInputs, result.template.resultUnit)
                  : prompt,
              rawInputs: rawInputs,
              expected: result,
            ),
          );
        } on MedcalcValidationException {
          continue;
        }
      }

      if (candidates.isEmpty) {
        return MedcalcExamFactory.generate(count: count);
      }

      candidates.shuffle(Random());
      if (candidates.length <= count) return candidates;
      return candidates.take(count).toList();
    } catch (_) {
      return MedcalcExamFactory.generate(count: count);
    }
  }

  String _fallbackPrompt(
    MedcalcFormulaType formulaType,
    Map<String, String> rawInputs,
    String resultUnit,
  ) {
    switch (formulaType) {
      case MedcalcFormulaType.dosePerKg:
        return 'Patient väger ${rawInputs['weightKg']} kg och ordinationen är '
            '${rawInputs['doseMgPerKg']} mg/kg. Beräkna total dos i $resultUnit.';
      case MedcalcFormulaType.volumeFromConcentration:
        return 'Ordinerad dos ${rawInputs['doseMg']} mg och styrka '
            '${rawInputs['concentrationMgPerMl']} mg/ml. Beräkna volym i $resultUnit.';
      case MedcalcFormulaType.infusionRate:
        return 'Total volym ${rawInputs['totalVolumeMl']} ml på '
            '${rawInputs['timeHours']} timmar. Beräkna infusionshastighet i $resultUnit.';
      case MedcalcFormulaType.dilutionC1V1EqualsC2V2:
        return 'C1=${rawInputs['stockConcentration']} mg/ml, '
            'C2=${rawInputs['targetConcentration']} mg/ml, '
            'V2=${rawInputs['finalVolume']} ml. Beräkna V1 i $resultUnit.';
    }
  }
}
