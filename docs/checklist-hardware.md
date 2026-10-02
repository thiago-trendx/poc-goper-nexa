# Checklist de testes manuais no hardware

Uma linha por método do contrato (seção 6.2 do plano). Resultados são **observados na bancada**, não confirmados pelo fabricante.

- Tablet: RK3568 (`rk3568_r`), Android 11, build `user`. Serial da máquina: `/dev/ttyS9`.
- Firmware do controlador (`DeviceInfo`): software `9170080`, versão `41`, código de produção `L850T0`.
- Build usado: `flutter build apk --debug --dart-define=GATEWAY=device`.

Legenda: ✅ passou · ⚠️ passou com ressalva · ⏳ ainda não testado

| Método | Pré-condição | Ação | Esperado | Obtido | Data | Status |
| --- | --- | --- | --- | --- | --- | --- |
| `initialize` | App aberto, máquina ligada | Tocar em "Conexão automática" (chamado antes de conectar) | Sem erro | Sem erro | 2026-09-30 | ✅ |
| `autoConnect` | Inicializado, serial ligada | Tocar em "Conexão automática" | Evento `connection: connected` | Conectou em `/dev/ttyS9` (varreu `ttyS2`, `ttyS8`, `ttyS9`) | 2026-09-30 | ✅ |
| `connect` | Inicializado | Informar o caminho da porta e tocar em "Conectar" | Evento `connection` | — | — | ⏳ |
| `disconnect` | Conectado | Tocar em "Desconectar" | Evento `disconnected`, polling parado | Release sem regras R8: o app fechou (`SIGABRT`, campo `mFd` ofuscado). Com `consumer-rules.pro`: desconectou e reconectou em 2 s, sem queda | 2026-09-30 | ✅ (após correção) |
| `reconnect` | Desconectado | — (sem botão na tela ainda) | Evento `connection` | — | — | ⏳ |
| `getConnectionInfo` | Conectado | — (sem botão na tela ainda) | `{state: CONNECTED, portPath}` | — | — | ⏳ |
| `startPolling` | Conectado | Automático ao conectar (200 ms); demais intervalos pelo seletor | Eventos `status` a cada ciclo, motor parado | Ver tabela de taxas: 200 ms responde 98% (4 Hz); 100 ms ~82% (~8 Hz); abaixo de 100 ms piora; ~54 ms quase sem resposta | 2026-09-30 | ⚠️ |
| `stopPolling` | Polling ativo | Alternar o switch de polling | `status` para de chegar | Telemetria congela e a tela avisa "Polling parado" | 2026-09-30 | ✅ |
| `queryDeviceInfo` | Conectado | Automático ao conectar | Evento `deviceInfo` | `DEVICE_INFO` recebido (resposta à consulta `01 61 00 00 00 00 00 00 00 06`) | 2026-09-30 | ✅ |
| `stop` | Conectado | Botão STOP | `run = STOP` enviado na hora | Sem erro; tela mostrou "STOP enviado". Estado seguiu `stop` (a máquina já estava parada) | 2026-09-30 | ✅ |
| `getDeviceParams` | SDK inicializado | Aba Parâmetros, "Ler valores salvos" | Valores guardados no app | `5 / 120 / 5 / 100 / 150 / 25 / 2 / 50 / 10 / 10 / 10`, iguais aos do painel original (confirmado pelo usuário). É o cache do SDK, não uma leitura do controlador | 2026-09-30 | ✅ |
| `sendDeviceParams` | Conectado | Alterar a força mínima e "Enviar ao controlador" (com confirmação) | `paramsAck` com os mesmos valores | Enviou 15 e depois restaurou 5; nos dois casos o controlador confirmou sem divergência. Resposta em 92 ms | 2026-09-30 | ✅ |
| `paramsAck` (evento) | Após o envio | — | `DeviceParams` devolvido pelo controlador | Chegou e a tela mostrou a confirmação; `RX SEND_PARAMS` no log | 2026-09-30 | ✅ |

## Protocolo observado: envio de parâmetros (`SEND_PARAMS`)
Bytes lidos do `logcat` (`SerialPortSender` e `SerialPortManager`) com a força mínima em 5. Observado, não confirmado pelo fabricante.

