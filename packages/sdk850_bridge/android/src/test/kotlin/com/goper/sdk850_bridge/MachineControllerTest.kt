package com.goper.sdk850_bridge

import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class MachineControllerTest {
    private val port = FakePort()
    private val scheduler = FakeScheduler()
    private val clock = FakeClock()
    private val controller = MachineController(port, scheduler, clock)
    private val events = mutableListOf<Map<String, Any?>>()

    @BeforeTest
    fun setUp() {
        controller.emitter = { events += it }
    }

    private fun initialize(logEnabled: Boolean? = null) =
        controller.initialize("sp", null, null, null, logEnabled)

    private fun connectedAndInitialized(logEnabled: Boolean? = null) {
        initialize(logEnabled)
        port.connected = true
        port.state = "CONNECTED"
        port.portPath = "/dev/ttyS2"
    }

    private fun codeOf(block: () -> Unit): String =
        assertFailsWith<BridgeException>(block = block).code

    // ---- initialize ----

    @Test
    fun initialize_usaOsValoresDoDemoERegistraOListener() {
        initialize()

        assertEquals(listOf<Any>(115200, 50L, 500L, false), port.configured)
        assertEquals(listOf("initDevice:sp", "configure", "register"), port.calls)
    }

    @Test
    fun initialize_aceitaValoresPersonalizadosEOLog() {
        controller.initialize("sp", 9600, 20L, 800L, true)

        assertEquals(listOf<Any>(9600, 20L, 800L, true), port.configured)
    }

    @Test
    fun initialize_chamadoDuasVezesInicializaODeviceManagerUmaSoVez() {
        initialize()
        initialize()

        assertEquals(1, port.deviceInitCount)
        assertEquals(2, port.calls.count { it == "configure" })
    }

    @Test
    fun initialize_rejeitaValoresInvalidos() {
        assertEquals(
            BridgeException.INVALID_ARGS,
            codeOf { controller.initialize("sp", 0, null, null, null) }
        )
        assertEquals(
            BridgeException.INVALID_ARGS,
            codeOf { controller.initialize("sp", null, -1L, null, null) }
        )
        assertEquals(
            BridgeException.INVALID_ARGS,
            codeOf { controller.initialize("sp", null, null, 0L, null) }
        )
        assertTrue(port.calls.isEmpty())
    }

    @Test
    fun initialize_comSerialConectadaVira_BUSY() {
        port.connected = true

        assertEquals(BridgeException.BUSY, codeOf { initialize() })
        assertTrue(port.calls.isEmpty())
    }

    // ---- pré-condições ----

    @Test
    fun antesDoInitialize_osMetodosViram_SDK_ERROR() {
        port.connected = true

        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.autoConnect() })
        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.connect("/dev/ttyS2") })
        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.reconnect() })
        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.startPolling(200) })
        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.queryDeviceInfo() })
        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.stop() })
    }

    @Test
    fun semConexao_polling_consultaEStopViram_NOT_CONNECTED() {
        initialize()

        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.startPolling(200) })
        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.queryDeviceInfo() })
        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.stop() })
        assertFalse(controller.isPolling)
    }

    @Test
    fun connectionInfo_funcionaAntesDoInitialize() {
        port.state = "IDLE"
        assertEquals(mapOf("state" to "IDLE", "portPath" to null), controller.connectionInfo())

        port.state = "CONNECTED"
        port.portPath = "/dev/ttyS8"
        assertEquals(mapOf("state" to "CONNECTED", "portPath" to "/dev/ttyS8"), controller.connectionInfo())
    }

    // ---- conexão ----

    @Test
    fun autoConnectEConnectDelegamAoSdk() {
        initialize()
        port.calls.clear()

        controller.autoConnect()
        assertTrue(controller.connect("/dev/ttyS8"))
        port.connectResult = false
        assertFalse(controller.connect("/dev/ttyS9"))
        controller.reconnect()

        assertEquals(
            listOf("autoConnect", "connect:/dev/ttyS8", "connect:/dev/ttyS9", "reConnect"),
            port.calls
        )
    }

    @Test
    fun disconnect_paraOPollingLimpaAFilaEDesconecta() {
        connectedAndInitialized()
        controller.startPolling(200)
        scheduler.advance(0)
        port.calls.clear()

        controller.disconnect()
        scheduler.advance(1000)

        assertEquals(listOf("markStop", "clearSendQueue", "disconnect"), port.calls)
        assertFalse(controller.isPolling)
    }

    @Test
    fun disconnect_antesDoInitializeNaoFazNada() {
        controller.disconnect()

        assertTrue(port.calls.isEmpty())
    }

    // ---- polling ----

    @Test
    fun polling_enviaOComandoDeControleAcadaCiclo() {
        connectedAndInitialized()
        controller.startPolling(200)

        scheduler.advance(0)
        assertEquals(1, port.controlSends)
        scheduler.advance(200)
        assertEquals(2, port.controlSends)
        scheduler.advance(400)
        assertEquals(4, port.controlSends)
        assertTrue(controller.isPolling)
    }

    @Test
    fun polling_sempreComecaEmSTOPAntesDoPrimeiroEnvio() {
        connectedAndInitialized()
        port.calls.clear()

        controller.startPolling(200)
        scheduler.advance(0)

        assertEquals(listOf("markStop", "send:0C"), port.calls)
    }

    @Test
    fun polling_puladoQuandoAFilaDoSdkEstaCheia() {
        connectedAndInitialized()
        port.pending = MachineController.MAX_PENDING_COMMANDS
        controller.startPolling(100)

        scheduler.advance(500)
        assertEquals(0, port.controlSends, "fila cheia: nenhum envio")

        port.pending = MachineController.MAX_PENDING_COMMANDS - 1
        scheduler.advance(100)
        assertEquals(1, port.controlSends)
    }

    @Test
    fun startPollingDeNovoMudaOIntervaloSemDuplicar() {
        connectedAndInitialized()
        controller.startPolling(200)
        scheduler.advance(0)
        controller.startPolling(50)
        port.sent.clear()

        scheduler.advance(200)

        assertEquals(5, port.controlSends)
    }

    @Test
    fun stopPolling_interrompeELimpaAFila() {
        connectedAndInitialized()
        controller.startPolling(100)
        scheduler.advance(250)
        val sent = port.controlSends
        port.calls.clear()

        controller.stopPolling()
        scheduler.advance(1000)

        assertEquals(sent, port.controlSends)
        assertEquals(listOf("markStop", "clearSendQueue"), port.calls)
        assertFalse(controller.isPolling)
    }

    @Test
    fun falhaNoEnvioDoPolling_emiteErroEPara() {
        connectedAndInitialized()
        port.failSend = RuntimeException("porta fechada")
        controller.startPolling(100)

        scheduler.advance(300)

        assertFalse(controller.isPolling)
        assertEquals(
            mapOf(
                "type" to "connection",
                "state" to "error",
                "portPath" to "/dev/ttyS2",
                "reason" to "Falha no polling: porta fechada"
            ),
            events.single()
        )
    }

    // ---- comandos diretos ----

    @Test
    fun queryDeviceInfo_enviaACosultaDoControlador() {
        connectedAndInitialized()
        port.calls.clear()

        controller.queryDeviceInfo()

        assertEquals(listOf("send:0D"), port.calls)
    }

    @Test
    fun stop_marcaSTOPEEnviaNaHoraSemEsperarOCiclo() {
        connectedAndInitialized()
        port.calls.clear()

        controller.stop()

        assertEquals(listOf("markStop", "send:0C"), port.calls)
        assertEquals(0, scheduler.pendingTasks, "não depende do polling")
    }

    // ---- eventos do SDK ----

    @Test
    fun onConnected_emiteConnection() {
        initialize()

        port.listener!!.onConnected("/dev/ttyS2")

        val expected: List<Map<String, Any?>> =
            listOf(mapOf("type" to "connection", "state" to "connected", "portPath" to "/dev/ttyS2"))
        assertEquals(expected, events.toList())
    }

    @Test
    fun onConnectFailed_emiteFailedEParaOPolling() {
        connectedAndInitialized()
        controller.startPolling(100)

        port.listener!!.onConnectFailed("/dev/ttyS2", "sem resposta")

        assertFalse(controller.isPolling)
        assertEquals("failed", events.single()["state"])
        assertEquals("sem resposta", events.single()["reason"])
    }

    @Test
    fun onDisconnected_emiteDisconnectedEParaOPolling() {
        connectedAndInitialized()
        controller.startPolling(100)

        port.listener!!.onDisconnected("/dev/ttyS2")

        assertFalse(controller.isPolling)
        assertEquals("disconnected", events.single()["state"])
    }

    @Test
    fun onError_emiteErrorComAPortaAtualEParaOPolling() {
        connectedAndInitialized()
        controller.startPolling(100)

        port.listener!!.onError("erro de leitura")

        assertFalse(controller.isPolling)
        assertEquals(
            mapOf(
                "type" to "connection",
                "state" to "error",
                "portPath" to "/dev/ttyS2",
                "reason" to "erro de leitura"
            ),
            events.single()
        )
    }

    @Test
    fun onStatus_emiteStatusComOsDoisRelogios() {
        initialize()
        clock.monotonic = 5_000
        clock.epoch = 1_750_000_005_000

        port.listener!!.onStatus(sampleStatus())

        val event = events.single()
        assertEquals("status", event["type"])
        assertEquals(5_000L, event["tsMonotonicMs"])
        assertEquals(1_750_000_005_000L, event["tsEpochMs"])
    }

    @Test
    fun onDeviceInfo_emiteDeviceInfo() {
        initialize()

        port.listener!!.onDeviceInfo(sampleInfo())

        assertEquals(Mappers.deviceInfo(sampleInfo()), events.single())
    }

    // ---- log (somente em debug) ----

    @Test
    fun log_naoEmiteNadaComLogDesligado() {
        initialize(logEnabled = false)

        port.listener!!.onSent(byteArrayOf(0x0C), true)
        port.listener!!.onPacket("CONTROL")

        assertTrue(events.isEmpty())
    }

    @Test
    fun log_emiteTxERxComLogLigado() {
        initialize(logEnabled = true)
        clock.epoch = 1_750_000_000_123

        port.listener!!.onSent(byteArrayOf(0x0C), true)
        port.listener!!.onPacket("CONTROL")

        assertEquals(
            listOf(
                Mappers.log("tx", "CONTROL", "0C", 1_750_000_000_123),
                Mappers.log("rx", "CONTROL", null, 1_750_000_000_123)
            ),
            events
        )
    }

    @Test
    fun log_sinalizaEnvioQueFalhou() {
        initialize(logEnabled = true)

        port.listener!!.onSent(byteArrayOf(0x0C), false)

        assertEquals("CONTROL (falha no envio)", events.single()["packetType"])
    }

    // ---- desligamento ----

    @Test
    fun shutdown_paraOPollingTiraOCallbackEDesconectaNessaOrdem() {
        connectedAndInitialized()
        controller.startPolling(100)
        scheduler.advance(0)
        port.calls.clear()

        controller.shutdown()
        scheduler.advance(1000)

        assertEquals(listOf("markStop", "clearSendQueue", "unregister", "disconnect"), port.calls)
        assertFalse(controller.isPolling)
        assertFalse(port.calls.contains("release"))
    }

    @Test
    fun shutdown_soltaOEmissorEExigeNovoInitialize() {
        connectedAndInitialized()
        controller.shutdown()
        val before = events.size

        assertNull(controller.emitter)
        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.autoConnect() })

        port.connected = false
        controller.emitter = { events += it }
        initialize()
        assertEquals(1, port.deviceInitCount, "o DeviceManager não é inicializado de novo")
        assertEquals(before, events.size)
    }
}
