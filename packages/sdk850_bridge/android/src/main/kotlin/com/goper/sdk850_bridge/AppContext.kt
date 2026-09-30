package com.goper.sdk850_bridge

import android.content.Context

/**
 * Contexto da aplicação, preenchido pelo plugin ao anexar ao engine. Fica fora do
 * [MachineController] para a lógica não depender de classes Android nos testes.
 */
object AppContext {
    @Volatile
    var application: Context? = null

    fun require(): Context = application
        ?: throw BridgeException(BridgeException.SDK_ERROR, "Plugin não está anexado a um engine")
}
