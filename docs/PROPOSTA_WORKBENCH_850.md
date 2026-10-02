# Proposta de desenvolvimento — Workbench 850 (Flutter + SDK 850)

> Documento de referência para o desenvolvimento assistido pelo Claude Code.
> Coloque este arquivo em `docs/PROPOSTA_WORKBENCH_850.md` e referencie-o no `CLAUDE.md` da raiz do repositório.

## 1. Objetivo

Criar um app Flutter de bancada para a equipe de engenharia. Ele deve:

- conectar à máquina de força 850 via serial;
- exercitar **todos os comandos** do SDK do fabricante;
- exibir e gravar a telemetria em tempo real.

O app é uma ferramenta interna de teste, não o produto final. A ponte nativa criada aqui será reaproveitada no app de produto.

## 2. Decisões já tomadas

| # | Decisão | Consequência |
| --- | --- | --- |
| D1 | O app é em **Flutter**, com gerenciamento de estado em **BLoC** (`flutter_bloc`). | Toda a lógica de tela fica em Blocs/Cubits. Widgets não chamam a ponte diretamente. |
| D2 | A ponte com o SDK é um **plugin Flutter separado** (`sdk850_bridge`), só para Android. | O código Kotlin que usa o SDK fica isolado e pode ser reusado por outros apps. |
| D3 | O `.aar` do fabricante é **publicado num repositório Maven** (local ou interno da empresa) e consumido como dependência normal. | Evita o erro do Android Gradle Plugin *"Direct local .aar file dependencies are not supported when building an AAR"* em módulos de biblioteca. |
| D4 | O polling do comando de controle roda **no lado nativo (Kotlin)**, não no Dart. | Travamentos da UI não atrasam os comandos enviados ao controlador. |
| D5 | Existe um **gateway falso** (`FakeMachineGateway`) em Dart. | A UI e os Blocs podem ser desenvolvidos e testados sem hardware. |

## 3. Material de referência do fabricante

O pacote `850_SDK.zip` foi enviado pela fábrica. Copie o conteúdo relevante para `third_party/sdk850/` no repositório:

- **Biblioteca `sdk850-v1.0-release.aar`**: vem dentro de `L850TDemo.zip`, no caminho `L850TDemo/app/libs/`.
- **Javadoc** (`API文档/javadoc/`): é a fonte de verdade para nomes de classes, métodos e faixas de valores.
- **Guia de integração** (`850 SDK 接入文档.md`): em chinês. Existe uma tradução em PT-BR mantida pela equipe.
- **App demo** (`L850TDemo/`): as referências de comportamento mais importantes estão em `app/src/main/java/com/sunway/l850tdemo/viewmodel/RunViewModel.java` e `App.java`.

**Regra:** os nomes de API usados no código devem vir do Javadoc ou do demo. Não invente métodos. Não descompile o `.aar`.

### 3.1 API do SDK relevante (resumo do Javadoc)

Pacote base: `com.sunway.sdk850`.

**Conexão — `base.SerialPortManager` (singleton `getInstance()`)**

- Configuração: `getConfig()` retorna um `SerialPortConfig` com os setters `setBaudRate`, `setDataBits`, `setParity`, `setStopBits`, `setSendInterval`, `setTestTime`, `setLogEnable` e `setCmd`.
- Listeners: `registerCallback(SerialPortCallback)`, `unregisterCallback(...)` e `clearCallbacks()`.
- Conexão: `autoConnect()` (assíncrono, varre as portas), `connect(String portPath)` (retorna `boolean`), `reConnect()`, `disconnect()` e `release()`.
- Envio e estado: `send(byte[])`, que enfileira sem bloquear, além de `clearSendQueue()`, `getPendingCount()`, `getState()`, `isConnected()` e `getCurrentPortPath()`.

**Callbacks — `SerialPortCallback` (use `SerialPortCallback.Simple`)**

- `onConnected`, `onConnectFailed(portPath, reason)`, `onDisconnected`, `onError`, `onDataSent` e `onDataReceived(SerialPacket)`.
- Os callbacks são entregues **na thread principal**.
- `SerialPacket.getType()` retorna um `SerialPacketType`. Os tipos relevantes são `DEVICE_INFO`, `SEND_PARAMS` e `CONTROL`. Também existem `OTA_*` e `NONE`.

