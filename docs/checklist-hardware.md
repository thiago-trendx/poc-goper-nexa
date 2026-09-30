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
- Testar `connect` manual e a reconexão com a máquina reiniciada (opcional, não bloqueia a Fase 3).
