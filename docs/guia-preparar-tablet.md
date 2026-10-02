# Guia: preparar um tablet da equipe para o Workbench 850

Para quem vai rodar o app em um tablet novo, ligado à máquina de força 850. Tudo aqui foi observado no **tablet de bancada** (Rockchip RK3568, Android 11) e **não foi confirmado pelo fabricante**. Em outro modelo de tablet, as portas e as permissões podem ser diferentes: use a seção 2 para conferir antes de instalar.

O app não precisa ser app de sistema nem ter root (decisão no ADR 0008).

## 1. O que você precisa
- Tablet com depuração USB ligada e o cabo serial da máquina já conectado.
- PC com `adb` (Android Platform Tools) e o APK do app.
- A máquina ligada. **Durante qualquer teste que mova a máquina: duas pessoas, parada de emergência física ao alcance, área livre.**

## 2. Conferir o tablet antes de instalar
Com `adb devices` mostrando o tablet, rode (todos são só leitura):

```bash
adb shell getprop ro.product.model        # modelo do tablet
adb shell getprop ro.build.version.sdk    # versão do Android (tablet de bancada: 30)
adb shell getprop ro.product.cpu.abi      # arquitetura (tablet de bancada: arm64-v8a)
adb shell getenforce                      # SELinux: Permissive ou Enforcing
adb shell ls -l /dev/ttyS* /dev/ttyUSB*   # portas seriais e permissões
adb shell pm list packages | grep -i oma  # app do fornecedor presente?
```

Como ler:
- **Portas com permissão `rw-rw-rw-` (666):** qualquer app consegue abrir. É o caso do tablet de bancada (`ttyS2`, `ttyS8`, `ttyS9`, dono `system`). Se a porta da máquina não for 666, o app comum **não** consegue abrir; nesse caso este guia não resolve e é preciso falar com quem mantém a ROM.
- **A porta da máquina:** no tablet de bancada é `/dev/ttyS9` a 115200 bps. O app varre `ttyS2`, `ttyS8` e `ttyS9` na conexão automática. Se o tablet novo usar outra porta, a varredura automática pode não achá-la: a lista varrida (`ttyS2`, `ttyS8`, `ttyS9`) é a que apareceu no log do SDK, e ela não foi alterada por nós.
- **SELinux:** o tablet de bancada está em `Permissive`. Em `Enforcing` o resultado **não foi testado**.
- **`adb root`, `setenforce` e `chmod` do plano original não funcionam neste build `user` e não são necessários.**

## 3. Instalar
Gere o APK com o gateway real (o padrão do app é o **simulado**, que mostra a barra âmbar "SIMULADO"):

```bash
cd apps/workbench
flutter build apk --debug --dart-define=GATEWAY=device
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```

O pacote é `com.goper.poc_goper_nexa`. Para abrir: `adb shell am start -n com.goper.poc_goper_nexa/.MainActivity`. Não rode pelo IDE sem o `--dart-define`: o app subiria simulado.

Opcional: `--dart-define=MAX_FORCE_KG=<kg>` muda o limite de carga do app (padrão 30 kg).

## 4. Primeira conexão
1. Abra o app e confira que **não** há a barra âmbar "SIMULADO".
2. Tela Conexão → **Conexão automática**. Esperado: "conectado" em `/dev/ttyS9`.
3. Ligue o polling (200 ms). A tela Telemetria deve mostrar ~4 Hz.
4. Tela Parâmetros → "Ler valores salvos" é só leitura. **Não envie parâmetros ao controlador** sem decisão de quem conhece a calibração da máquina.
5. Antes de qualquer movimento, siga os roteiros de `docs/checklist-hardware.md`: carga baixa (5 kg), modo Padrão, parada física ao alcance.

## 5. Se a conexão falhar
| Sintoma | O que já se observou | O que fazer |
| --- | --- | --- |
| "nenhuma porta disponível" (`未找到可用串口`) e `ttyS9` com "returns null" no log | Aconteceu uma vez; depois de parar o app do fornecedor e tentar de novo, conectou. **Hipótese não confirmada:** o app do fornecedor segura a `ttyS9`. | `adb shell am force-stop com.oma.doublecontrol` e tentar de novo. Se o app do fornecedor voltar sozinho (ele reage à instalação de apps), repita antes de conectar. |
| `ttyS2` e `ttyS8` abrem mas não respondem | É normal: só a `ttyS9` tem a máquina. | Nada; o erro real é o da `ttyS9`. |
| Nenhuma porta aparece | Cabo serial fora ou máquina desligada. | Conferir cabo e energia; `ls -l /dev/ttyS*`. |
| `adb devices` vazio | Costuma ser físico: porta/cabo USB do tablet. | Trocar cabo/porta; no Windows, conferir o driver (VID `2207` no tablet de bancada). |
| Respostas lentas ou perdidas | Abaixo de ~100 ms de polling o controlador responde cada vez menos. | Usar 200 ms (padrão) ou 100 ms; nunca menos que 100 ms. |

Para diagnosticar, o log da varredura do SDK está no `logcat`:

```bash
adb logcat -d | grep -E "SerialPortScanner|SerialPortManager|serial_port"
```

## 6. Pegar os arquivos do app
Logs, CSVs e relatórios ficam em `Android/data/com.goper.poc_goper_nexa/files`, sem precisar de permissão de armazenamento:

```bash
adb shell ls /sdcard/Android/data/com.goper.poc_goper_nexa/files
adb pull /sdcard/Android/data/com.goper.poc_goper_nexa/files/<arquivo> .
```

- `workbench_log_*.txt`: log (o app guarda só as últimas 2000 linhas; salve logo após cada teste).
- `workbench_telemetria_*.csv` e `workbench_relatorio_*.txt`: da tela Telemetria.

## 7. Segurança (resumo; o completo está no plano, seção 7.5)
- O botão **STOP** fica fixo em todas as telas.
- O limite de carga do app vale também no código nativo.
- Ao fechar o app ou ir para segundo plano, o app envia STOP e para o polling. Trocar de tela **não** para a máquina: o indicador "EM EXECUÇÃO" aparece na barra de qualquer tela, e o STOP fixo continua embaixo.
- Desconectar e desligar o polling enviam STOP antes. Parâmetros e firmware só com a máquina parada.
- Origem, reset de erro e limpar dados pedem confirmação; autoteste e ajuste de posição dos motores também.
- A máquina nunca reinicia sozinha depois de um ajuste.
- Nunca versione credenciais, chaves de assinatura nem o `release.jks` do demo.

## 8. Opcional: APK release
Só vale se a equipe for receber um APK release em vez do debug. O release usa a chave de debug, então instala por cima do debug (mesma assinatura) e **não serve para publicação**.

```bash
cd apps/workbench
flutter build apk --release --dart-define=GATEWAY=device
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

Teste obrigatório do release, porque o R8 já derrubou o app uma vez (sem as regras do plugin, **Desconectar** fechava o app): conectar, ligar o polling, abrir Controle, sair da tela, **desconectar** e conectar de novo. Se o app fechar, é o R8: veja `packages/sdk850_bridge/android/consumer-rules.pro` e o `logcat` (`NoSuchFieldError mFd`).

**Não foi feito ainda:** este teste do release no tablet (só o debug foi validado em hardware).

## 9. O que ainda não se sabe
- Se o app do fornecedor realmente disputa a serial.
- Se outros modelos de tablet usam a mesma porta e permissões.
- Comportamento com SELinux em `Enforcing`.
- Perguntas ao fabricante em aberto: seção 10 do plano.