| Sentido | Bytes |
| --- | --- |
| Envio (`参数下发指令`) | `01 65 05 78 05 64 FF 96 19 02 32 0A 0A 0A 00 00 00 00 00 00 00 00 00 B3` |
| Resposta (`SEND_PARAMS`) | `01 65 05 78 05 64 00 96 19 02 32 0A 0A 0A 00 00 00 00 00 00 00 00 00 25` |

Mapeamento inferido (valores do painel original): `01 65` cabeçalho e comando; depois `minForce` (05), `maxForce` (78 = 120), `inactiveForce` (05), `maxLength` (64 = 100), 2 bytes de `ratedSpeed` (`96` = 150 no byte baixo), `ropeGuideDiameter` (19 = 25), `orginMinDistance` (02), `orginMaxDistance` (32 = 50), `velocityRange`, `torqueVariationCycle` e `torqueCoefficient` (0A = 10 cada), 9 bytes zerados e 1 byte final de verificação.

- **Byte alto de `ratedSpeed`:** o SDK envia `FF` e o controlador devolve `00`, então o valor guardado é 150. É compatível com extensão de sinal de um byte (150 como `byte` vira -106 = `FF96`). **Hipótese não confirmada:** para velocidades nominais acima de 127 o SDK pode estar montando o byte alto errado; vale perguntar ao fabricante junto com a especificação do protocolo (pergunta 5).
- **Byte de verificação:** não é soma simples; não foi decifrado e não é necessário (o SDK monta o comando).

## Taxa de polling x resposta do controlador
Medido pelo log TX/RX do app em duas sessões (build debug, 2026-09-30). "Resposta" = respostas `CONTROL` divididas pelos comandos `CONTROL` enviados. A segunda sessão foi feita **com o cabo da máquina em movimento**, em `STOP`.

| Intervalo pedido | TX real | Respostas/s | Resposta | Latência média | Observação |
| --- | --- | --- | --- | --- | --- |
| 200 ms | ~207 ms | 4,0 | 98% | 97 ms | Estável; é o padrão do plano e do demo |
| 100 ms | ~104 ms | ~8,2 (regime) | ~82% | 69 ms | **Maior taxa de dados**; pausas ocasionais (a maior, 1,6 s) |
| 80 ms | ~79 ms | ~5,4 | ~44% | — | Pior que 100 ms |
| 60 ms | ~59 ms | ~6,2 | ~50% | 76 ms | Pior que 100 ms |
| 50 ms | ~54 ms | ~2,0 | ~12% | 54 ms | Quase sem resposta (na 1ª sessão, 0 respostas por 22 s) |

- O SDK mantém no mínimo 50 ms entre envios (`setSendInterval(50)`); 50 ms pedido vira ~54 a 56 ms real.
- A taxa de dados entregues **não cresce ao acelerar o polling**: passa de ~4 Hz (200 ms) para ~8 Hz (100 ms) e depois cai. O controlador precisa de um intervalo entre comandos; abaixo de ~100 ms ele responde cada vez menos e volta ao normal assim que o ritmo diminui (sem travar).
- Recomendação provisória: manter **200 ms** como padrão (98% de resposta) e usar **100 ms** quando precisar de mais resolução. Não usar menos que 100 ms.

## Valores em repouso observados (motor parado, STOP)
Força real 0 · velocidade 0,0 cm/s · curso 1 cm · temperatura 27,0 °C · repetições 0 · código de erro 0.

## O que o controlador informa em `STOP` (cabo movendo, 80 s de log)
| Campo | Observado |
| --- | --- |
| `curso` | **Acompanha o cabo**: de 1 a 40 cm |
| `velocidade` | Só dois valores, **0,0 e 43,0 cm/s**, mesmo com movimento contínuo (nas saídas rápidas o curso variava ~48 cm/s e a velocidade vinha 43 ou 0). Não confiável em `STOP` |
| `repetições` | Sempre 0 |
| `força real` / `força` | Sempre 0 |
| `errorCode`, motores 1/2, `verityCodeError` | Sempre 0 |

Ainda não se sabe se `velocidade` e `repetições` passam a variar em `RUNNING` (Fase 4).