**Estado do dispositivo — `port.DeviceManager`**

- `getInstance()` e `init(Context, String spFileName)`.
- O guia usa também `getDeviceParams()`, `getControlParams()`, `getDeviceInfo()` e `setDeviceInfo()`, que não aparecem no resumo do Javadoc. Confirme essas assinaturas no demo.

**Construtor de comandos — `port.Cmd`**

- `quaryDeviceInfo()` (a grafia com "quary" é do próprio SDK), `sendParams(DeviceParams)` e `control(ControlParams)`.
- `ota0`, `ota1` e `ota2` são usados internamente pelo `FirmwareInstaller`.

**`bean.DeviceParams`** — parâmetros de calibração. Cada setter também salva o valor em SharedPreferences.

| Campo | Faixa | Unidade |
| --- | --- | --- |
| `minForce` | 5–20 | kg |
| `maxForce` | 50–150 | kg |
| `inactiveForce` (força em repouso) | 2–20 | kg |
| `maxLength` (comprimento máx. do cabo) | 10–255 | cm |
| `ratedSpeed` | 1–2000 | rpm |
| `ropeGuideDiameter` | 1–255 | cm (conforme o Javadoc) |
| `orginMinDistance` | 1–50 | cm |
| `orginMaxDistance` | 2–100 | cm |
| `velocityRange` (faixa do coef. isocinético) | 0–50 | — |
| `torqueVariationCycle` | 0–100 | — |
| `torqueCoefficient` | 1–20 | — |

**`bean.ControlParams`** — é reenviado a cada ciclo de polling.

- `run` (`RunState`), `mode` (`ForceMode`) e `force` (kg).
- Coeficientes: `centripetal` (concêntrico), `centrifugal` (excêntrico), `velocity` (isocinético, de 0 até `velocityRange`) e `elastic`.
- `safeMode`: 0 = normal, 51 = modo de falha/fadiga (力竭), 53 = modo de proteção.
- `clearMode` (`ClearMode`).
- `motorPosition1` e `motorPosition2`, que também são salvos em SharedPreferences.
- `motorSelfCheck` (boolean).
- `balancingForce`: força fixa de compensação de atrito no retorno, de 0 a 25 kg.
- `maxElectric`: curso ou força elástica máxima, padrão 50.
- Flags `needSetOrigin` e `needErrorRestor`.

**`bean.DeviceStatus`** — resposta de `CONTROL`.

- `run`, `mode`, `force` (kg) e `realForce` (a unidade não está documentada; o demo exibe em kg).
- `speed` (double, cm/s), `distance` (int, cm), `pullNum`, `errorCode` e `temperature` (double, °C).
- `liftMotorStatus`: 0x00 parado, 0x01 em movimento, 0x02 em autoteste.
- `liftMotorError1`, `liftMotorError2` (0x00 = sem erro) e `verityCodeError` (0x00 = OK, 0xAA = erro).

**Enums**

- `RunState`: `RUNNING`, `STOP`, `ORIGIN_RESET`, `ERROR_RESTORE`.
- `ForceMode`: `STANDARD`, `CENTRIPETAL`, `CENTRIFUGAL`, `VELOCITY`, `ELASTIC`.
- `ClearMode`: `NONE`, `FIRST`, `SECOND`, `ALL`.

**Firmware — `port.FirmwareInstaller(int type, File bin)`**

- `type`: 1 = placa adaptadora, 2 = controlador.
- Métodos: `setCallBack(...)`, que recebe `startSend`, `progress(int)`, `success()` e `error(String)`; além de `setTimeout(ms)`, `startInstall(Handler)` e `stop()`.
- Depois da instalação, é preciso desligar e religar a máquina.

### 3.2 Regras de comportamento do controlador (obrigatórias)

