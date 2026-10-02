# Workbench 850 — instruções para o Claude Code

App Flutter de bancada para testar a máquina de força 850 via serial, com plugin Android `sdk850_bridge`.
**Leia `docs/PROPOSTA_WORKBENCH_850.md` antes de qualquer trabalho** — ele é a fonte de verdade de arquitetura, contrato do canal, segurança e fases.

Jira: história GOPER-5978 (subtarefas por fase, GOPER-5979 a 5986). Perguntas em aberto ao fabricante: seção 10 do plano.

## Estrutura
- `apps/workbench/` — app Flutter (BLoC). Plugin referenciado por caminho local.
- `packages/sdk850_bridge/` — plugin Flutter só Android (Kotlin + API Dart + gateway falso).
- `third_party/sdk850/` — material do fabricante, **somente leitura** (`.aar`, Javadoc, guias em chinês, demo).
- `tools/maven/` — publica o `.aar` como `com.sunway:sdk850:1.0.0` em `maven-repo/` (`publish_sdk850.sh`; usa Gradle `maven-publish`, não precisa de Maven).
- `maven-repo/` — repositório Maven local (opção A). O `.aar` nunca vai em `libs/`.
- `docs/decisions/` — ADRs curtos, um por decisão nova.
- `docs/guia-preparar-tablet.md` — como conferir e preparar outro tablet, instalar, conectar e pegar os arquivos (Fase 8 reduzida, ADR 0008).

## Regras
- Trabalhe **uma fase por vez** (seção 8 do plano). Ao final de cada fase: `flutter analyze`, `flutter test` e `flutter build apk --debug` em `apps/workbench`, e resuma o que foi feito.
- Nomes de API do SDK vêm do Javadoc (`third_party/sdk850/javadoc/`) e do demo. Não invente métodos e **não descompile o `.aar`**. Se algo não estiver documentado, pare e pergunte.
- Qualquer mudança no contrato do canal (seção 6.2) é proposta antes e registrada em ADR.
- **Nunca remova nem enfraqueça** os requisitos de segurança da seção 7.5 (STOP fixo, limite de carga, confirmações, estado de erro, stop ao sair).
- **Nunca versione** credenciais, chaves de assinatura, `key.properties` nem o `release.jks` do demo.
- Itens que dependem de hardware estão listados na memória do projeto (perguntas verificáveis na bancada); registre o que for observado como "observado, não confirmado pelo fabricante".
- Comentários e mensagens de commit em português. Identificadores de código em inglês.

## Comandos
```bash
tools/maven/publish_sdk850.sh                 # (re)publica o .aar em maven-repo/
cd apps/workbench && flutter pub get && flutter analyze && flutter test
cd apps/workbench && flutter build apk --debug
cd packages/sdk850_bridge && flutter analyze && flutter test
cd apps/workbench && flutter run --dart-define=GATEWAY=fake      # sem hardware (padrão)
cd apps/workbench && flutter run --dart-define=GATEWAY=device    # máquina real (Fase 2 em diante)
```
`--dart-define=MAX_FORCE_KG=<kg>` ajusta o limite de carga do app (padrão 30 kg). Decisões de cada fase: `docs/decisions/`.
A propriedade `sdk850MavenUrl` (em `apps/workbench/android/gradle.properties`) define o repositório Maven; para o repositório interno (opção B) use `-Psdk850PublishUrl=` no script de publicação.
