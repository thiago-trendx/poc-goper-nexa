# ADR 0008 — Fase 8: escopo reduzido (sem flavor `system`)

Status: aceito (Fase 8, GOPER-5986); decisão do usuário

## Contexto
O plano previa, na Fase 8, um flavor `system` (`android:sharedUserId="android.uid.system"`, assinado com a chave de plataforma da ROM), regras de R8 e um checklist de testes manuais. O POC só roda no tablet de bancada e nos tablets da própria equipe.

## Decisão
- **Não haverá flavor `system` nem uso de chave de plataforma.** O tablet de bancada já deixa o app comum abrir a serial (`ttyS*` com 666, SELinux `Permissive`), e a chave da ROM não está disponível (pergunta 4 do plano sem resposta). Assinar com a chave errada ainda poderia quebrar a instalação no aparelho de bancada.
- **O flavor `dev` do plano é o app atual**, sem flavors no Gradle.
- **R8:** as regras já estão no plugin (`consumer-rules.pro`). A verificação de um APK release no tablet fica como passo opcional do guia, só se a equipe for receber release.
- **No lugar da Fase 8 completa:** `docs/guia-preparar-tablet.md` (como conferir e preparar outro tablet, instalar, conectar, resolver falhas e pegar os arquivos).

## Consequências
- Nenhum código mudou. O release continua assinado com a chave de debug: serve para instalação interna, não para publicação.
- Se um dia o app precisar rodar como app de sistema, essa decisão volta a ser aberta e exige a chave da ROM de destino.
- O que continua pendente (fora da Fase 8): validar as Fases 5 e 6 na bancada, as melhorias do log e a Fase 7 (firmware), que depende da fábrica.
