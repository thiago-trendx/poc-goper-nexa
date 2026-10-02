# ADR 0007 — Fase 6: telemetria (gráficos, CSV, teste de taxa e relatório)

Status: aceito em software (Fase 6, GOPER-5985); **validação na bancada pendente**

## Contexto
A Fase 6 só lê dados: não envia nenhum comando de movimento. Entrega gráficos, gravação em CSV, medição de taxa com teste de intervalos e o relatório com a taxa estável e os `errorCode` observados.

## Decisões
- **Gráficos** (`fl_chart ^1.2.0`): força real × tempo, velocidade × tempo (últimos 60 s, eixo em segundos antes da amostra mais recente) e força real × curso (últimas 240 amostras). Saem do buffer circular de 60 s do `TelemetryBloc`; eixos com folga e altura sempre > 0 para valores constantes não quebrarem o gráfico.
- **CSV:** `TelemetryCsv` (função pura) com cabeçalho fixo (`tsEpochMs,tsMonotonicMs,run,mode,force,realForce,speed,distance,pullNum,errorCode,temperature,liftMotorStatus,liftMotorError1,liftMotorError2,verityCodeError`), um status por linha e ponto como separador decimal. As amostras ficam em memória durante a gravação (teto de 100 000) e o arquivo é gravado ao **parar**; ligar de novo começa do zero. Sem amostras, ou se a gravação de arquivo falhar, a tela mostra o motivo.
- **Destino dos arquivos:** o mesmo do log (`Android/data/<pacote>/files`, acessível por `adb pull`). O código de gravação foi extraído para `shared/files/file_saver.dart`; `LogExporter` continua com a mesma interface. Arquivos novos: `workbench_telemetria_<data>.csv` e `workbench_relatorio_<data>.txt`.
- **Erros observados:** a cada status, os códigos diferentes de 0 de `errorCode`, `liftMotorError1`, `liftMotorError2` e `verityCodeError` são contados por origem e código, com o primeiro instante (relógio do aparelho). "Limpar gráficos" não apaga a tabela nem a gravação em andamento: é evidência da sessão.
- **Teste de taxa** (`RateTestCubit`): liga o polling em 200, 100 e 50 ms, 15 s cada, e mede com `tsMonotonicMs`: status recebidos, taxa (Hz), resposta (recebidos ÷ comandos que o intervalo pediria, limitada a 100%) e maior pausa. Segurança: o polling começa em STOP e o teste só roda **com a máquina parada** (estado local e reportado); se ela entrar em execução, a conexão cair ou o usuário cancelar, o teste termina e o polling volta ao estado e ao intervalo de antes.
- **Critério de "estável":** resposta ≥ 90%. O relatório informa dois números: o **menor intervalo estável** e o intervalo de **maior taxa de dados**, estável ou não (na Fase 2 o de 100 ms entregou mais dados que o de 200 ms, com ~82% de resposta).
- **Relatório:** texto com data, dados do controlador (se houver), tabela do teste de taxa, conclusão e tabela de erros; avisa que tudo é observado e não confirmado pelo fabricante e que o significado dos códigos depende da tabela do fabricante (pergunta em aberto).

## Consequências
- Nenhuma mudança no contrato do canal nem no código Kotlin.
- Testes ao fim da fase: 161 no app (162 em Kotlin e 84 no plugin Dart, sem mudança).
- Não validado no hardware: valores reais do teste de taxa, o desenho dos gráficos em movimento e o tamanho do CSV de uma sessão longa.
