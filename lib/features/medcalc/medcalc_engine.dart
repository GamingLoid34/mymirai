import 'dart:math';

enum MedcalcFormulaType {
  dosePerKg,
  volumeFromConcentration,
  infusionRate,
  dilutionC1V1EqualsC2V2,
}

extension MedcalcFormulaTypeX on MedcalcFormulaType {
  String get label {
    switch (this) {
      case MedcalcFormulaType.dosePerKg:
        return 'Dos (mg/kg)';
      case MedcalcFormulaType.volumeFromConcentration:
        return 'Volym från koncentration';
      case MedcalcFormulaType.infusionRate:
        return 'Infusionshastighet (ml/h)';
      case MedcalcFormulaType.dilutionC1V1EqualsC2V2:
        return 'Spädning (C1V1=C2V2)';
    }
  }

  String get shortCode {
    switch (this) {
      case MedcalcFormulaType.dosePerKg:
        return 'dose_per_kg';
      case MedcalcFormulaType.volumeFromConcentration:
        return 'volume_from_concentration';
      case MedcalcFormulaType.infusionRate:
        return 'infusion_rate';
      case MedcalcFormulaType.dilutionC1V1EqualsC2V2:
        return 'dilution_c1v1_c2v2';
    }
  }
}

class MedcalcValidationException implements Exception {
  final String message;

  MedcalcValidationException(this.message);

  @override
  String toString() => message;
}

/// Fast decimal med 6 fasta decimaler och BigInt för exakt matematik.
class ExactDecimal {
  static const _scaleDigits = 6;
  static final _scale = BigInt.from(10).pow(_scaleDigits);

  final BigInt _scaled;

  const ExactDecimal._(this._scaled);

  static ExactDecimal zero() => ExactDecimal._(BigInt.zero);

  static ExactDecimal fromInt(int value) {
    return ExactDecimal._(BigInt.from(value) * _scale);
  }

  static ExactDecimal parse(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    final match = RegExp(r'^-?\d+(\.\d+)?$').firstMatch(normalized);
    if (match == null) {
      throw MedcalcValidationException(
        'Ogiltigt tal: "$raw". Ange ett numeriskt värde, t.ex. 12.5',
      );
    }

    final negative = normalized.startsWith('-');
    final unsigned = negative ? normalized.substring(1) : normalized;
    final parts = unsigned.split('.');
    final wholePart = parts[0];
    final fractionPart = parts.length > 1 ? parts[1] : '';

    if (fractionPart.length > _scaleDigits) {
      throw MedcalcValidationException(
        'För många decimaler i "$raw". Max $_scaleDigits decimaler tillåts.',
      );
    }

    final whole = BigInt.parse(wholePart) * _scale;
    final paddedFraction = fractionPart.padRight(_scaleDigits, '0');
    final fraction = BigInt.parse(paddedFraction);
    final scaled = whole + fraction;

    return ExactDecimal._(negative ? -scaled : scaled);
  }

  ExactDecimal operator +(ExactDecimal other) {
    return ExactDecimal._(_scaled + other._scaled);
  }

  ExactDecimal operator -(ExactDecimal other) {
    return ExactDecimal._(_scaled - other._scaled);
  }

  ExactDecimal multiply(ExactDecimal other) {
    final numerator = _scaled * other._scaled;
    return ExactDecimal._(_divRound(numerator, _scale));
  }

  ExactDecimal divide(ExactDecimal other) {
    if (other._scaled == BigInt.zero) {
      throw MedcalcValidationException('Division med noll är inte tillåten.');
    }
    final numerator = _scaled * _scale;
    return ExactDecimal._(_divRound(numerator, other._scaled));
  }

  ExactDecimal roundTo(int decimals) {
    if (decimals < 0 || decimals > _scaleDigits) {
      throw ArgumentError.value(decimals, 'decimals');
    }
    final factor = BigInt.from(10).pow(_scaleDigits - decimals);
    final rounded = _divRound(_scaled, factor) * factor;
    return ExactDecimal._(rounded);
  }

