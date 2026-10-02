# ADR 0002 — Fase 1: contrato Dart, fake e regras de segurança do app

Status: aceito (Fase 1, GOPER-5980)

## Contexto
A Fase 1 entrega os modelos Dart, o `MachineGateway`, o `FakeMachineGateway`, o `MachineRepository`, os Blocs e as telas, sem hardware. Algumas decisões não estavam no plano ou o plano deixava em aberto. Nenhuma altera o contrato do canal (seção 6.2): são formatos de fio e detalhes que o plano não fixava.

## Decisões

### Formato dos eventos no canal
- Enums trafegam como o `name()` do enum Kotlin (`RUNNING`, `ORIGIN_RESET`, `ALL`…). `safeMode` trafega como inteiro (0, 51, 53). `connection.state`, `liftMotor.phase`, `firmware.phase`, `log.direction` e `CoefficientKind` usam o nome em minúsculas definido na seção 6.2.
- `paramsAck` leva os campos de `DeviceParams` no mesmo nível de `type` (sem mapa aninhado). Os nomes dos campos são os do SDK, inclusive `orginMinDistance` e `orginMaxDistance`.
- `getConnectionInfo` devolve `state` com o `SerialPortManager.State` do Javadoc (`IDLE`, `SCANNING`, `CONNECTED`, `CLOSED`) e `portPath`.
- `DeviceInfo` tem `softwareNum` (texto), `versionCode` (inteiro) e `produceCode` (texto), conforme o Javadoc.
- Um evento com `type`, enum ou campo inválido lança `FormatException` no Dart e chega ao app como erro do stream (`MachineRepository.eventErrors`, registrado no log), nunca como valor padrão.

### Segurança (seção 7.5, sem enfraquecer)
- O botão STOP fica no rodapé do `HomeShell`, chama `MachineRepository.stop()` direto e nunca é desabilitado; se o envio falhar, mostra o erro.
- `SafetyLimits.maxForceKg` tem padrão **30 kg**, abaixo do menor `maxForce` possível do dispositivo (50 kg), para os primeiros testes serem com carga baixa. Configurável por `--dart-define=MAX_FORCE_KG`. `ControlBloc` corta valores acima do limite e avisa; o slider não passa dele.
- Ao sair da tela de controle, ao enviar o app para segundo plano (`paused`) ou ao fechá-lo (`detached`), o app chama `MachineRepository.haltForSafety()`: envia `stop()`, espera **dois ciclos de polling** e então para o polling. A espera existe porque o `stop()` só altera o `ControlParams`; ele segue para o controlador no próximo ciclo. **Requisito para a Fase 2/4:** o `stop()` nativo deve enviar um `Cmd.control` imediatamente, sem esperar o próximo ciclo.
- Consequência: sair da tela de controle para o polling; a telemetria só volta quando o polling for religado na tela de conexão.
- **Substituído em parte pelo ADR 0009:** sair da tela de controle deixou de parar a máquina e o polling. Segundo plano e fechar o app continuam como acima.

### Blocs
- Em cada Bloc, comandos de tipos diferentes entram numa **fila única** (`sequential`), por um handler sobre um tipo base selado (`ControlCommand`, `ConnectionCommand`, `DeviceParamsEvent`). Motivo: `sequential()` só serializa dentro de um mesmo tipo de evento, e comandos de tipos diferentes chegariam à máquina fora de ordem.
- Exceções deliberadas: `StopPressed` (`concurrent`, nunca espera a fila) e `ForceChanged` (`restartable` com debounce de 150 ms, só o último valor é enviado).
- `LiftMotorBloc` descarta pedidos enquanto `state.busy`: o handler termina quando o comando é aceito, mas o movimento continua até o evento `completed`/`timeout`.
- Nomes que diferem do plano: `TelemetryStarted` no lugar de `StatusReceived` (o Bloc assina os status com `emit.forEach`); `ElasticMaxChanged` foi adicionado para cobrir `setElasticMax`; `ConnectionBloc` usa `ConnectionBlocEvent`/`ConnectionBlocState` para não colidir com `ConnectionEvent` do plugin e `ConnectionState` do Flutter.

### Escopo adiado
- Envio do perfil ativo de `DeviceParams` ao conectar e `ProfileSaved/Loaded`: Fase 3.
- Gravação em CSV e gráficos: Fase 6 (`fl_chart` e `path_provider` entram então). `file_picker` entra na Fase 7; até lá o caminho do `.bin` é digitado.
- Exportação do log em arquivo `.txt`: por enquanto o log é copiado para a área de transferência; arquivo na Fase 2.
- O lado Kotlin só registra os canais `sdk850_bridge/methods` e `sdk850_bridge/events` e responde `notImplemented`; o Dart converte isso em `MachineException(SDK_ERROR)`.

### Gateway padrão
`main.dart` usa `--dart-define=GATEWAY=fake|device` com padrão **`fake`**, para nunca comandar a máquina real sem pedir explicitamente.

## Consequências
- O app roda e é testável sem hardware; o `FakeMachineGateway` simula status, repetições, motores de elevação e erros injetáveis, mas **não reproduz o comportamento real do controlador** (por exemplo, quais campos valem em `STOP`, que a Fase 4 verifica no hardware).
- Testes: modelos, gateway de canal e fake no plugin; todos os Blocs, o repositório e as telas (STOP em todas as rotas) no app.