1. **Um comando, uma resposta.** O controlador só responde quando recebe um comando. Por isso, `Cmd.control(controlParams)` é enviado em loop. O intervalo padrão é de 200 ms e deve ser configurável.
2. **Em `STOP`, o motor fica em força base.** Segundo o Javadoc, nesse estado *qualquer comando além de iniciar é ignorado*. A UI deve deixar isso claro, e a Fase 4 deve verificar na prática quais campos têm efeito em `STOP`.
3. **Comandos de disparo único** são limpar dados, redefinir origem, reset de erro e autoteste dos motores.
   - O guia avisa que o comando de limpar dados não pode ser enviado continuamente.
   - O Javadoc diz que, quando o autoteste termina, o app deve voltar `motorSelfCheck` para `false` imediatamente, e que o movimento deve estar parado durante o autoteste.
   - **Antes de implementar esses comandos, leia `RunViewModel.java` e reproduza exatamente como o demo reseta cada flag.**
4. **Status dos motores de elevação não é garantido.** O controlador nem sempre informa "em ajuste" ou "em autoteste". Por isso, é obrigatório um timeout de segurança. O demo usa 130 s para o autoteste e `4 + Δnível × Contancts.MOTOR_LONG_TIME` segundos para ajuste de posição.
5. **Ajustar motores exige parar.** O demo chama `stop()` antes de alterar `motorPosition1` e `motorPosition2`.
6. **Divergência a confirmar.** O guia usa `setMaxElectricLength`, mas o Javadoc usa `setMaxElectric`. Use o que compilar e registre a escolha.

## 4. Estrutura do repositório

```
workbench850/
├── CLAUDE.md                      # instruções para o Claude Code (aponta para este documento)
├── docs/
│   ├── PROPOSTA_WORKBENCH_850.md  # este documento
│   └── decisions/                 # ADRs curtos, um por decisão nova
├── third_party/sdk850/            # material do fabricante (somente leitura)
│   ├── sdk850-v1.0-release.aar
│   ├── javadoc/
│   ├── guia-integracao-zh.md
│   └── L850TDemo/                 # código-fonte do demo, só para referência
├── tools/maven/
│   ├── sdk850-1.0.0.pom
│   └── publish_sdk850.sh
├── maven-repo/                    # repositório Maven local em arquivo (opção A)
├── packages/
│   └── sdk850_bridge/             # plugin Flutter (somente Android)
│       ├── android/               # Kotlin: ponte com o SDK
│       ├── lib/                   # API Dart, modelos, gateway falso
│       └── test/
└── apps/
    └── workbench/                 # app Flutter de bancada (BLoC)
```

O app referencia o plugin por caminho local:

```yaml
# apps/workbench/pubspec.yaml
dependencies:
  sdk850_bridge:
    path: ../../packages/sdk850_bridge
```

## 5. Publicação do `.aar` no Maven (D3)

### 5.1 Coordenadas

- `groupId`: `com.sunway` (ou o prefixo interno da empresa, por exemplo `br.com.<empresa>.thirdparty.sunway`)
- `artifactId`: `sdk850`
- `version`: `1.0.0`
- `packaging`: `aar`

O POM **deve declarar a dependência transitiva** da biblioteca serial nativa. O `.aar` não a inclui, e ela é usada pelo demo:

```xml
<!-- tools/maven/sdk850-1.0.0.pom -->
<project xmlns="http://maven.apache.org/POM/4.0.0">
  <modelVersion>4.0.0</modelVersion>
  <groupId>com.sunway</groupId>
  <artifactId>sdk850</artifactId>
  <version>1.0.0</version>
  <packaging>aar</packaging>
  <dependencies>
    <dependency>
      <groupId>com.licheedev</groupId>
      <artifactId>android-serialport</artifactId>
      <version>2.1.4</version>
      <scope>compile</scope>
    </dependency>
  </dependencies>
</project>
```

Confirme no `settings.gradle.kts` do demo em qual repositório o `com.licheedev:android-serialport` é resolvido (`mavenCentral()` ou outro) e replique essa configuração.

### 5.2 Opção A — repositório local em pasta (padrão para começar)