  bool equalsRounded(ExactDecimal other, int decimals) {
    return roundTo(decimals)._scaled == other.roundTo(decimals)._scaled;
  }

  bool greaterThan(ExactDecimal other) => _scaled > other._scaled;
  bool lessThan(ExactDecimal other) => _scaled < other._scaled;
  bool lessThanOrEqual(ExactDecimal other) => _scaled <= other._scaled;
  bool greaterThanOrEqual(ExactDecimal other) => _scaled >= other._scaled;

  String format([int decimals = 2]) {
    if (decimals < 0 || decimals > _scaleDigits) {
      throw ArgumentError.value(decimals, 'decimals');
    }

    final rounded = roundTo(decimals);
    final negative = rounded._scaled.isNegative;
    final abs = rounded._scaled.abs();
    final denominator = BigInt.from(10).pow(_scaleDigits);
    final whole = abs ~/ denominator;
    final fractionAll = abs % denominator;

    if (decimals == 0) {
      return '${negative ? '-' : ''}$whole';
    }

    final reduceFactor = BigInt.from(10).pow(_scaleDigits - decimals);
    final fraction = fractionAll ~/ reduceFactor;
    final fractionText = fraction.toString().padLeft(decimals, '0');
    return '${negative ? '-' : ''}$whole.$fractionText';
  }

  double toDouble() {
    return _scaled.toDouble() / _scale.toDouble();
  }

  static BigInt _divRound(BigInt numerator, BigInt denominator) {
    if (denominator == BigInt.zero) {
      throw MedcalcValidationException('Internt fel: division med noll.');
    }

    final sameSign = numerator.isNegative == denominator.isNegative;
    final absNum = numerator.abs();
    final absDen = denominator.abs();
    var quotient = absNum ~/ absDen;
    final remainder = absNum % absDen;
    if (remainder * BigInt.from(2) >= absDen) {
      quotient += BigInt.one;
    }
    return sameSign ? quotient : -quotient;
  }
}

class MedcalcInputDefinition {
  final String key;
  final String label;
  final String unit;
  final String hint;
  final ExactDecimal min;
  final ExactDecimal max;

  const MedcalcInputDefinition({
    required this.key,
    required this.label,
    required this.unit,
    required this.hint,
    required this.min,
    required this.max,
  });
}

class MedcalcTemplate {
  final MedcalcFormulaType formulaType;
  final String title;
  final String description;
  final String resultUnit;
  final int displayDecimals;
  final List<MedcalcInputDefinition> inputs;

  const MedcalcTemplate({
    required this.formulaType,
    required this.title,
    required this.description,
    required this.resultUnit,
    required this.displayDecimals,
    required this.inputs,
  });
}

class MedcalcResult {
  final MedcalcTemplate template;
  final Map<String, ExactDecimal> normalizedInputs;
  final ExactDecimal methodA;
  final ExactDecimal methodB;
  final ExactDecimal finalValue;
  final bool methodsMatch;
  final List<String> steps;

  const MedcalcResult({
    required this.template,
    required this.normalizedInputs,
    required this.methodA,
    required this.methodB,
    required this.finalValue,
    required this.methodsMatch,
    required this.steps,
  });

  String get formattedResult => finalValue.format(template.displayDecimals);
  String get formattedMethodA => methodA.format(template.displayDecimals);
  String get formattedMethodB => methodB.format(template.displayDecimals);
}

class MedcalcEngine {
  static final instance = MedcalcEngine._();

  MedcalcEngine._();

  static final _thousand = ExactDecimal.fromInt(1000);
  static final _sixty = ExactDecimal.fromInt(60);

