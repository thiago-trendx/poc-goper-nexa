package com.goper.sdk850_bridge

/**
 * Falha de um método do canal. [code] é um dos códigos do contrato (seção 6.1 do plano) e
 * vira `result.error(code, message, details)`.
 */
class BridgeException(
    val code: String,
    message: String,
    val details: Any? = null
) : Exception(message) {
    companion object {
        const val NOT_CONNECTED = "NOT_CONNECTED"
        const val INVALID_ARGS = "INVALID_ARGS"
        const val OUT_OF_RANGE = "OUT_OF_RANGE"
        const val BUSY = "BUSY"
        const val SDK_ERROR = "SDK_ERROR"
    }
}