```bash
# tools/maven/publish_sdk850.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
mvn deploy:deploy-file \
  -Dfile="$ROOT/third_party/sdk850/sdk850-v1.0-release.aar" \
  -DpomFile="$ROOT/tools/maven/sdk850-1.0.0.pom" \
  -Dpackaging=aar \
  -Durl="file://$ROOT/maven-repo" \
  -DrepositoryId=local
```

Se a equipe preferir não depender do Maven instalado, o script pode ser trocado por um projeto Gradle mínimo com o plugin `maven-publish` que publique o mesmo artefato. O resultado final deve ser idêntico.

### 5.3 Opção B — repositório interno (Nexus, Artifactory etc.)

Use o mesmo comando, trocando `-Durl` pela URL do repositório de releases e `-DrepositoryId` pelo id configurado no `~/.m2/settings.xml` com as credenciais. **Não coloque credenciais no repositório.**

### 5.4 Consumo

A URL do repositório vem de uma propriedade, para alternar entre as opções A e B sem editar código:

```properties
# apps/workbench/android/gradle.properties  (ou ~/.gradle/gradle.properties)
sdk850MavenUrl=../../../maven-repo
```

Declare o repositório **no build Android do app**. Os plugins Flutter são subprojetos desse build, então a declaração vale para eles também. Use `allprojects { repositories { ... } }` ou o bloco equivalente do template atual. Declare também no bloco de repositórios do `android/build.gradle` do plugin, para que ele compile isolado.

```kotlin
maven { url = uri(providers.gradleProperty("sdk850MavenUrl").get()) }
```

No plugin:

```kotlin
dependencies {
    implementation("com.sunway:sdk850:1.0.0")
}
```

**Critério de pronto:** `flutter build apk --debug` em `apps/workbench` compila sem nenhum `.aar` em `libs/`.

### 5.5 R8 / ProGuard

O `.aar` foi gerado com R8 e não se sabe se traz regras de consumo. No build release do app, adicione `-keep class com.sunway.sdk850.** { *; }` e `-keep class android.serialport.** { *; }` até que se confirme que não são necessárias.

## 6. Plugin `sdk850_bridge`

### 6.1 Lado Kotlin (`packages/sdk850_bridge/android/`)

| Classe | Responsabilidade |
| --- | --- |
| `Sdk850BridgePlugin` | Implementa `FlutterPlugin`. Registra o `MethodChannel` e o `EventChannel` e delega ao `MachineController`. |
| `MachineController` | Singleton por processo. Inicializa o `DeviceManager` uma única vez, com o `applicationContext`. Configura `SerialPortConfig`, registra o `SerialPortCallback` e controla o loop de polling. Expõe os comandos. |
| `PollingLoop` | Usa um `Handler(Looper.getMainLooper())` com intervalo configurável e envia `Cmd.control(controlParams)` a cada ciclo. O envio do SDK é não bloqueante, então rodar na thread principal é seguro. |
| `OneShotCommands` | Encapsula limpar dados, origem, reset de erro e autoteste, com o reset dos flags idêntico ao demo (seção 3.2, item 3). |
| `LiftMotorGuard` | Timeout de segurança dos motores de elevação e detecção de conclusão (transição de 0x01/0x02 para 0x00, ou fim do timeout). |
| `Mappers` | Converte `DeviceStatus`, `DeviceInfo` e `DeviceParams` em `Map<String, Any?>`. Enums são enviados como `name()`. Cada status recebe `tsMonotonicMs` (`SystemClock.elapsedRealtime()`) e `tsEpochMs`. |
| `FirmwareController` | Usa o `FirmwareInstaller`. Pausa o polling durante a instalação e o retoma no final. |

Regras do lado Kotlin:

- `EventSink.success` é sempre chamado na thread principal. Os callbacks do SDK já chegam nela.
- Ao desconectar o `EventChannel` ou fechar o app: parar o polling, chamar `unregisterCallback` e depois `disconnect`. Chamar `release()` apenas no desligamento do processo.
- Toda falha deve virar `result.error(code, message, details)`. Códigos: `NOT_CONNECTED`, `INVALID_ARGS`, `OUT_OF_RANGE`, `BUSY`, `SDK_ERROR`.
- Validar as faixas de `DeviceParams` (seção 3.1) antes de enviar, retornando `OUT_OF_RANGE`.
- Ativar `setLogEnable(true)` somente em debug.

