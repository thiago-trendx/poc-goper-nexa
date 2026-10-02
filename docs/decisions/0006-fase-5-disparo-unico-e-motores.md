# ADR 0006 — Fase 5: disparo único e motores de elevação

Status: aceito em software (Fase 5, GOPER-5984); **validação na bancada pendente**

## Contexto
A Fase 5 liga os comandos que o demo trata como disparo único (`originReset`, `errorRestore`, `clearData`) e os dois que mexem nos motores de elevação (`setMotorPosition`, `startMotorSelfCheck`). Foram lidos `RunViewModel.java` e `FactorySetViewModel.java` do demo e o Javadoc de `ControlParams`.

## Lacunas da documentação (decisões do usuário)
1. **O demo nunca desliga `needSetOrigin`, `needErrorRestor` nem `clearMode`.** Um comentário do demo diz que o comando de limpar dados "não pode ser enviado continuamente" e que o demo "evita isso por clonagem", mas o Javadoc não diz se o SDK limpa os flags depois de enviar. **Decisão: o app desliga os flags.** O comando é montado com `Cmd.control` com os flags ligados, enviado uma única vez, e os flags são desligados logo depois (também se o envio falhar). Assim o polling nunca repete o comando, qualquer que seja o comportamento do SDK. Além disso, `startPolling` sempre começa com os três flags e o `motorSelfCheck` desligados.
2. **`Contancts.MOTOR_LONG_TIME` não aparece em nenhum documento** (só o uso: `4 + Δnível × MOTOR_LONG_TIME` s). **Decisão: teto provisório de 130 s** (`LIFT_ADJUST_TIMEOUT_SEC`, o mesmo do autoteste) para o ajuste de posição, a medir na bancada e a confirmar com o fabricante.
3. **A faixa válida das posições dos motores e o valor padrão não estão documentados** (`DefaultUserConfig` não faz parte do material). Só se valida `>= 0`; na bancada, usar passos de 1 a partir da posição atual (`getControlParams`).

## Decisões de segurança (plano §7.5, nada foi enfraquecido)
- **Nunca reinicia sozinho.** O demo chama `start()` quando o ajuste dos motores termina. Aqui o estado fica em `STOP` ao fim de qualquer operação e o usuário precisa tocar em Iniciar.
- **Origem e reset de erro só com a máquina parada** (`BUSY` se `run == RUNNING`). Limpar dados vale em execução (o demo também permite).
- **Durante uma operação dos motores** ficam bloqueados (`BUSY`) iniciar, outro ajuste/autoteste e os disparos únicos; STOP continua sempre disponível.
- **Ajuste e autoteste exigem o polling ligado** (as posições e o flag de autoteste só chegam ao controlador pelo polling), e começam com STOP enviado na hora (Javadoc: movimento parado durante o autoteste).
- **`LiftMotorGuard`** encerra a operação uma única vez, por conclusão (status do motor `0x01`/`0x02` e depois `0x00`, como o demo) ou por timeout (autoteste: o pedido, padrão 130 s, máximo 600; ajuste: 130 s). Ao terminar, por qualquer motivo: desliga `motorSelfCheck`, volta a `STOP`, envia a ordem na hora (Javadoc: responder `false` imediatamente) e só depois publica o evento `liftMotor`.
- **Abortos contam como `timeout`:** parar o polling, desconectar ou perder a conexão encerram a guarda e publicam `timeout`, para a tela não ficar esperando um evento que não virá. Isso não muda o contrato (a fase `timeout` já existia). No `shutdown` a limpeza é feita sem publicar eventos.
- Ordem em `disconnect`/`stopPolling`/`shutdown`: a fila de envio é limpa **antes** de abortar a guarda, para a ordem de limpeza (flag `false`) não ser descartada.
- **UI:** origem, reset de erro e limpar dados passam a pedir confirmação; origem e reset de erro ficam desabilitados com a máquina em execução; Iniciar fica desabilitado durante operação dos motores; a tela dos motores exige o polling e avisa que a máquina fica em STOP no fim.

## Contrato
Sem mudança na seção 6.2: `originReset`, `errorRestore`, `clearData {mode}`, `setMotorPosition {p1,p2}` e `startMotorSelfCheck {timeoutSec?}` já estavam no contrato. Novos erros: `BUSY` (operação dos motores em andamento, ou máquina em execução), `SDK_ERROR` (polling desligado), `INVALID_ARGS` (posições iguais às atuais), `OUT_OF_RANGE` (posição negativa, `timeoutSec` fora de 1 a 600).

## Consequências
- O `FakeMachineGateway` espelha as mesmas regras (polling, `BUSY`, aborto como `timeout`).
- Testes ao fim da fase: 162 em Kotlin, 84 no plugin Dart, 135 no app.
- Não validado no hardware: se o SDK limpa os flags sozinho, o tempo real de ajuste, o `liftMotorStatus` observado, o efeito de `originReset`, `errorRestore` e `clearData` nos campos do status.
