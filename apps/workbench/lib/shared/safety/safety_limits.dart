import 'package:equatable/equatable.dart';

/// Limites de segurança aplicados pelo app, independentes da calibração da máquina.
class SafetyLimits extends Equatable {
  const SafetyLimits({this.maxForceKg = defaultMaxForceKg});

  /// Lê `--dart-define=MAX_FORCE_KG=<kg>`; sem ele, usa [defaultMaxForceKg].
  factory SafetyLimits.fromEnvironment() =>
      const SafetyLimits(maxForceKg: int.fromEnvironment('MAX_FORCE_KG', defaultValue: defaultMaxForceKg));

  /// Carga máxima padrão. Fica abaixo do menor `maxForce` possível do dispositivo (50 kg),
  /// para os primeiros testes serem sempre com carga baixa.
  static const defaultMaxForceKg = 30;

  /// Maior força, em kg, que o slider e o `ControlBloc` aceitam.
  final int maxForceKg;

  /// Faixa de força válida: da força mínima da calibração ([minForceKg]) até [maxForceKg].
  /// Nula quando o limite do app está abaixo do mínimo (nenhuma força é válida).
  ({int min, int max})? forceRange(int minForceKg) =>
      maxForceKg < minForceKg ? null : (min: minForceKg, max: maxForceKg);

  bool allowsForce(int kg, {int minForceKg = 0}) => kg >= minForceKg && kg <= maxForceKg;

  /// Só use com [forceRange] não nulo.
  int clampForce(int kg, {int minForceKg = 0}) => kg.clamp(minForceKg, maxForceKg);

  @override
  List<Object?> get props => [maxForceKg];
}
