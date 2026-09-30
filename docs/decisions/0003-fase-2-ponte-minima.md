# ADR 0003 — Fase 2: ponte mínima com o SDK 850

Status: aceito (Fase 2, GOPER-5981)

## Contexto
A Fase 2 liga o app à máquina real: `initialize`, conexão, polling, eventos `connection`/`status`/`deviceInfo`/`log` e o `LogCubit` com exportação. Nenhuma assinatura do contrato do canal (seção 6.2) mudou.

## Decisões

### Estrutura do código Kotlin
- Tudo que toca o SDK fica atrás da interface `SdkPort`; a implementação real é `SdkSerialPort`, que só usa nomes do Javadoc e do demo. O `MachineController` (conexão, polling, eventos) é Kotlin puro e testado com um `FakePort`.
- `PollingLoop` roda num `Handler` da thread principal, como no plano (o demo usa uma `HandlerThread`; o `send` do SDK só enfileira). `Scheduler` abstrai o `Handler` para o laço ser testável.
- O contexto da aplicação vem de `AppContext`, preenchido pelo plugin ao anexar ao engine. O `Mockito` não consegue mockar `android.content.Context` nos testes de unidade, e o controlador não precisa dele.
- `Mappers`, `Args` e `CommandNames` são objetos puros. `BridgeException` leva um dos códigos do contrato e vira `result.error`.

### Segurança
- **O polling sempre começa em `STOP`**: `startPolling` chama `markStop()` antes do primeiro envio, porque o valor padrão de `ControlParams.run` não é documentado. Reiniciar o polling (por exemplo, ao trocar o intervalo) também volta para `STOP`.
- **`stop()` foi implementado já nesta fase** (não estava no escopo): coloca `run = STOP` e envia o `Cmd.control` na hora, sem esperar o ciclo. É o requisito deixado no ADR 0002 para o `haltForSafety`.
- Um ciclo de polling é pulado quando a fila de envio do SDK tem 3 ou mais comandos pendentes (`MAX_PENDING_COMMANDS`), para nunca empilhar ordens velhas.
- `onError`, `onConnectFailed`, `onDisconnected` e uma falha no envio do polling param o polling e emitem evento `connection`. `onError` vira `state: error`.
- Ao o Dart parar de escutar o `EventChannel` ou o plugin ser desanexado: para o polling, limpa a fila, `unregisterCallback` e `disconnect`, nessa ordem. `release()` não é chamado.

### Contrato
- Métodos implementados: `initialize`, `autoConnect`, `connect`, `disconnect`, `reconnect`, `getConnectionInfo`, `startPolling`, `stopPolling`, `queryDeviceInfo` e `stop`. Os demais respondem `notImplemented` até a fase deles.
- Padrões de `initialize` iguais aos do demo: 115200 bps, 50 ms de intervalo de envio, 500 ms de handshake. `DeviceManager.init` roda uma vez por processo.
- Faixa aceita para `intervalMs`: 10 a 5000 ms (`OUT_OF_RANGE` fora dela). O limite inferior só evita um laço sem pausa; o menor intervalo que o controlador suporta continua sendo a pergunta 1 do fabricante.
- O evento `log` (somente com `logEnabled`) traz o nome do comando TX traduzido por `CommandNames` (o SDK devolve em chinês, por exemplo `控制指令` = `CONTROL`); nomes desconhecidos passam como vieram.

### R8 em build release (antecipado da Fase 8)
- Em build **release**, o R8 ofusca `android.serialport.SerialPort` e o código nativo `libserial_port.so` não acha o campo `mFd`: tocar em **Desconectar** derruba o app com `SIGABRT` (`NoSuchFieldError: no "Ljava/io/FileDescriptor;" field "mFd"`). Conectar e ler funcionam, porque só o `close()` usa esse campo. Observado no tablet de bancada em 2026-09-30.
- Correção: `packages/sdk850_bridge/android/consumer-rules.pro` com `-keep class android.serialport.** { *; }` e `-keep class com.sunway.sdk850.** { *; }` (as regras da seção 5.5 do plano), declarado como `consumerProguardFiles` no plugin, então vale para qualquer app que o use. Verificado em `seeds.txt` do R8 (`mFd` preservado). Build **debug** não é afetado.
- Fica pendente da Fase 8 confirmar se todas as regras são necessárias.

### Diagnóstico de polling (achado da bancada)
- A tela de Telemetria avisa "Sem resposta do controlador há N s" quando o polling está ligado e nenhum status chega por 3 s (`TelemetryBloc.silentSeconds`, contado por timer, não por relógio de parede). Sem isso, um polling rápido demais só parecia "congelado".
- O log registra uma linha `STATUS ...` com todos os campos **quando a leitura muda** (ignorando temperatura e relógios), para mostrar movimento do cabo, erros e mudança de estado sem uma linha por ciclo.
- O seletor de intervalo oferece 200, 150, 120, 100, 80, 70, 60 e 50 ms; só pode ser trocado com o polling desligado.

### App
- `LogExporter` grava o log em `getExternalStorageDirectory()` (`Android/data/<pacote>/files`), de onde sai com `adb pull` sem permissão de armazenamento. O botão **Copiar** continua disponível.
- O `DeviceParams` **não** é enviado automaticamente ao conectar (o demo faz isso no `onConnected`). O controlador respondeu `CONTROL` e `DEVICE_INFO` sem ele. Enviar calibração muda a máquina e exige confirmação (seção 7.5), então a decisão fica para a Fase 3.

## Observado na bancada (2026-09-30)
Observações, não confirmadas pelo fabricante; detalhes em `docs/checklist-hardware.md`.
- App comum (sem `sharedUserId` de sistema) conectou em `/dev/ttyS9` no tablet de bancada (Android 11, build `user`, SELinux permissivo, `ttyS2/8/9` com permissão 666). Pergunta 4 respondida para esta ROM.
- Taxa de polling: 200 ms responde 98% (~4 Hz); 100 ms ~82% (~8 Hz, a maior taxa de dados); 80 e 60 ms respondem ~44 a 50%; ~54 ms (pedido de 50 ms) quase não obtém resposta (0 em 22 s numa sessão). O controlador não trava: volta a responder assim que o ritmo diminui. Padrão mantido em 200 ms; não usar menos que 100 ms. Tabela em `docs/checklist-hardware.md`.
- Em `STOP`, com o cabo em movimento, `curso` acompanha o cabo (1 a 40 cm), `velocidade` só vale 0,0 ou 43,0 e `repetições`, forças e erros ficam em 0.
- Controlador: software `9170080`, versão `41`, código de produção `L850T0`.

## Consequências
- Testes: 70 de unidade em Kotlin (`./gradlew :sdk850_bridge:testDebugUnitTest`, a partir de `apps/workbench/android`), 65 no plugin Dart e 78 no app.
- A ponte só foi exercitada com o motor parado. Comandos que movem a máquina (`start`, força, modo) continuam para a Fase 4.
