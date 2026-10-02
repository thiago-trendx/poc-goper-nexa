package com.goper.sdk850_bridge

/** Fases de um ajuste de posição ou autoteste; os nomes vão como `phase` do evento `liftMotor`. */
enum class LiftPhase(val wire: String) {
    STARTED("started"),
    COMPLETED("completed"),
    TIMEOUT("timeout")
}

/**
 * Guarda de segurança dos motores de elevação.
 *
 * O controlador nem sempre informa "em ajuste" ou "em autoteste", então o fim da operação vem
 * de duas fontes: o status do motor voltar a `0x00` depois de ter sido `0x01`/`0x02` (como o
 * demo), ou o timeout. O que ocorrer primeiro encerra a guarda uma única vez.
 *
 * [onPhase] é chamado com `STARTED` (ao [begin]) e depois com `COMPLETED` ou `TIMEOUT`. O
 * chamador faz a limpeza (desligar o flag de autoteste, voltar a STOP) dentro dele, antes de
 * publicar o evento.
 */
class LiftMotorGuard(
    private val scheduler: Scheduler,
    private val onPhase: (phase: LiftPhase, remainingSec: Int) -> Unit
) {
    var isActive: Boolean = false
        private set

    var remainingSec: Int = 0
        private set

    private var sawActivity = false

    private val tick = object : Runnable {
        override fun run() {
            if (!isActive) return
            remainingSec--
            if (remainingSec <= 0) {
                finish(LiftPhase.TIMEOUT)
            } else {
                scheduler.postDelayed(this, ONE_SECOND_MS)
            }
        }
    }

    /** Inicia a contagem de [timeoutSec] segundos. */
    fun begin(timeoutSec: Int) {
        require(timeoutSec > 0) { "timeoutSec deve ser > 0" }
        check(!isActive) { "Já há uma operação dos motores em andamento" }
        isActive = true
        sawActivity = false
        remainingSec = timeoutSec
        scheduler.postDelayed(tick, ONE_SECOND_MS)
        onPhase(LiftPhase.STARTED, timeoutSec)
    }

    /** Alimenta a guarda com o `liftMotorStatus` de cada status recebido. */
    fun onLiftStatus(status: Int) {
        if (!isActive) return
        if (status == STATUS_MOVING || status == STATUS_SELF_CHECK) {
            sawActivity = true
        } else if (sawActivity) {
            finish(LiftPhase.COMPLETED)
        }
    }

    /**
     * Encerra sem conclusão (conexão perdida, polling parado, desligamento). Conta como
     * `TIMEOUT` para a tela não ficar esperando um evento que não virá.
     */
    fun abort() {
        if (isActive) finish(LiftPhase.TIMEOUT)
    }

    private fun finish(phase: LiftPhase) {
        val remaining = if (phase == LiftPhase.COMPLETED) remainingSec else 0
        isActive = false
        scheduler.removeCallbacks(tick)
        remainingSec = 0
        onPhase(phase, remaining)
    }

    companion object {
        const val STATUS_MOVING = 0x01
        const val STATUS_SELF_CHECK = 0x02
        private const val ONE_SECOND_MS = 1000L
    }
}
