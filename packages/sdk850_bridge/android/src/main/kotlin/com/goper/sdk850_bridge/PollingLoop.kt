package com.goper.sdk850_bridge

import android.os.Handler
import android.os.Looper

/** Agenda tarefas; existe para o [PollingLoop] poder ser testado sem um `Looper`. */
interface Scheduler {
    fun postDelayed(task: Runnable, delayMs: Long)
    fun removeCallbacks(task: Runnable)
}

/** [Scheduler] sobre um `Handler`, por padrão o da thread principal. */
class HandlerScheduler(
    private val handler: Handler = Handler(Looper.getMainLooper())
) : Scheduler {
    override fun postDelayed(task: Runnable, delayMs: Long) {
        handler.postDelayed(task, delayMs)
    }

    override fun removeCallbacks(task: Runnable) {
        handler.removeCallbacks(task)
    }
}

/**
 * Laço que executa [tick] a cada intervalo, começando imediatamente (como o demo).
 *
 * O `send` do SDK só enfileira e não bloqueia, então o laço pode rodar na thread principal.
 * Uma falha em [tick] vai para [onTickError] e não interrompe o laço.
 */
class PollingLoop(
    private val scheduler: Scheduler,
    private val onTickError: (Throwable) -> Unit = {},
    private val tick: () -> Unit
) {
    var intervalMs: Long = 0
        private set

    var isRunning: Boolean = false
        private set

    private val task = object : Runnable {
        override fun run() {
            if (!isRunning) return
            try {
                tick()
            } catch (e: Exception) {
                onTickError(e)
            }
            if (isRunning) scheduler.postDelayed(this, intervalMs)
        }
    }

    /** Inicia o laço; se já estiver rodando, reinicia com o novo [intervalMs]. */
    fun start(intervalMs: Long) {
        require(intervalMs > 0) { "intervalMs deve ser > 0" }
        stop()
        this.intervalMs = intervalMs
        isRunning = true
        scheduler.postDelayed(task, 0)
    }

    fun stop() {
        isRunning = false
        scheduler.removeCallbacks(task)
    }
}
