package com.goper.sdk850_bridge

/** Leitura e validação dos argumentos que chegam do Dart. */
object Args {
    /** Valores do demo (`WelcomeActivity`): 115200 bps, 50 ms entre envios, 500 ms de handshake. */
    const val DEFAULT_BAUD_RATE = 115200
    const val DEFAULT_SEND_INTERVAL_MS = 50L
    const val DEFAULT_TEST_TIME_MS = 500L

    /** Intervalo padrão do polling (`LOOP_SPACE` do demo). */
    const val DEFAULT_POLLING_MS = 200

    /**
     * Faixa aceita para o intervalo de polling. O menor intervalo que o controlador suporta
     * ainda é pergunta em aberto (nº 1 do plano); 10 ms só evita um laço sem pausa.
     */
    const val MIN_POLLING_MS = 10
    const val MAX_POLLING_MS = 5000

    fun string(args: Map<*, *>?, key: String): String {
        val value = args?.get(key)
        if (value is String && value.isNotBlank()) return value
        throw BridgeException(BridgeException.INVALID_ARGS, "Argumento \"$key\" deve ser um texto não vazio")
    }

    fun optionalInt(args: Map<*, *>?, key: String): Int? {
        val value = args?.get(key) ?: return null
        if (value is Number) return value.toInt()
        throw BridgeException(BridgeException.INVALID_ARGS, "Argumento \"$key\" deve ser um inteiro")
    }

    fun optionalLong(args: Map<*, *>?, key: String): Long? {
        val value = args?.get(key) ?: return null
        if (value is Number) return value.toLong()
        throw BridgeException(BridgeException.INVALID_ARGS, "Argumento \"$key\" deve ser um inteiro")
    }

    fun optionalBool(args: Map<*, *>?, key: String): Boolean? {
        val value = args?.get(key) ?: return null
        if (value is Boolean) return value
        throw BridgeException(BridgeException.INVALID_ARGS, "Argumento \"$key\" deve ser booleano")
    }

    fun pollingInterval(args: Map<*, *>?): Int {
        val ms = optionalInt(args, "intervalMs") ?: DEFAULT_POLLING_MS
        if (ms < MIN_POLLING_MS || ms > MAX_POLLING_MS) {
            throw BridgeException(
                BridgeException.OUT_OF_RANGE,
                "intervalMs deve estar entre $MIN_POLLING_MS e $MAX_POLLING_MS ms"
            )
        }
        return ms
    }
}
