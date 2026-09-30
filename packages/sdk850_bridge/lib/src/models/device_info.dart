import 'machine_event.dart';

/// Versão do controlador (`DeviceInfo` do SDK), evento `deviceInfo`.
class DeviceInfo extends MachineEvent {
  const DeviceInfo({
    required this.softwareNum,
    required this.versionCode,
    required this.produceCode,
  });

  factory DeviceInfo.fromMap(Map<String, Object?> map) => DeviceInfo(
        softwareNum: readString(map, 'softwareNum'),
        versionCode: readInt(map, 'versionCode'),
        produceCode: readString(map, 'produceCode'),
      );

  final String softwareNum;
  final int versionCode;
  final String produceCode;

  @override
  String get type => 'deviceInfo';

  @override
  Map<String, Object?> toMap() => {
        'type': type,
        'softwareNum': softwareNum,
        'versionCode': versionCode,
        'produceCode': produceCode,
      };

  @override
  List<Object?> get props => [softwareNum, versionCode, produceCode];
}
