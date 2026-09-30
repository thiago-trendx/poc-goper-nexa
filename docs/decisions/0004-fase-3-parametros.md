# ADR 0004 — Fase 3: parâmetros do dispositivo

Status: aceito (Fase 3, GOPER-5982)

## Contexto
A Fase 3 lê, valida e envia os 11 campos de `DeviceParams` (calibração da máquina) e guarda perfis. O plano previa "ler da máquina" e enviar o perfil ativo ao conectar, como faz o demo.

## Decisões

### Enviar só por ação explícita (decisão do usuário)
- Nada envia `DeviceParams` ao conectar nem ao ligar o polling. O único caminho é o botão **Enviar ao controlador**, com confirmação. Testes garantem isso na ponte (`MachineController`) e na tela. O demo envia no `onConnected`; aqui não, porque enviar calibração altera a máquina e o controlador já responde ao polling sem isso.
- Carregar um perfil só preenche o formulário; nunca envia.

### "Ler" lê o cache do app, não o controlador
- O protocolo não tem comando de leitura de parâmetros (só `quaryDeviceInfo`, `sendParams` e `control`). `DeviceManager.getDeviceParams()` devolve o cache local (SharedPreferences), que o SDK também atualiza com o retorno de `SEND_PARAMS`. Os setters de `DeviceParams` persistem no cache **antes** de o controlador confirmar.
- A tela se chama "Ler valores salvos" e explica a origem. O repositório inicializa o SDK antes de ler ou enviar (o `DeviceManager` precisa do `init`).
- O controlador só informa os parâmetros dele em resposta a um envio (`paramsAck`). Quando os valores devolvidos diferem dos enviados, a tela lista campo, enviado e devolvido. Sem confirmação em 3 s, avisa e libera novo envio.

### Validação
- `sendDeviceParams` valida tudo antes de aplicar qualquer setter: campo ausente ou com tipo errado vira `INVALID_ARGS`; valor fora da faixa do Javadoc vira `OUT_OF_RANGE`, com os campos nos `details`. Nada é aplicado em caso de erro.
- As faixas existem em Kotlin (`ParamRanges`) e em Dart (`DeviceParamField`); testes verificam limites inferior e superior de cada campo nos dois lados.

### Perfis
- JSON em `<documentos do app>/profiles/<nome>.json` (nome, data e 11 campos). Nomes de 1 a 40 caracteres, só letras, números, espaço, `-`, `_` e `.`, sem começar ou terminar com espaço ou ponto: impede `../` e caracteres de caminho antes de tocar no disco.

## Observado na bancada (2026-09-30)
Detalhes em `docs/checklist-hardware.md`.
- Os valores iniciais do cache (`5 / 120 / 5 / 100 / 150 / 25 / 2 / 50 / 10 / 10 / 10`) coincidem com o painel original.
- Envio de teste (força mínima 15) e restauração (5): o controlador confirmou os dois, em ~92 ms, sem divergência. **A calibração da máquina foi alterada durante o teste e restaurada ao valor original.**
- Bytes do envio e da resposta decodificados; o byte alto de `ratedSpeed` vai como `FF` e volta como `00` (hipótese de extensão de sinal no SDK, a confirmar com o fabricante).

## Consequências
- O log do app mostra `TX SEND_PARAMS` (nome do comando traduzido) e `RX SEND_PARAMS`; o hex da resposta só aparece no `logcat` do SDK.
- Testes: 90 em Kotlin, 67 no plugin Dart e 120 no app.
