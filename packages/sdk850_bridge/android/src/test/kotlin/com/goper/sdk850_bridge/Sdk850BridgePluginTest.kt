package com.goper.sdk850_bridge

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

internal class Sdk850BridgePluginTest {
    private val port = FakePort()
    private val scheduler = FakeScheduler()
    private val controller = MachineController(port, scheduler, FakeClock())
    private val plugin = Sdk850BridgePlugin { controller }

    private fun call(method: String, args: Map<String, Any?>? = null): MethodChannel.Result {
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall(method, args), result)
        return result
    }

    private fun initializeController() = controller.initialize("sp", null, null, null, null)

    private fun connect() {
        initializeController()
        port.connected = true
    }

    @Test
    fun metodoDesconhecido_respondeNotImplemented() {
        Mockito.verify(call("start")).notImplemented()
        Mockito.verify(call("setForce", mapOf("kg" to 10))).notImplemented()
    }

    @Test
    fun initialize_repassaOsArgumentosAoControlador() {
        val result = call(
            "initialize",
            mapOf("spFileName" to "sp", "baudRate" to 9600, "sendIntervalMs" to 20, "testTimeMs" to 800, "logEnabled" to true)
        )

        Mockito.verify(result).success(null)
        assertEquals(listOf<Any>(9600, 20L, 800L, true), port.configured)
    }

    @Test
    fun initialize_semNomeDoArquivoViraINVALID_ARGS() {
        Mockito.verify(call("initialize", mapOf("baudRate" to 9600)))
            .error(eq(BridgeException.INVALID_ARGS), any(), any())
    }

    @Test
    fun argumentoAusente_viraINVALID_ARGS() {
        initializeController()

        Mockito.verify(call("connect", emptyMap())).error(eq(BridgeException.INVALID_ARGS), any(), any())
    }

    @Test
    fun semInitialize_viraSDK_ERRORComAMensagemDoControlador() {
        val result = call("startPolling", mapOf("intervalMs" to 200))

        Mockito.verify(result).error(BridgeException.SDK_ERROR, "initialize ainda não foi chamado", null)
    }

    @Test
    fun semConexao_viraNOT_CONNECTED() {
        initializeController()

        Mockito.verify(call("startPolling")).error(eq(BridgeException.NOT_CONNECTED), any(), any())
        Mockito.verify(call("queryDeviceInfo")).error(eq(BridgeException.NOT_CONNECTED), any(), any())
        Mockito.verify(call("stop")).error(eq(BridgeException.NOT_CONNECTED), any(), any())
    }

    @Test
    fun intervaloForaDaFaixa_viraOUT_OF_RANGEENaoIniciaOPolling() {
        connect()

        val result = call("startPolling", mapOf("intervalMs" to 5))

        Mockito.verify(result).error(eq(BridgeException.OUT_OF_RANGE), any(), any())
        assertTrue(!controller.isPolling)
    }

    @Test
    fun startPolling_semArgumentoUsa200ms() {
        connect()

        Mockito.verify(call("startPolling")).success(null)
        scheduler.advance(0)
        scheduler.advance(200)

        assertEquals(2, port.controlSends)
    }

    @Test
    fun stopPolling_respondeSucesso() {
        connect()
        call("startPolling")

        Mockito.verify(call("stopPolling")).success(null)
        assertTrue(!controller.isPolling)
    }

    @Test
    fun connect_devolveOBooleanDoSdk() {
        initializeController()
        port.connectResult = true

        Mockito.verify(call("connect", mapOf("portPath" to "/dev/ttyS2"))).success(true)
        assertTrue(port.calls.contains("connect:/dev/ttyS2"))
    }

    @Test
    fun getConnectionInfo_devolveEstadoEPorta() {
        port.state = "CONNECTED"
        port.portPath = "/dev/ttyS8"

        Mockito.verify(call("getConnectionInfo"))
            .success(mapOf("state" to "CONNECTED", "portPath" to "/dev/ttyS8"))
    }

    @Test
    fun stop_enviaNaHora() {
        connect()
        port.calls.clear()

        Mockito.verify(call("stop")).success(null)
        assertEquals(listOf("markStop", "send:0C"), port.calls)
    }

    @Test
    fun excecaoInesperada_viraSDK_ERRORComAMensagem() {
        connect()
        port.failSend = RuntimeException("porta fechada")

        Mockito.verify(call("stop")).error(BridgeException.SDK_ERROR, "porta fechada", null)
    }

    @Test
    fun autoConnectEDisconnect_respondemSucesso() {
        initializeController()

        Mockito.verify(call("autoConnect")).success(null)
        Mockito.verify(call("disconnect")).success(null)
        Mockito.verify(call("reconnect")).success(null)
    }
}
