package com.goper.sdk850_bridge

import com.sunway.sdk850.port.bean.DeviceStatus
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** Disparo único e motores de elevação (Fase 5). */
internal class OneShotAndLiftTest {
    private val port = FakePort()
    private val scheduler = FakeScheduler()
    private val controller = MachineController(port, scheduler, FakeClock())
    private val events = mutableListOf<Map<String, Any?>>()

    @BeforeTest
    fun setUp() {
        controller.emitter = { events += it }
    }

    private fun connect() {
        controller.initialize("sp", null, null, null, null)
        port.connected = true
        port.state = "CONNECTED"
    }

    private fun connectAndPoll() {
        connect()
        controller.startPolling(200)
        scheduler.advance(0)
        port.calls.clear()
        port.sent.clear()
        port.controlSnapshots.clear()
    }

    private fun codeOf(block: () -> Unit): String = assertFailsWith<BridgeException>(block = block).code

    private fun liftStatus(value: Int): DeviceStatus = DeviceStatus().also { it.liftMotorStatus = value }

    private fun liftEvents() = events.filter { it["type"] == "liftMotor" }

    private fun phases() = liftEvents().map { it["phase"] }

    // ---- origem ----

    @Test
    fun originReset_enviaUmaVezComOsFlagsLigadosEDepoisDesliga() {
        connect()

        controller.originReset()

        assertEquals(1, port.controlSnapshots.size, "um único comando")
        val sent = port.controlSnapshots.single()
        assertTrue(sent.needSetOrigin)
        assertEquals("ALL", sent.clearMode)
        assertFalse(port.control.needSetOrigin)
        assertEquals("NONE", port.control.clearMode)
    }

    @Test
    fun originReset_oPollingDepoisNaoRepeteOComando() {
        connectAndPoll()

        controller.originReset()
        port.controlSnapshots.clear()
        scheduler.advance(1_000)

        assertTrue(port.controlSnapshots.isNotEmpty(), "o polling segue enviando")
        assertTrue(port.controlSnapshots.none { it.needSetOrigin || it.clearMode != "NONE" })
    }

    @Test
    fun originReset_comAMaquinaEmExecucaoViraBUSYENaoEnvia() {
        connect()
        port.control = defaultControl().copy(run = "RUNNING")

        assertEquals(BridgeException.BUSY, codeOf { controller.originReset() })

        assertTrue(port.controlSnapshots.isEmpty())
        assertFalse(port.control.needSetOrigin)
    }