  static final templates = <MedcalcTemplate>[
    MedcalcTemplate(
      formulaType: MedcalcFormulaType.dosePerKg,
      title: 'Dosberäkning (mg/kg)',
      description: 'Beräkna total ordinerad dos från vikt och mg/kg.',
      resultUnit: 'mg',
      displayDecimals: 2,
      inputs: [
        MedcalcInputDefinition(
          key: 'weightKg',
          label: 'Patientvikt',
          unit: 'kg',
          hint: 't.ex. 72',
          min: ExactDecimal._(BigInt.from(1000000)),
          max: ExactDecimal._(BigInt.from(300000000)),
        ),
        MedcalcInputDefinition(
          key: 'doseMgPerKg',
          label: 'Ordination',
          unit: 'mg/kg',
          hint: 't.ex. 7.5',
          min: ExactDecimal._(BigInt.from(10000)),
          max: ExactDecimal._(BigInt.from(100000000)),
        ),
      ],
    ),
    MedcalcTemplate(
      formulaType: MedcalcFormulaType.volumeFromConcentration,
      title: 'Volym från koncentration',
      description: 'Beräkna ml från ordinerad mg och styrka mg/ml.',
      resultUnit: 'ml',
      displayDecimals: 2,
      inputs: [
        MedcalcInputDefinition(
          key: 'doseMg',
          label: 'Ordinerad dos',
          unit: 'mg',
          hint: 't.ex. 500',
          min: ExactDecimal._(BigInt.from(1000)),
          max: ExactDecimal._(BigInt.from(1000000000)),
        ),
        MedcalcInputDefinition(
          key: 'concentrationMgPerMl',
          label: 'Styrka',
          unit: 'mg/ml',
          hint: 't.ex. 50',
          min: ExactDecimal._(BigInt.from(1000)),
          max: ExactDecimal._(BigInt.from(100000000)),
        ),
      ],
    ),
    MedcalcTemplate(
      formulaType: MedcalcFormulaType.infusionRate,
      title: 'Infusionshastighet',
      description: 'Beräkna ml/h från total volym och infusionstid.',
      resultUnit: 'ml/h',
      displayDecimals: 2,
      inputs: [
        MedcalcInputDefinition(
          key: 'totalVolumeMl',
          label: 'Total volym',
          unit: 'ml',
          hint: 't.ex. 1000',
          min: ExactDecimal._(BigInt.from(1000)),
          max: ExactDecimal._(BigInt.from(500000000)),
        ),
        MedcalcInputDefinition(
          key: 'timeHours',
          label: 'Tid',
          unit: 'h',
          hint: 't.ex. 8',
          min: ExactDecimal._(BigInt.from(10000)),
          max: ExactDecimal._(BigInt.from(168000000)),
        ),
      ],
    ),
    MedcalcTemplate(
      formulaType: MedcalcFormulaType.dilutionC1V1EqualsC2V2,
      title: 'Spädning (C1V1=C2V2)',
      description: 'Beräkna hur mycket stocklösning (V1) som behövs.',
      resultUnit: 'ml',
      displayDecimals: 2,
      inputs: [
        MedcalcInputDefinition(
          key: 'stockConcentration',
          label: 'C1 (stock)',
          unit: 'mg/ml',
          hint: 't.ex. 50',
          min: ExactDecimal._(BigInt.from(1000)),
          max: ExactDecimal._(BigInt.from(100000000)),
        ),
        MedcalcInputDefinition(
          key: 'targetConcentration',
          label: 'C2 (mål)',
          unit: 'mg/ml',
          hint: 't.ex. 10',
          min: ExactDecimal._(BigInt.from(1000)),
          max: ExactDecimal._(BigInt.from(100000000)),
        ),
        MedcalcInputDefinition(
          key: 'finalVolume',
          label: 'V2 (slutvolym)',
          unit: 'ml',
          hint: 't.ex. 100',
          min: ExactDecimal._(BigInt.from(1000)),
          max: ExactDecimal._(BigInt.from(1000000000)),
        ),
      ],
    ),
  ];

  MedcalcTemplate templateFor(MedcalcFormulaType formulaType) {
    return templates.firstWhere((template) => template.formulaType == formulaType);
  }