### 6.2 Contrato do canal

Nomes dos canais: `sdk850_bridge/methods` e `sdk850_bridge/events`.

**Métodos (Dart → Kotlin)**

| Método | Argumentos | Retorno | SDK |
| --- | --- | --- | --- |
| `initialize` | `{spFileName, baudRate?, sendIntervalMs?, testTimeMs?, logEnabled?}` | `void` | `DeviceManager.init` + `SerialPortConfig` |
| `autoConnect` | — | `void` (o resultado chega por evento) | `autoConnect()` |
| `connect` | `{portPath}` | `bool` | `connect(portPath)` |
| `disconnect` / `reconnect` | — | `void` | `disconnect()` / `reConnect()` |
| `getConnectionInfo` | — | `{state, portPath}` | `getState()`, `getCurrentPortPath()` |
| `startPolling` | `{intervalMs}` (padrão 200) | `void` | loop com `Cmd.control` |
| `stopPolling` | — | `void` | — |
| `queryDeviceInfo` | — | `void` (o resultado chega por evento) | `Cmd.quaryDeviceInfo()` |
| `getDeviceParams` | — | `Map` | `DeviceManager.getDeviceParams()` |
| `sendDeviceParams` | `Map` (campos da seção 3.1) | `void` (confirmação por evento `SEND_PARAMS`) | `Cmd.sendParams` |
| `getControlParams` | — | `Map` | `DeviceManager.getControlParams()` |
| `start` / `stop` | — | `void` | `setRun(RUNNING / STOP)` |
| `originReset` | — | `void` | conforme o demo (`needSetOrigin` + `ClearMode.ALL`) |
| `errorRestore` | — | `void` | conforme o demo (`needErrorRestor` + `ERROR_RESTORE`) |
| `clearData` | `{mode: NONE\|FIRST\|SECOND\|ALL}` | `void` | `setClearMode` (disparo único) |
| `setForce` | `{kg}` | `void` | `setForce` |
| `setMode` | `{mode}` | `void` | `setMode(ForceMode)` |
| `setCoefficient` | `{kind: centripetal\|centrifugal\|velocity\|elastic, value}` | `void` | setters correspondentes |
| `setElasticMax` | `{value}` | `void` | `setMaxElectric` (ver seção 3.2, item 6) |
| `setSafeMode` | `{value: 0\|51\|53}` | `void` | `setSafeMode` |
| `setBalancingForce` | `{kg: 0..25}` | `void` | `setBalancingForce` |
| `setMotorPosition` | `{p1, p2}` | `void` | `stop()` + `setMotorPosition1/2` + guarda de timeout |
| `startMotorSelfCheck` | `{timeoutSec?}` (padrão 130) | `void` | `setMotorSelfCheck(true)` + reset conforme o demo |
| `installFirmware` | `{type: 1\|2, filePath, timeoutMs?}` | `void` (progresso por evento) | `FirmwareInstaller` |
| `cancelFirmware` | — | `void` | `FirmwareInstaller.stop()` |

**Eventos (Kotlin → Dart)**

Todos os eventos são `Map`, com o tipo no campo `type`:

| `type` | Conteúdo |
| --- | --- |
| `connection` | `{state: connected\|failed\|disconnected\|error, portPath, reason?}` |
| `status` | todos os campos de `DeviceStatus` + `tsMonotonicMs` e `tsEpochMs` |
| `deviceInfo` | campos de `DeviceInfo` (conferir no demo quais existem) |
| `paramsAck` | `DeviceParams` retornado em `SEND_PARAMS` |
| `liftMotor` | `{phase: started\|completed\|timeout, remainingSec}` |
| `firmware` | `{phase: sending\|progress\|success\|error, progress?, message?}` |
| `log` | `{direction: tx\|rx, packetType, hex?, tsEpochMs}` (somente em debug) |

### 6.3 Lado Dart do plugin (`packages/sdk850_bridge/lib/`)

