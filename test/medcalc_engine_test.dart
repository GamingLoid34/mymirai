import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/features/medcalc/medcalc_engine.dart';

void main() {
  final engine = MedcalcEngine.instance;

  test('dose per kg is deterministic and correct', () {
    final result = engine.calculate(
      MedcalcFormulaType.dosePerKg,
      {
        'weightKg': '72',
        'doseMgPerKg': '7',
      },
    );

    expect(result.formattedResult, '504.00');
    expect(result.methodsMatch, isTrue);
  });

  test('volume from concentration calculates ml correctly', () {
    final result = engine.calculate(
      MedcalcFormulaType.volumeFromConcentration,
      {
        'doseMg': '500',
        'concentrationMgPerMl': '50',
      },
    );

    expect(result.formattedResult, '10.00');
    expect(result.methodsMatch, isTrue);
  });

  test('infusion rate calculates ml per hour', () {
    final result = engine.calculate(
      MedcalcFormulaType.infusionRate,
      {
        'totalVolumeMl': '1000',
        'timeHours': '8',
      },
    );

    expect(result.formattedResult, '125.00');
    expect(result.methodsMatch, isTrue);
  });

  test('dilution calculates V1 correctly from C1V1=C2V2', () {
    final result = engine.calculate(
      MedcalcFormulaType.dilutionC1V1EqualsC2V2,
      {
        'stockConcentration': '50',
        'targetConcentration': '10',
        'finalVolume': '100',
      },
    );

    expect(result.formattedResult, '20.00');
    expect(result.methodsMatch, isTrue);
  });

  test('dilution rejects impossible concentration setup', () {
    expect(
      () => engine.calculate(
        MedcalcFormulaType.dilutionC1V1EqualsC2V2,
        {
          'stockConcentration': '5',
          'targetConcentration': '10',
          'finalVolume': '100',
        },
      ),
      throwsA(isA<MedcalcValidationException>()),
    );
  });
}