  MedcalcResult calculate(
    MedcalcFormulaType formulaType,
    Map<String, String> rawInputs,
  ) {
    final template = templateFor(formulaType);
    final values = <String, ExactDecimal>{};

    for (final input in template.inputs) {
      final raw = rawInputs[input.key] ?? '';
      final value = ExactDecimal.parse(raw);
      if (value.lessThan(input.min) || value.greaterThan(input.max)) {
        throw MedcalcValidationException(
          '${input.label} måste vara mellan '
          '${input.min.format(2)} och ${input.max.format(2)} ${input.unit}.',
        );
      }
      values[input.key] = value;
    }

    late ExactDecimal methodA;
    late ExactDecimal methodB;
    late List<String> steps;

    switch (formulaType) {
      case MedcalcFormulaType.dosePerKg:
        final weight = values['weightKg']!;
        final dose = values['doseMgPerKg']!;
        methodA = weight.multiply(dose);
        methodB = dose.multiply(weight);
        steps = [
          'Formel: total dos (mg) = vikt (kg) x ordination (mg/kg)',
          '${weight.format(2)} x ${dose.format(2)} = ${methodA.format(2)} mg',
        ];
        break;
      case MedcalcFormulaType.volumeFromConcentration:
        final dose = values['doseMg']!;
        final concentration = values['concentrationMgPerMl']!;
        methodA = dose.divide(concentration);
        // Alternativ kontroll: konvertera till g och räkna om.
        final doseInGrams = dose.divide(_thousand);
        final concentrationInGramsPerMl = concentration.divide(_thousand);
        methodB = doseInGrams.divide(concentrationInGramsPerMl);
        steps = [
          'Formel: volym (ml) = ordinerad dos (mg) / styrka (mg/ml)',
          '${dose.format(2)} / ${concentration.format(2)} = ${methodA.format(2)} ml',
        ];
        break;
      case MedcalcFormulaType.infusionRate:
        final totalVolume = values['totalVolumeMl']!;
        final hours = values['timeHours']!;
        methodA = totalVolume.divide(hours);
        final minutes = hours.multiply(_sixty);
        methodB = totalVolume.multiply(_sixty).divide(minutes);
        steps = [
          'Formel: infusionshastighet (ml/h) = total volym (ml) / tid (h)',
          '${totalVolume.format(2)} / ${hours.format(2)} = ${methodA.format(2)} ml/h',
        ];
        break;
      case MedcalcFormulaType.dilutionC1V1EqualsC2V2:
        final c1 = values['stockConcentration']!;
        final c2 = values['targetConcentration']!;
        final v2 = values['finalVolume']!;
        if (c2.greaterThan(c1)) {
          throw MedcalcValidationException(
            'C2 kan inte vara högre än C1 i en spädning.',
          );
        }
        methodA = c2.multiply(v2).divide(c1);
        final ratio = c1.divide(c2);
        methodB = v2.divide(ratio);
        steps = [
          'Formel: C1V1 = C2V2  =>  V1 = (C2 x V2) / C1',
          '(${c2.format(2)} x ${v2.format(2)}) / ${c1.format(2)} = ${methodA.format(2)} ml',
        ];
        break;
    }

    final methodsMatch = methodA.equalsRounded(methodB, 4);
    if (!methodsMatch) {
      throw MedcalcValidationException(
        'Intern dubbelberäkning matchar inte. Ingen uträkning visas.',
      );
    }

    final finalValue = methodA.roundTo(template.displayDecimals);

    return MedcalcResult(
      template: template,
      normalizedInputs: values,
      methodA: methodA,
      methodB: methodB,
      finalValue: finalValue,
      methodsMatch: methodsMatch,
      steps: steps,
    );
  }
}

class MedcalcExamQuestion {
  final String id;
  final MedcalcFormulaType formulaType;
  final String prompt;
  final Map<String, String> rawInputs;
  final MedcalcResult expected;

  const MedcalcExamQuestion({
    required this.id,
    required this.formulaType,
    required this.prompt,
    required this.rawInputs,
    required this.expected,
  });
}