- **`sdk850_bridge.dart`** exporta a API pública.
- **`src/models/`** tem classes imutáveis com `Equatable` e `fromMap`/`toMap`: `DeviceStatus`, `DeviceInfo`, `DeviceParams`, `ControlSnapshot`, `ConnectionEvent`, `LiftMotorEvent`, `FirmwareEvent` e `LogEntry`, além dos enums `RunState`, `ForceMode`, `ClearMode` e `SafeMode`.
- **`src/machine_gateway.dart`** define a interface `abstract class MachineGateway`, com os métodos do contrato como `Future` e um `Stream<MachineEvent> get events`.
- **`src/method_channel_gateway.dart`** é a implementação real. Ela converte `PlatformException` em uma exceção tipada (`MachineException` com `code`).
- **`testing.dart`** exporta o `FakeMachineGateway`, que simula a máquina:
  - status a cada 200 ms, com repetições sintéticas (força e curso senoidais);
  - reação a `start`, `stop`, `setForce` e `setMode`;
  - motores de elevação com duração configurável;
  - erros injetáveis, para testar as telas de falha.

## 7. App `workbench` (BLoC)

### 7.1 Dependências

`flutter_bloc`, `bloc_concurrency`, `equatable`, `fl_chart`, `path_provider` e `file_picker` (para o `.bin` de firmware). Em desenvolvimento: `bloc_test` e `mocktail`.

### 7.2 Camadas

```
apps/workbench/lib/
├── main.dart                 # escolhe o gateway: --dart-define=GATEWAY=fake|device
├── app.dart                  # MultiRepositoryProvider + MultiBlocProvider + rotas
├── data/
│   └── machine_repository.dart   # única dona do MachineGateway; expõe streams por tipo de evento
├── features/
│   ├── connection/       # ConnectionBloc  + ConnectionPage
│   ├── device_params/    # DeviceParamsBloc + DeviceParamsPage (perfis salvos em JSON)
│   ├── control/          # ControlBloc     + ControlPage
│   ├── lift_motor/       # LiftMotorBloc   + LiftMotorPage
│   ├── telemetry/        # TelemetryBloc   + TelemetryPage (gráficos + gravação CSV)
│   ├── firmware/         # FirmwareBloc    + FirmwarePage
│   └── log/              # LogCubit        + LogPage
└── shared/
    ├── widgets/emergency_stop_button.dart
    └── safety/safety_limits.dart
```

### 7.3 Blocs

| Bloc | Eventos principais | Estado | Observações |
| --- | --- | --- | --- |
| `ConnectionBloc` | `ConnectRequested(auto\|path)`, `DisconnectRequested`, `PollingToggled(intervalMs)` | `disconnected / connecting / connected(portPath, deviceInfo) / failed(reason)` | Inicia o polling automaticamente ao conectar e envia `sendDeviceParams` com o perfil ativo, como faz o demo. |
| `DeviceParamsBloc` | `Loaded`, `FieldChanged`, `SendRequested`, `ProfileSaved/Loaded` | valores, validação por campo, `ackPending` | Valida as faixas da seção 3.1 antes de enviar. |
| `ControlBloc` | `StartPressed`, `StopPressed`, `ForceChanged`, `ModeChanged`, `CoefficientChanged`, `OneShotRequested(kind)`, `SafeModeChanged`, `BalancingForceChanged` | último `ControlSnapshot` + estado de execução refletido do status | Use o transformer `sequential()` para comandos e `restartable()` para o slider de força (com debounce de cerca de 150 ms). |
| `LiftMotorBloc` | `PositionRequested(p1,p2)`, `SelfCheckRequested` | `idle / adjusting(remaining) / selfChecking(remaining) / completed / timeout` | Pede confirmação na UI antes de disparar. |
| `TelemetryBloc` | `StatusReceived` (via `emit.forEach`), `RecordingToggled`, `Cleared` | último status, buffer circular (60 s), taxa medida (Hz), `recording` | Mede o intervalo real entre amostras usando `tsMonotonicMs`. |
| `FirmwareBloc` | `FileSelected`, `InstallRequested(type)`, `Cancelled` | `idle / sending / progress(n) / success / error` | Após `success`, mostra aviso de desligar e religar. |
| `LogCubit` | — | lista limitada (por exemplo, 2.000 entradas) | Permite exportar para `.txt`. |

