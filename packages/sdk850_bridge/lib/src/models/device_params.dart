import 'package:equatable/equatable.dart';

import 'machine_event.dart';

/// Campo de calibração de [DeviceParams], com faixa e unidade do Javadoc.
///
/// [key] é o nome do campo no canal e no SDK (inclui a grafia `orgin...` do fabricante).
enum DeviceParamField {
  minForce('minForce', 5, 20, 'kg'),
  maxForce('maxForce', 50, 150, 'kg'),
  inactiveForce('inactiveForce', 2, 20, 'kg'),
  maxLength('maxLength', 10, 255, 'cm'),
  ratedSpeed('ratedSpeed', 1, 2000, 'rpm'),
  ropeGuideDiameter('ropeGuideDiameter', 1, 255, 'cm'),
  orginMinDistance('orginMinDistance', 1, 50, 'cm'),
  orginMaxDistance('orginMaxDistance', 2, 100, 'cm'),
  velocityRange('velocityRange', 0, 50, ''),
  torqueVariationCycle('torqueVariationCycle', 0, 100, ''),
  torqueCoefficient('torqueCoefficient', 1, 20, '');

  const DeviceParamField(this.key, this.min, this.max, this.unit);

  final String key;
  final int min;
  final int max;
  final String unit;

  /// Mensagem de faixa, por exemplo "Entre 5 e 20 kg".
  String get rangeLabel => unit.isEmpty ? 'Entre $min e $max' : 'Entre $min e $max $unit';
}

/// Parâmetros de calibração do dispositivo (`DeviceParams` do SDK).
class DeviceParams extends Equatable {
  const DeviceParams({
    required this.minForce,
    required this.maxForce,
    required this.inactiveForce,
    required this.maxLength,
    required this.ratedSpeed,
    required this.ropeGuideDiameter,
    required this.orginMinDistance,
    required this.orginMaxDistance,
    required this.velocityRange,
    required this.torqueVariationCycle,
    required this.torqueCoefficient,
  });

  factory DeviceParams.fromMap(Map<String, Object?> map) => DeviceParams(
        minForce: readInt(map, 'minForce'),
        maxForce: readInt(map, 'maxForce'),
        inactiveForce: readInt(map, 'inactiveForce'),
        maxLength: readInt(map, 'maxLength'),
        ratedSpeed: readInt(map, 'ratedSpeed'),
        ropeGuideDiameter: readInt(map, 'ropeGuideDiameter'),
        orginMinDistance: readInt(map, 'orginMinDistance'),
        orginMaxDistance: readInt(map, 'orginMaxDistance'),
        velocityRange: readInt(map, 'velocityRange'),
        torqueVariationCycle: readInt(map, 'torqueVariationCycle'),
        torqueCoefficient: readInt(map, 'torqueCoefficient'),
      );

  /// Valores iniciais de um formulário vazio: o limite inferior de cada faixa.
  factory DeviceParams.lowerBounds() => DeviceParams(
        minForce: DeviceParamField.minForce.min,
        maxForce: DeviceParamField.maxForce.min,
        inactiveForce: DeviceParamField.inactiveForce.min,
        maxLength: DeviceParamField.maxLength.min,
        ratedSpeed: DeviceParamField.ratedSpeed.min,
        ropeGuideDiameter: DeviceParamField.ropeGuideDiameter.min,
        orginMinDistance: DeviceParamField.orginMinDistance.min,
        orginMaxDistance: DeviceParamField.orginMaxDistance.min,
        velocityRange: DeviceParamField.velocityRange.min,
        torqueVariationCycle: DeviceParamField.torqueVariationCycle.min,
        torqueCoefficient: DeviceParamField.torqueCoefficient.min,
      );

  final int minForce;
  final int maxForce;
  final int inactiveForce;
  final int maxLength;
  final int ratedSpeed;
  final int ropeGuideDiameter;
  final int orginMinDistance;
  final int orginMaxDistance;
  final int velocityRange;
  final int torqueVariationCycle;
  final int torqueCoefficient;

  int valueOf(DeviceParamField field) => switch (field) {
        DeviceParamField.minForce => minForce,
        DeviceParamField.maxForce => maxForce,
        DeviceParamField.inactiveForce => inactiveForce,
        DeviceParamField.maxLength => maxLength,
        DeviceParamField.ratedSpeed => ratedSpeed,
        DeviceParamField.ropeGuideDiameter => ropeGuideDiameter,
        DeviceParamField.orginMinDistance => orginMinDistance,
        DeviceParamField.orginMaxDistance => orginMaxDistance,
        DeviceParamField.velocityRange => velocityRange,
        DeviceParamField.torqueVariationCycle => torqueVariationCycle,
        DeviceParamField.torqueCoefficient => torqueCoefficient,
      };

  DeviceParams withField(DeviceParamField field, int value) => DeviceParams(
        minForce: field == DeviceParamField.minForce ? value : minForce,
        maxForce: field == DeviceParamField.maxForce ? value : maxForce,
        inactiveForce: field == DeviceParamField.inactiveForce ? value : inactiveForce,
        maxLength: field == DeviceParamField.maxLength ? value : maxLength,
        ratedSpeed: field == DeviceParamField.ratedSpeed ? value : ratedSpeed,
        ropeGuideDiameter:
            field == DeviceParamField.ropeGuideDiameter ? value : ropeGuideDiameter,
        orginMinDistance:
            field == DeviceParamField.orginMinDistance ? value : orginMinDistance,
        orginMaxDistance:
            field == DeviceParamField.orginMaxDistance ? value : orginMaxDistance,
        velocityRange: field == DeviceParamField.velocityRange ? value : velocityRange,
        torqueVariationCycle:
            field == DeviceParamField.torqueVariationCycle ? value : torqueVariationCycle,
        torqueCoefficient:
            field == DeviceParamField.torqueCoefficient ? value : torqueCoefficient,
      );

  /// Campos fora da faixa do Javadoc, com a mensagem de erro de cada um.
  /// Vazio quando todos os valores são válidos.
  Map<DeviceParamField, String> validate() => {
        for (final field in DeviceParamField.values)
          if (valueOf(field) < field.min || valueOf(field) > field.max)
            field: field.rangeLabel,
      };

  Map<String, Object?> toMap() => {
        for (final field in DeviceParamField.values) field.key: valueOf(field),
      };

  @override
  List<Object?> get props => [for (final field in DeviceParamField.values) valueOf(field)];
}