## Pendências da Fase 2 para fechar o checklist
- Testar `connect` manual e a reconexão com a máquina reiniciada (opcional).

## Fase 4 — controle (2026-10-02)
Tudo abaixo é **observado, não confirmado pelo fabricante**. Execuções feitas pelo usuário na bancada, com parada física ao alcance.

### Conexão
- `autoConnect` falhou uma vez: `ttyS9` abriu com `fd = -1` ("native openSerialPort returns null") e `ttyS2`/`ttyS8` abriram mas não responderam ao handshake. A mensagem em chinês `未找到可用串口` só diz "nenhuma porta disponível". Depois de `am force-stop com.oma.doublecontrol` a conexão funcionou; hipótese: o app do fornecedor segura a `ttyS9`. Não se sabe qual processo segurava.

### Protocolo do comando de controle (`01 64 ...`)
- Byte 3: `FB` = STOP, `FA` = execução.
- Força em unidades de 0,1 kg em dois campos (bytes 4-5 e 6-7): 5 kg = `0x32`, 10 = `0x64`, 22 = `0xDC`, 30 = `0x12C`. O primeiro varia com o modo (concêntrico/excêntrico); o segundo mantém a força definida.
- Byte 15 = força de compensação (10 → 5 → 4 → 3 → 2 → 0 → 1 → 6 → 5 aceitos em STOP).
- No elástico apareceu `04` no byte 2 (nos outros modos fica `00`); significado não confirmado.
- A máquina confirma cada `CONTROL` em ~90 ms.

### Fórmulas do guia
- Concêntrico `força×(1−coef×0,1)+0,5`: com 22 kg e coef. 5, 4, 3, 2 enviou 11, 13, 15 e 18 kg.
- Excêntrico `força×(1+coef×0,1)+0,5`: com 5 kg e coef. 3 e 5 enviou 7 e 8 kg.
- Resultado truncado em kg inteiro. Trocar coeficiente com a máquina em execução foi aceito.

### Telemetria em execução
- `força real` ficou em 0 com 5 kg (Padrão e Elástico) e chegou a 22 (Padrão, 22 kg) e 16 (Concêntrico, 22 kg); pode haver limiar.
- `repetições` passou a contar (1 a 3). `velocidade` ficou em 0,0 em todos os testes. Em STOP, `força` reportada é 0.
- Proteção 51 foi aceita; elástico (coef. 5, curso 50 cm) rodou sem erro.

### Pendências
- Efeito de cada campo em STOP; comportamento ao parar o polling com a máquina em execução; escala do coeficiente elástico; por que `velocidade` fica em 0.

## Fase 5 — roteiro de bancada (NÃO executado ainda)
Registrar o que for observado como "observado, não confirmado pelo fabricante". Parada de emergência física ao alcance, duas pessoas, área livre, sem carga no cabo. Um teste por vez; salvar o log depois de cada um.

1. **Limpar dados** (só contagens): fazer algumas repetições em STOP, limpar `Todos`. Esperado: `rep` volta a 0. No log, o TX do comando de controle aparece **uma vez** com o `clearMode` diferente de `NONE` (bytes) e os seguintes já voltam ao normal. *Isso responde se o comando se repete.*
2. **Reset de erro**: só se houver erro; senão apenas observar o TX (uma vez, `run = ERROR_RESTORE`) e que o estado volta a STOP.
3. **Redefinir origem** (altera o ponto zero do curso): com o cabo na posição de repouso; observar `curso`, `rep` e o byte do comando (uma vez).
4. **Ajuste de posição dos motores**: ler as posições atuais em Controle; ajustar **só 1 passo** em um motor, com o ajuste confirmado. Medir o tempo até `liftMotorStatus` voltar a `0x00` e se o status passa por `0x01`. Anotar o tempo (resposta à pergunta de `MOTOR_LONG_TIME`). Depois voltar à posição original.
5. **Autoteste** (130 s, move os motores): só com tudo livre. Medir quando termina, se o status passa por `0x02` e se o flag `false` é enviado na hora (log).
6. **Abortos**: durante o ajuste/autoteste, desligar o polling e conferir que o flag volta a `false` e a tela mostra `timeout`.