### 7.4 Telas

1. **Conexão e diagnóstico**: conexão automática ou por caminho manual, estado da conexão, `DeviceInfo`, intervalo de polling e acesso ao log.
2. **Parâmetros do dispositivo**: formulário de `DeviceParams` com faixas, e botões de ler, enviar e salvar/carregar perfil.
3. **Painel de controle**: iniciar, parar, redefinir origem, reset de erro e limpar dados (com seletor `ClearMode`); seletor de modo; slider de carga; coeficientes do modo ativo; `safeMode` e `balancingForce`.
4. **Motores de elevação**: posições 1 e 2, autoteste, contagem regressiva, `liftMotorStatus` e erros 1 e 2.
5. **Telemetria**: valores numéricos grandes; gráficos de força real × tempo, velocidade × tempo e força × curso; indicador de taxa (Hz); gravação em CSV.
6. **Firmware**: seleção do `.bin`, tipo 1 ou 2, progresso e resultado.

### 7.5 Requisitos de segurança (não negociáveis)

- **O botão STOP fica fixo em todas as telas.** Ele chama `stop()` direto no repositório, sem passar por fila de Bloc.
- **Limite de carga no app.** O `SafetyLimits.maxForceKg` é configurável, com padrão abaixo do `maxForce` do dispositivo. O slider não ultrapassa esse limite.
- **Ações que movem motores ou alteram calibração pedem confirmação**: autoteste, ajuste de posição, envio de `DeviceParams` e instalação de firmware.
- **Perda de conexão ou exceção:** a UI mostra um estado de erro claro e desabilita os comandos.
- **Ao fechar o app ou enviá-lo para segundo plano:** enviar `stop()` e parar o polling. **Alterado em 2026-10-02 (ADR 0009, decisão do usuário):** sair da tela de controle não para mais a máquina nem o polling; no lugar, o indicador "EM EXECUÇÃO" aparece em todas as telas, desconectar e desligar o polling enviam STOP antes, e parâmetros e firmware só com a máquina parada.

### 7.6 Build e ambiente

- `minSdk` 24 e `abiFilters` com `arm64-v8a` e `armeabi-v7a`.
- **Flavors:**
  - `dev`: app comum, para usar no tablet de testes com permissões de serial ajustadas manualmente.
  - `system`: com `android:sharedUserId="android.uid.system"` e assinatura com a chave de plataforma da ROM de destino.
- **A chave de plataforma nunca vai para o repositório.** O caminho e as senhas vêm de variáveis de ambiente ou do `key.properties` fora do versionamento.
- **Preparação manual do tablet de testes (flavor `dev`, somente em POC):**

  ```bash
  adb root
  adb shell setenforce 0
  adb shell chmod 666 /dev/ttyUSB0
  ```

## 8. Fases e critérios de pronto

| Fase | Entregas | Critério de pronto |
| --- | --- | --- |
| 0. Fundação | Estrutura do repositório, `CLAUDE.md`, `third_party/sdk850/`, script e POM de publicação, `.aar` publicado na opção A | O plugin vazio compila consumindo `com.sunway:sdk850:1.0.0` do Maven. |
| 1. Contrato e fake | Modelos Dart, `MachineGateway`, `FakeMachineGateway`, `MachineRepository`, esqueleto dos Blocs e das telas | O app roda com `GATEWAY=fake`, e os testes `bloc_test` dos Blocs passam. |
| 2. Ponte mínima | `initialize`, `autoConnect`/`connect`, polling, eventos `connection`/`status`/`deviceInfo`, `LogCubit` | No hardware, a telemetria real aparece com o motor parado. |
| 3. Parâmetros | `getDeviceParams`, `sendDeviceParams` com validação, perfis | Os valores do painel original são reproduzidos, e `paramsAck` é recebido. |
| 4. Controle | `start`/`stop`, `setForce`, `setMode` e coeficientes, `safeMode`, `balancingForce` | Cada modo foi testado com carga baixa, e está documentado quais campos têm efeito em `STOP`. |
| 5. Disparo único e motores | `clearData`, `originReset`, `errorRestore`, `setMotorPosition`, `startMotorSelfCheck` com guardas | Os flags são resetados como no demo, os timeouts funcionam e não há comando repetido indevidamente. |
| 6. Telemetria | Gráficos, gravação CSV, medição de taxa, teste de intervalos (200, 100 e 50 ms) | Relatório com a taxa máxima estável e a tabela de `errorCode` observados. |
| 7. Firmware | `installFirmware` e `cancelFirmware` | Só depois de a fábrica confirmar o procedimento e fornecer um `.bin` de teste. |
| 8. Release interno | Flavor `system`, regras de R8, checklist de testes manuais | APK assinado instalado no equipamento de bancada. |

