# ADR 0005 — Fase 4: controle (start/stop, força, modos, coeficientes)

Status: aceito (Fase 4, GOPER-5983)

## Contexto
A Fase 4 move a máquina: `start`/`stop`, força, modo, coeficientes, curso elástico, proteção (`safeMode`) e força de compensação (`balancingForce`). As faixas e regras vêm do demo e do Javadoc do SDK.

## Decisões

### Limite de carga também no Kotlin (decisão do usuário)
- `initialize` ganhou o argumento **opcional** `maxForceKg` (adição ao contrato da seção 6.2, compatível com versões anteriores). O app envia o limite (30 kg por padrão) e o `MachineController` recusa com `OUT_OF_RANGE` qualquer força acima dele, mesmo que o Dart falhe. O `FakeMachineGateway` espelha a regra.
- Faixa válida da força: de `minForce` (calibração atual) até o menor entre `maxForce` e o limite do app. Se o limite do app ficar abaixo de `minForce`, nenhuma carga é válida e **Iniciar** explica o motivo.

### Início seguro
- O polling sempre começa em `STOP`. `start` só é aceito com o polling ligado e com a força dentro da faixa; ao iniciar, a força é reenviada antes do `start`.
- Se o polling parar, o estado local volta a `STOP`.
- Ao sair da tela Controle ou ir para segundo plano: `stop`, espera de 2 ciclos e parada do polling (`haltForSafety`) (decisão do usuário). A telemetria deixa de chegar depois disso.
- O botão STOP vai direto ao repositório e nunca espera a fila de comandos.

### Faixas (do demo/Javadoc)
- Concêntrico e excêntrico: 0 a 6. Isocinético e elástico: 0 a 10 (isocinético também limitado por `velocityRange`). Curso elástico: 1 a `maxLength`. Compensação: 0 a 25. `safeMode`: 0, 51 ou 53.
- A fila de comandos usa tipos-base selados com um handler por tipo, porque `sequential()` só serializa dentro do mesmo tipo de evento.

## Observado na bancada (2026-10-02, "observado, não confirmado pelo fabricante")
Detalhes em `docs/checklist-hardware.md`.
- Execução em Padrão com 5, 10, 22 e 30 kg, Concêntrico (22 kg), Excêntrico (5 kg), Elástico (5 kg, coeficiente 5, curso 50 cm); sem `errorCode` diferente de 0.
- Fórmulas do guia confirmadas pelos bytes enviados para Concêntrico e Excêntrico (força truncada em kg inteiro).
- Proteção 51 aceita pela máquina. A sensação de resistência mudou com a compensação e o Excêntrico deu mais resistência na descida (relato do usuário).

## Consequências
- Não foi testado: o que acontece com a máquina em execução quando o polling para; o efeito de cada campo em `STOP`; a escala do coeficiente elástico.
- Testes ao fim da fase: 131 no app e 79 no plugin Dart; testes Kotlin passam.
