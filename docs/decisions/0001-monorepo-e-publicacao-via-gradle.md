# ADR 0001 — Monorepo e publicação do `.aar` via Gradle

Status: aceito (Fase 0, GOPER-5979)

## Contexto
O projeto foi iniciado com `flutter create` na raiz. O plano (seção 4) prevê um monorepo com `apps/workbench` e `packages/sdk850_bridge`. A seção 5.2 sugere `mvn deploy:deploy-file`, mas o Maven não está instalado na máquina de desenvolvimento; o plano permite trocar por um projeto Gradle com `maven-publish`.

## Decisões
1. O app existente foi movido para `apps/workbench`, mantendo nome de pacote `poc_goper_nexa` e appId `com.goper.poc_goper_nexa`. A raiz virou workspace (`docs/`, `third_party/`, `tools/`, `maven-repo/`).
2. O `.aar` é publicado por `tools/maven` (Gradle `maven-publish`, wrapper próprio) em `maven-repo/`. O POM gerado é equivalente a `tools/maven/sdk850-1.0.0.pom` (mantido como referência para quem preferir `mvn`), com `com.licheedev:android-serialport:2.1.4` como dependência transitiva.
3. A URL do repositório vem de `sdk850MavenUrl` (app) e, sem ela, o plugin usa `maven-repo/` da raiz. O repositório é restrito ao grupo `com.sunway`.

## Consequências
- `flutter build apk --debug` consome `com.sunway:sdk850:1.0.0` do Maven, sem `.aar` em `libs/`.
- O demo resolve `android-serialport` por `google()`, `mavenCentral()` e `jitpack.io`; no nosso build ele resolveu sem precisar do JitPack.
- Pendente com o fabricante: licença de redistribuição do `.aar` (pergunta 8), que afeta versioná-lo em `third_party/` e `maven-repo/`.
