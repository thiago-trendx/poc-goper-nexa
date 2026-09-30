package com.goper.sdk850_bridge

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

internal class PollingLoopTest {
    private val scheduler = FakeScheduler()
    private var ticks = 0

    private fun loop(onError: (Throwable) -> Unit = {}, tick: () -> Unit = { ticks++ }) =
        PollingLoop(scheduler, onError, tick)

    @Test
    fun comecaImediatamenteERepeteNoIntervalo() {
        val loop = loop()
        loop.start(200)
        assertEquals(0, ticks, "nada roda antes de o agendador andar")

        scheduler.advance(0)
        assertEquals(1, ticks)
        scheduler.advance(199)
        assertEquals(1, ticks)
        scheduler.advance(1)
        assertEquals(2, ticks)
        scheduler.advance(600)
        assertEquals(5, ticks)
        assertTrue(loop.isRunning)
        assertEquals(200, loop.intervalMs)
    }

    @Test
    fun stopInterrompeEZeraATarefaAgendada() {
        val loop = loop()
        loop.start(100)
        scheduler.advance(250)
        val before = ticks

        loop.stop()
        scheduler.advance(1000)

        assertEquals(before, ticks)
        assertFalse(loop.isRunning)
        assertEquals(0, scheduler.pendingTasks)
    }

    @Test
    fun startDeNovoReiniciaComOutroIntervaloSemDuplicarTarefas() {
        val loop = loop()
        loop.start(200)
        scheduler.advance(400)
        ticks = 0

        loop.start(50)
        scheduler.advance(200)

        assertEquals(50, loop.intervalMs)
        assertEquals(5, ticks) // 0, 50, 100, 150 e 200 ms
        assertEquals(1, scheduler.pendingTasks)
    }

    @Test
    fun falhaNoTickVaiParaOCallbackENaoInterrompeOLaco() {
        val errors = mutableListOf<Throwable>()
        var calls = 0
        val loop = loop(onError = { errors += it }) {
            calls++
            if (calls == 2) error("falhou")
        }
        loop.start(100)
        scheduler.advance(300)

        assertEquals(4, calls)
        assertEquals(listOf("falhou"), errors.map { it.message })
        assertTrue(loop.isRunning)
    }

    @Test
    fun callbackDeErroPodePararOLaco() {
        lateinit var loop: PollingLoop
        loop = PollingLoop(scheduler, onTickError = { loop.stop() }) {
            ticks++
            error("falhou")
        }
        loop.start(100)
        scheduler.advance(1000)

        assertEquals(1, ticks)
        assertFalse(loop.isRunning)
        assertEquals(0, scheduler.pendingTasks)
    }

    @Test
    fun intervaloInvalidoELancado() {
        assertFailsWith<IllegalArgumentException> { loop().start(0) }
    }
}