## 9. Testes

- **Dart:** testes de `fromMap`/`toMap` de todos os modelos; `bloc_test` para cada Bloc usando `FakeMachineGateway` ou `mocktail`; e um teste de widget do botão STOP em todas as rotas.
- **Kotlin:** testes unitários de `Mappers`, da validação de faixas e da lógica de `LiftMotorGuard` (sem SDK real, com fakes).
- **Checklist manual no hardware (`docs/checklist-hardware.md`):** uma linha por método do contrato, registrando a pré-condição, a ação, o resultado esperado, o resultado obtido, a data e o firmware usado.

## 10. Perguntas em aberto para o fabricante

1. Qual é o menor intervalo de polling suportado pelo controlador?
2. Qual é a tabela completa de `errorCode`, `liftMotorError1` e `liftMotorError2`?
3. Qual é a unidade de `realForce`?
4. É obrigatório que o app seja de sistema (`android.uid.system`) para acessar a serial? Qual chave de plataforma deve ser usada?
5. Existe a especificação do protocolo serial em bytes, para uma eventual implementação em Dart?
6. Qual é o comportamento esperado de cada comando de disparo único? Por quantos ciclos o flag deve permanecer ativo?
7. Qual nome de método é o correto: `setMaxElectric` ou `setMaxElectricLength`? A fórmula do modo elástico do guia está correta?
8. Existe algum termo de licença de uso e redistribuição do `.aar`?
9. Existe parâmetro, campo ou comando para controlar a velocidade do ajuste dos motores de elevação (banco/assento e braço)? A lentidão observada é um limite do hardware, do firmware ou de configuração? *(Pedido pela equipe de produto, 2026-10-02. O guia, o Javadoc e o demo não mostram nenhum controle de velocidade do ajuste; `ratedSpeed` e `velocity` são de outras funções.)*
10. Qual é o valor de `Contancts.MOTOR_LONG_TIME` (tempo por nível) de cada modelo de motor? Qual é a faixa válida e o valor padrão das posições (níveis) dos motores 1 e 2? Qual dos dois é o do assento e qual é o do braço?
11. O que significa a luz vermelha da máquina depois de uma execução e o que a libera? Observado: ela fica vermelha ao iniciar, continua vermelha depois do STOP (a máquina responde STOP e o cabo solta) e só volta a verde quando o polling é interrompido (ver `docs/checklist-hardware.md`, Fase 6).

## 11. Instruções para o Claude Code

- Trabalhe **uma fase por vez** (seção 8). Ao final de cada fase, rode `flutter analyze`, `flutter test` e o build Android, e resuma o que foi feito.
- **Contrato do canal (seção 6.2):** qualquer mudança deve ser proposta antes de implementada e registrada num ADR em `docs/decisions/`.
- **Nomes de API do SDK:** consulte `third_party/sdk850/javadoc/` e o demo. Se algo não estiver documentado, pare e pergunte. Não descompile o `.aar`.
- **Nunca remova nem enfraqueça** os requisitos de segurança da seção 7.5.
- **Nunca coloque no repositório** credenciais, chaves de assinatura ou o `release.jks` que veio no demo.
- Comentários e mensagens de commit em português. Identificadores de código em inglês.