class MedcalcExamFactory {
  static List<MedcalcExamQuestion> generate({int count = 8, int? seed}) {
    final random = Random(seed ?? DateTime.now().millisecondsSinceEpoch);
    final engine = MedcalcEngine.instance;
    final formulas = MedcalcFormulaType.values;
    final questions = <MedcalcExamQuestion>[];

    for (var i = 0; i < count; i++) {
      final formulaType = formulas[i % formulas.length];
      final inputs = _generateInputs(formulaType, random);
      final result = engine.calculate(formulaType, inputs);
      final prompt = _buildPrompt(formulaType, inputs, result.template.resultUnit);
      questions.add(
        MedcalcExamQuestion(
          id: '${formulaType.shortCode}-$i',
          formulaType: formulaType,
          prompt: prompt,
          rawInputs: inputs,
          expected: result,
        ),
      );
    }

    return questions;
  }

  static String _buildPrompt(
    MedcalcFormulaType type,
    Map<String, String> rawInputs,
    String resultUnit,
  ) {
    switch (type) {
      case MedcalcFormulaType.dosePerKg:
        return 'Patient väger ${rawInputs['weightKg']} kg. Ordination '
            '${rawInputs['doseMgPerKg']} mg/kg. Beräkna total dos i $resultUnit.';
      case MedcalcFormulaType.volumeFromConcentration:
        return 'Ordinerad dos är ${rawInputs['doseMg']} mg och styrkan är '
            '${rawInputs['concentrationMgPerMl']} mg/ml. Beräkna volym i $resultUnit.';
      case MedcalcFormulaType.infusionRate:
        return 'Total volym ${rawInputs['totalVolumeMl']} ml ska ges på '
            '${rawInputs['timeHours']} timmar. Beräkna infusionshastighet i $resultUnit.';
      case MedcalcFormulaType.dilutionC1V1EqualsC2V2:
        return 'C1=${rawInputs['stockConcentration']} mg/ml, '
            'C2=${rawInputs['targetConcentration']} mg/ml, '
            'V2=${rawInputs['finalVolume']} ml. Beräkna V1 i $resultUnit.';
    }
  }

  static Map<String, String> _generateInputs(
    MedcalcFormulaType type,
    Random random,
  ) {
    String decimal(num value) {
      if (value is int) return value.toString();
      final text = value.toStringAsFixed(1);
      return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
    }

    switch (type) {
      case MedcalcFormulaType.dosePerKg:
        final weight = 45 + random.nextInt(56); // 45-100
        final dose = (2 + random.nextInt(18)) / 2; // 1.0-10.0 step 0.5
        return {
          'weightKg': weight.toString(),
          'doseMgPerKg': decimal(dose),
        };
      case MedcalcFormulaType.volumeFromConcentration:
        final dose = [125, 250, 500, 750, 1000][random.nextInt(5)];
        final concentration = [5, 10, 20, 25, 50][random.nextInt(5)];
        return {
          'doseMg': dose.toString(),
          'concentrationMgPerMl': concentration.toString(),
        };
      case MedcalcFormulaType.infusionRate:
        final volume = [250, 500, 750, 1000][random.nextInt(4)];
        final hours = [2, 4, 6, 8, 12, 24][random.nextInt(6)];
        return {
          'totalVolumeMl': volume.toString(),
          'timeHours': hours.toString(),
        };
      case MedcalcFormulaType.dilutionC1V1EqualsC2V2:
        final stock = [10, 20, 50, 100][random.nextInt(4)];
        final targetOptions = [1, 2, 5, 10, 20].where((v) => v < stock).toList();
        final target = targetOptions[random.nextInt(targetOptions.length)];
        final finalVolume = [50, 100, 250, 500][random.nextInt(4)];
        return {
          'stockConcentration': stock.toString(),
          'targetConcentration': target.toString(),
          'finalVolume': finalVolume.toString(),
        };
    }
  }
}
