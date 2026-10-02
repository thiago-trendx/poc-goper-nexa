# ADR 0009 — Sair da tela de Controle não para mais a máquina

Status: aceito (decisão do usuário, 2026-10-02, confirmada com a equipe de engenharia)
Substitui em parte: ADR 0002 e ADR 0005; altera o item "ao sair da tela de controle" da seção 7.5 do plano.

## Contexto
Na Fase 4 o usuário escolheu parar a máquina e o polling ao sair da tela Controle. Na bancada (teste A2 da Fase 6) isso mostrou que não dá para acompanhar a Telemetria com a máquina em execução: ao abrir a tela Telemetria, o app mandava STOP e parava o polling. A equipe de engenharia confirmou que a regra inviabilizaria os testes futuros.

## Decisão
- **Sair da tela Controle não envia STOP nem para o polling.** O Controle deixa de chamar `haltForSafety` ao ser descartado.
- **Continuam valendo:** o botão STOP fixo em todas as telas (direto no repositório); `stop()` + parada do polling ao fechar o app ou enviá-lo para segundo plano; o STOP nativo imediato; o limite de carga; as confirmações; e os bloqueios da Fase 5.

## Compensações (para não deixar a segurança mais frouxa do que a mudança exige)
O que a regra antiga protegia indiretamente passou a ser tratado de forma explícita:
- **Indicador "EM EXECUÇÃO"** na barra de qualquer tela enquanto a máquina estiver em execução, com "sem resposta há N s" se os status pararem de chegar. A fonte é o estado **reportado pela máquina**; o estado local só vale antes do primeiro status, porque o STOP fixo não passa pelo `ControlBloc` e deixaria o estado local desatualizado.
- **Desconectar e desligar o polling pela tela Conexão enviam STOP antes** (`haltForSafety`: STOP, espera de 2 ciclos, depois desliga). Antes isso só era alcançável com a máquina já parada.
- **Enviar parâmetros do dispositivo e instalar firmware só com a máquina parada:** botões desabilitados com explicação; no nativo, `sendDeviceParams` responde `BUSY` se `run == RUNNING`; o gateway falso espelha isso (também no firmware, que o nativo ainda não implementa).
- **Teste de taxa** passou a usar a mesma fonte de "máquina em execução" e continua só com a máquina parada.

## Consequências
- Dá para acompanhar a Telemetria, o Log e as demais telas com a máquina em movimento.
- Risco novo, aceito pelo usuário: o usuário pode sair da tela Controle com a máquina em execução e esquecê-la assim. O indicador e o STOP fixo existem para isso.
- **Não validado na bancada:** o que a máquina faz se o app deixar de enviar comandos com ela em execução (pergunta já aberta na Fase 4). Por isso desconectar e desligar o polling mandam STOP antes.
- Testes: 164 no app, 84 no plugin Dart e os de Kotlin passando.
