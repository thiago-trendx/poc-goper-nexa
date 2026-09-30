package com.goper.sdk850_bridge

/**
 * `Cmd.getCmdName` devolve o nome do comando em chinês. Para o log ficar legível ao lado dos
 * tipos de pacote recebidos (`CONTROL`, `DEVICE_INFO`), os nomes conhecidos são traduzidos;
 * os demais passam como vieram.
 */
object CommandNames {
    private val known = mapOf(
        "控制指令" to "CONTROL", // 控制指令: comando de controle
        "查询设备信息" to "QUERY_DEVICE_INFO", // 查询设备信息: consulta de informações do dispositivo
        "\u53c2\u6570\u4e0b\u53d1\u6307\u4ee4" to "SEND_PARAMS" // 参数下发指令: envio de parâmetros (resposta chega como SEND_PARAMS)
    )

    fun translate(raw: String): String = known[raw] ?: raw
}
