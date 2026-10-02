package com.goper.sdk850_bridge

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class LiftMotorGuardTest {
    private val scheduler = FakeScheduler()
    private val phases = mutableListOf<Pair<LiftPhase, Int>>()
    private val guard = LiftMotorGuard(scheduler) { phase, remaining -> phases += phase to remaining }

    @Test
    fun begin_publicaStartedComOTimeoutEFicaAtiva() {
        guard.begin(130)

        assertEquals(listOf(LiftPhase.STARTED to 130), phases)
        assertTrue(guard.isActive)
        assertEquals(130, guard.remainingSec)
    }

    @Test
    fun begin_comTimeoutInvalidoOuJaAtivaFalha() {
        assertFailsWith<IllegalArgumentException> { guard.begin(0) }
        guard.begin(5)
        assertFailsWith<IllegalStateException> { guard.begin(5) }
    }

    @Test
    fun timeout_encerraUmaSoVezNoFimDaContagem() {
        guard.begin(3)

        scheduler.advance(2_999)
        assertTrue(guard.isActive)
        assertEquals(1, phases.size)

        scheduler.advance(1)
        assertFalse(guard.isActive)
        assertEquals(listOf(LiftPhase.STARTED to 3, LiftPhase.TIMEOUT to 0), phases)

        scheduler.advance(60_000)
        assertEquals(2, phases.size, "nada se repete depois do fim")
        assertEquals(0, scheduler.pendingTasks)
    }

    @Test
    fun conclusao_exigeVerOMotorEmMovimentoOuAutotesteEDepoisParado() {
        guard.begin(130)

        guard.onLiftStatus(0x00) // ainda parado: não é conclusão
        assertTrue(guard.isActive)

        guard.onLiftStatus(0x01)
        assertTrue(guard.isActive)
        scheduler.advance(5_000)
        guard.onLiftStatus(0x00)

        assertFalse(guard.isActive)
        assertEquals(LiftPhase.COMPLETED to 125, phases.last())
        assertEquals(0, scheduler.pendingTasks, "o timeout é cancelado")
    }

    @Test
    fun autoteste_0x02TambemContaComoAtividade() {
        guard.begin(130)
        guard.onLiftStatus(0x02)
        guard.onLiftStatus(0x00)

        assertEquals(LiftPhase.COMPLETED, phases.last().first)
    }

    @Test
    fun statusDepoisDoFim_Ignorado() {
        guard.begin(130)
        guard.onLiftStatus(0x01)
        guard.onLiftStatus(0x00)
        guard.onLiftStatus(0x01)
        guard.onLiftStatus(0x00)

        assertEquals(2, phases.size)
    }

    @Test
    fun abort_contaComoTimeoutEcancelaOTimer() {
        guard.begin(130)
        guard.abort()

        assertEquals(LiftPhase.TIMEOUT to 0, phases.last())
        assertFalse(guard.isActive)
        assertEquals(0, scheduler.pendingTasks)
    }

    @Test
    fun abort_semOperacaoNaoFazNada() {
        guard.abort()

        assertTrue(phases.isEmpty())
    }

    @Test
    fun podeIniciarDeNovoDepoisDoFim() {
        guard.begin(2)
        scheduler.advance(2_000)
        guard.begin(4)

        assertEquals(LiftPhase.STARTED to 4, phases.last())
        assertTrue(guard.isActive)
    }
}