    @Test
    fun originReset_semConexaoViraNOT_CONNECTED() {
        controller.initialize("sp", null, null, null, null)

        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.originReset() })
    }

    @Test
    fun disparoUnico_seOEnvioFalhaOsFlagsMesmoAssimDesligam() {
        connect()
        port.failSend = IllegalStateException("fila cheia")

        assertFailsWith<IllegalStateException> { controller.originReset() }

        assertFalse(port.control.needSetOrigin)
        assertEquals("NONE", port.control.clearMode)
    }

    // ---- reset de erro ----

    @Test
    fun errorRestore_enviaRunErrorRestoreUmaVezEVoltaASTOP() {
        connect()

        controller.errorRestore()

        assertEquals(1, port.controlSnapshots.size)
        val sent = port.controlSnapshots.single()
        assertTrue(sent.needErrorRestor)
        assertEquals("ERROR_RESTORE", sent.run)
        assertFalse(port.control.needErrorRestor)
        assertEquals("STOP", port.control.run)
    }

    @Test
    fun errorRestore_seOEnvioFalhaVoltaASTOPEDesligaOFlag() {
        connect()
        port.failSend = IllegalStateException("fila cheia")

        assertFailsWith<IllegalStateException> { controller.errorRestore() }

        assertEquals("STOP", port.control.run)
        assertFalse(port.control.needErrorRestor)
    }

    @Test
    fun errorRestore_comAMaquinaEmExecucaoViraBUSY() {
        connect()
        port.control = defaultControl().copy(run = "RUNNING")

        assertEquals(BridgeException.BUSY, codeOf { controller.errorRestore() })

        assertTrue(port.controlSnapshots.isEmpty())
        assertEquals("RUNNING", port.control.run, "a execução não é tocada")
    }

    // ---- limpar dados ----

    @Test
    fun clearData_enviaOModoUmaVezEDepoisVoltaANONE() {
        connect()

        for (mode in listOf("FIRST", "SECOND", "ALL")) {
            port.controlSnapshots.clear()
            controller.clearData(mode)

            assertEquals(listOf(mode), port.controlSnapshots.map { it.clearMode }, mode)
            assertEquals("NONE", port.control.clearMode)
        }
    }

    @Test
    fun clearData_NONENaoFazNada() {
        connect()
        port.calls.clear()

        controller.clearData("NONE")

        assertTrue(port.controlSnapshots.isEmpty())
        assertTrue(port.calls.none { it.startsWith("setClearMode") })
    }

    @Test
    fun clearData_naoMexeNaExecucao() {
        connect()
        port.control = defaultControl().copy(run = "RUNNING")

        controller.clearData("ALL")

        assertEquals("RUNNING", port.control.run)
        assertEquals("RUNNING", port.controlSnapshots.single().run)
    }

    @Test
    fun startPolling_desligaFlagsQueSobraramDeUmaSessaoAnterior() {
        connect()
        port.control = defaultControl().copy(
            needSetOrigin = true,
            needErrorRestor = true,
            clearMode = "ALL",
            motorSelfCheck = true
        )

        controller.startPolling(200)
        scheduler.advance(0)

        val first = port.controlSnapshots.first()
        assertFalse(first.needSetOrigin)
        assertFalse(first.needErrorRestor)
        assertFalse(first.motorSelfCheck)
        assertEquals("NONE", first.clearMode)
    }

    // ---- posição dos motores ----

    @Test
    fun setMotorPosition_exigePollingLigado() {
        connect()

        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.setMotorPosition(3, 4) })

        assertTrue(port.controlSnapshots.isEmpty())
    }

    @Test
    fun setMotorPosition_validaAsPosicoes() {
        connectAndPoll()
        port.control = defaultControl().copy(motorPosition1 = 2, motorPosition2 = 2)

        assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.setMotorPosition(-1, 2) })
        assertEquals(BridgeException.INVALID_ARGS, codeOf { controller.setMotorPosition(2, 2) })

        assertTrue(liftEvents().isEmpty())
        assertEquals(2, port.control.motorPosition1)
    }

    @Test
    fun setMotorPosition_paraAntesGravaAsPosicoesEIniciaAGuarda() {
        connectAndPoll()
        port.control = defaultControl().copy(run = "RUNNING", motorPosition1 = 2, motorPosition2 = 2)

        controller.setMotorPosition(3, 5)

        val stop = port.controlSnapshots.first()
        assertEquals("STOP", stop.run, "o STOP sai antes de mexer nas posições")
        assertEquals(2, stop.motorPosition1)
        assertEquals(
            listOf("markStop", "send:0C", "setMotorPositions:3:5"),
            port.calls.filter { it == "markStop" || it.startsWith("send") || it.startsWith("setMotorPositions") }
        )
        assertEquals(3, port.control.motorPosition1)
        assertEquals(5, port.control.motorPosition2)
        assertEquals(listOf("started"), phases())
        assertEquals(MachineController.LIFT_ADJUST_TIMEOUT_SEC, liftEvents().single()["remainingSec"])
    }

    @Test
    fun setMotorPosition_terminaPeloStatusEFicaEmSTOPSemReiniciar() {
        connectAndPoll()
        controller.setMotorPosition(3, 5)

        controller.onStatus(liftStatus(0x01))
        scheduler.advance(8_000)
        controller.onStatus(liftStatus(0x00))

        assertEquals(listOf("started", "completed"), phases())
        assertEquals("STOP", port.control.run)
        assertTrue(port.calls.none { it == "setRunning:true" }, "diferente do demo, não reinicia sozinho")
    }

    @Test
    fun setMotorPosition_estourouOTimeoutPublicaTimeoutEVoltaASTOP() {
        connectAndPoll()
        controller.setMotorPosition(3, 5)

        scheduler.advance(MachineController.LIFT_ADJUST_TIMEOUT_SEC * 1_000L)

        assertEquals(listOf("started", "timeout"), phases())
        assertEquals("STOP", port.control.run)
    }

    @Test
    fun setMotorPosition_perderAConexaoPublicaTimeout() {
        connectAndPoll()
        controller.setMotorPosition(3, 5)

        port.connected = false
        controller.onDisconnected("/dev/ttyS9")

        assertEquals(listOf("started", "timeout"), phases())
    }

    @Test
    fun durante_umaOperacaoDosMotores_naoIniciaNemAceitaOutra() {
        connectAndPoll()
        port.control = defaultControl().copy(force = 10)
        controller.setMotorPosition(3, 5)
        port.calls.clear()

        assertEquals(BridgeException.BUSY, codeOf { controller.start() })
        assertEquals(BridgeException.BUSY, codeOf { controller.startMotorSelfCheck(130) })
        assertEquals(BridgeException.BUSY, codeOf { controller.setMotorPosition(7, 8) })
        assertEquals(BridgeException.BUSY, codeOf { controller.originReset() })
        assertEquals(BridgeException.BUSY, codeOf { controller.errorRestore() })
        assertEquals(BridgeException.BUSY, codeOf { controller.clearData("ALL") })

        assertTrue(port.calls.none { it == "setRunning:true" || it.startsWith("setMotorPositions") })
    }

    @Test
    fun durante_umaOperacaoDosMotores_oStopContinuaFuncionando() {
        connectAndPoll()
        controller.setMotorPosition(3, 5)
        port.calls.clear()

        controller.stop()

        assertTrue(port.calls.contains("markStop"))
        assertTrue(port.calls.contains("send:0C"))
    }

    // ---- autoteste ----

    @Test
    fun autoteste_exigePollingEValidaOTimeout() {
        connect()
        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.startMotorSelfCheck(130) })

        controller.startPolling(200)
        assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.startMotorSelfCheck(0) })
        assertEquals(
            BridgeException.OUT_OF_RANGE,
            codeOf { controller.startMotorSelfCheck(MachineController.MAX_SELF_CHECK_TIMEOUT_SEC + 1) }
        )
        assertFalse(port.control.motorSelfCheck)
    }

    @Test
    fun autoteste_paraAMaquinaLigaOFlagEIniciaAGuarda() {
        connectAndPoll()
        port.control = defaultControl().copy(run = "RUNNING")

        controller.startMotorSelfCheck(130)

        assertEquals("STOP", port.controlSnapshots.first().run, "o Javadoc exige o movimento parado")
        assertTrue(port.control.motorSelfCheck)
        assertEquals(listOf("started"), phases())
        assertEquals(130, liftEvents().single()["remainingSec"])
    }

    @Test
    fun autoteste_oPollingCarregaOFlagAteTerminar() {
        connectAndPoll()
        controller.startMotorSelfCheck(130)
        port.controlSnapshots.clear()

        scheduler.advance(1_000)

        assertTrue(port.controlSnapshots.isNotEmpty())
        assertTrue(port.controlSnapshots.all { it.motorSelfCheck })
    }

    @Test
    fun autoteste_aoConcluirDesligaOFlagEEnviaNaHora() {
        connectAndPoll()
        controller.startMotorSelfCheck(130)
        controller.onStatus(liftStatus(0x02))
        port.controlSnapshots.clear()

        controller.onStatus(liftStatus(0x00))

        assertEquals(listOf("started", "completed"), phases())
        assertFalse(port.control.motorSelfCheck)
        val immediate = port.controlSnapshots.first()
        assertFalse(immediate.motorSelfCheck, "o Javadoc pede responder false imediatamente")
        assertEquals("STOP", immediate.run)
    }

    @Test
    fun autoteste_estourouOTimeoutDesligaOFlag() {
        connectAndPoll()
        controller.startMotorSelfCheck(5)

        scheduler.advance(5_000)

        assertEquals(listOf("started", "timeout"), phases())
        assertFalse(port.control.motorSelfCheck)
    }

    @Test
    fun autoteste_pararOPollingAbortaEDesligaOFlag() {
        connectAndPoll()
        controller.startMotorSelfCheck(130)

        controller.stopPolling()

        assertEquals(listOf("started", "timeout"), phases())
        assertFalse(port.control.motorSelfCheck)
        assertNotNull(port.controlSnapshots.lastOrNull { !it.motorSelfCheck }, "a ordem false ainda sai")
    }

    @Test
    fun autoteste_desconectarAbortaEDesligaOFlag() {
        connectAndPoll()
        controller.startMotorSelfCheck(130)

        controller.disconnect()

        assertEquals(listOf("started", "timeout"), phases())
        assertFalse(port.control.motorSelfCheck)
    }

    @Test
    fun shutdown_comAutotesteEmAndamentoDesligaOFlagSemPublicarEvento() {
        connectAndPoll()
        controller.startMotorSelfCheck(130)
        events.clear()

        controller.shutdown()

        assertFalse(port.control.motorSelfCheck)
        assertTrue(events.isEmpty(), "o canal já foi cancelado")
    }
}
