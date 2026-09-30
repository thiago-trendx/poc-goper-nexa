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

  bool allowsForce(int kg) => kg >= 0 && kg <= maxForceKg;

  int clampForce(int kg) => kg.clamp(0, maxForceKg);

  @override
  List<Object?> get props => [maxForceKg];
}
