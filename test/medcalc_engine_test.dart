import 'package:flutter_test/flutter_test.dart';
import 'package:my_mirai/features/medcalc/medcalc_engine.dart';

void main() {
  final engine = MedcalcEngine.instance;

  void assertCase({
    required MedcalcFormulaType formula,
    required Map<String, String> inputs,
    required String expected,
  }) {
    final result = engine.calculate(formula, inputs);
    expect(result.formattedResult, expected);
    expect(result.methodsMatch, isTrue);
  }

  test('golden bank: dose per kg cases', () {
    final cases = [
      ({'weightKg': '72', 'doseMgPerKg': '7'}, '504.00'),
      ({'weightKg': '60', 'doseMgPerKg': '5'}, '300.00'),
      ({'weightKg': '82', 'doseMgPerKg': '2.5'}, '205.00'),
      ({'weightKg': '45', 'doseMgPerKg': '1'}, '45.00'),
      ({'weightKg': '100', 'doseMgPerKg': '0.5'}, '50.00'),
      ({'weightKg': '68.5', 'doseMgPerKg': '7.5'}, '513.75'),
      ({'weightKg': '73.2', 'doseMgPerKg': '5'}, '366.00'),
    ];

    for (final c in cases) {
      assertCase(
        formula: MedcalcFormulaType.dosePerKg,
        inputs: c.$1,
        expected: c.$2,
      );
    }
  });

  test('golden bank: volume from concentration cases', () {
    final cases = [
      ({'doseMg': '500', 'concentrationMgPerMl': '50'}, '10.00'),
      ({'doseMg': '750', 'concentrationMgPerMl': '25'}, '30.00'),
      ({'doseMg': '125', 'concentrationMgPerMl': '5'}, '25.00'),
      ({'doseMg': '333', 'concentrationMgPerMl': '18'}, '18.50'),
      ({'doseMg': '600', 'concentrationMgPerMl': '37.5'}, '16.00'),
      ({'doseMg': '250', 'concentrationMgPerMl': '12.5'}, '20.00'),
    ];

    for (final c in cases) {
      assertCase(
        formula: MedcalcFormulaType.volumeFromConcentration,
        inputs: c.$1,
        expected: c.$2,
      );
    }
  });

  test('golden bank: infusion rate cases', () {
    final cases = [
      ({'totalVolumeMl': '1000', 'timeHours': '8'}, '125.00'),
      ({'totalVolumeMl': '250', 'timeHours': '2'}, '125.00'),
      ({'totalVolumeMl': '500', 'timeHours': '6'}, '83.33'),
      ({'totalVolumeMl': '750', 'timeHours': '12'}, '62.50'),
      ({'totalVolumeMl': '325', 'timeHours': '3.5'}, '92.86'),
      ({'totalVolumeMl': '480', 'timeHours': '4'}, '120.00'),
    ];

    for (final c in cases) {
      assertCase(
        formula: MedcalcFormulaType.infusionRate,
        inputs: c.$1,
        expected: c.$2,
      );
    }
  });

  test('golden bank: dilution C1V1=C2V2 cases', () {
    final cases = [
      ({
        'stockConcentration': '50',
        'targetConcentration': '10',
        'finalVolume': '100',
      }, '20.00'),
      ({
        'stockConcentration': '100',
        'targetConcentration': '20',
        'finalVolume': '250',
      }, '50.00'),
      ({
        'stockConcentration': '20',
        'targetConcentration': '5',
        'finalVolume': '100',
      }, '25.00'),
      ({
        'stockConcentration': '10',
        'targetConcentration': '1',
        'finalVolume': '50',
      }, '5.00'),
      ({
        'stockConcentration': '80',
        'targetConcentration': '20',
        'finalVolume': '500',
      }, '125.00'),
    ];

    for (final c in cases) {
      assertCase(
        formula: MedcalcFormulaType.dilutionC1V1EqualsC2V2,
        inputs: c.$1,
        expected: c.$2,
      );
    }
  });

  test('accepts comma decimal separator', () {
    assertCase(
      formula: MedcalcFormulaType.dosePerKg,
      inputs: {
        'weightKg': '70,5',
        'doseMgPerKg': '2,0',
      },
      expected: '141.00',
    );
  });

  test('rejects invalid numeric format', () {
    expect(
      () => engine.calculate(
        MedcalcFormulaType.dosePerKg,
        {
          'weightKg': 'sjuttio',
          'doseMgPerKg': '2',
        },
      ),
      throwsA(isA<MedcalcValidationException>()),
    );
  });

  test('rejects values outside safe range', () {
    expect(
      () => engine.calculate(
        MedcalcFormulaType.infusionRate,
        {
          'totalVolumeMl': '1000',
          'timeHours': '0',
        },
      ),
      throwsA(isA<MedcalcValidationException>()),
    );
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
