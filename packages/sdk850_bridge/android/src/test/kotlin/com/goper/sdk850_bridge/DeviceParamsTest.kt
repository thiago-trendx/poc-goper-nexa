package com.goper.sdk850_bridge

import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** Faixas, leitura e envio de `DeviceParams` (Fase 3). */
internal class DeviceParamsTest {
    private val port = FakePort()
    private val scheduler = FakeScheduler()
    private val controller = MachineController(port, scheduler, FakeClock())
    private val plugin = Sdk850BridgePlugin { controller }
    private val events = mutableListOf<Map<String, Any?>>()

    @BeforeTest
    fun setUp() {
        controller.emitter = { events += it }
    }

    private fun initialize() = controller.initialize("sp", null, null, null, null)

    private fun connect() {
        initialize()
        port.connected = true
        port.portPath = "/dev/ttyS9"
    }

    private fun validArgs(): MutableMap<String, Any?> = defaultParams().toMap().toMutableMap()

    private fun codeOf(block: () -> Unit): String = assertFailsWith<BridgeException>(block = block).code

    private fun call(method: String, args: Map<String, Any?>? = null): MethodChannel.Result {
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall(method, args), result)
        return result
    }

    // ---- faixas ----

    @Test
    fun faixas_seguemOJavadocDoSdk() {
        val expected = mapOf(
            "minForce" to (5 to 20),
            "maxForce" to (50 to 150),
            "inactiveForce" to (2 to 20),
            "maxLength" to (10 to 255),
            "ratedSpeed" to (1 to 2000),
            "ropeGuideDiameter" to (1 to 255),
            "orginMinDistance" to (1 to 50),
            "orginMaxDistance" to (2 to 100),
            "velocityRange" to (0 to 50),
            "torqueVariationCycle" to (0 to 100),
            "torqueCoefficient" to (1 to 20)
        )
        assertEquals(expected, ParamRanges.all.associate { it.key to (it.min to it.max) })
    }

    @Test
    fun faixas_cobremExatamenteOsCamposDeParamsValues() {
        assertEquals(ParamRanges.keys, defaultParams().toMap().keys)
    }

    @Test
    fun valoresPadraoDoTesteEstaoDentroDasFaixas() {
        Args.deviceParams(validArgs()) // não lança
    }

    // ---- Args.deviceParams ----

    @Test
    fun args_aceitaOsLimitesInferiorESuperiorDeCadaCampo() {
        for (range in ParamRanges.all) {
            for (value in listOf(range.min, range.max)) {
                val args = validArgs().also { it[range.key] = value }
                assertEquals(value, Args.deviceParams(args).toMap()[range.key], range.key)
            }
        }
    }

    @Test
    fun args_umPassoForaDaFaixaViraOUT_OF_RANGEComOCampoNosDetalhes() {
        for (range in ParamRanges.all) {
            for (value in listOf(range.min - 1, range.max + 1)) {
                val args = validArgs().also { it[range.key] = value }
                val error = assertFailsWith<BridgeException> { Args.deviceParams(args) }
                assertEquals(BridgeException.OUT_OF_RANGE, error.code, "${range.key}=$value")
                assertEquals(listOf(range.key), error.details, range.key)
            }
        }
    }

    @Test
    fun args_listaTodosOsCamposForaDaFaixa() {
        val args = validArgs().also {
            it["minForce"] = 99
            it["ratedSpeed"] = 0
        }

        val error = assertFailsWith<BridgeException> { Args.deviceParams(args) }

        assertEquals(listOf("minForce", "ratedSpeed"), error.details)
        assertTrue(error.message!!.contains("minForce (5 a 20)"))
        assertTrue(error.message!!.contains("ratedSpeed (1 a 2000)"))
    }

    @Test
    fun args_campoAusenteOuComTipoErradoViraINVALID_ARGS() {
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.deviceParams(null) })
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.deviceParams(validArgs().also { it.remove("maxLength") }) })
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.deviceParams(validArgs().also { it["maxLength"] = "200" }) })
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.deviceParams(validArgs().also { it["maxLength"] = null }) })
    }

    @Test
    fun args_aceitaLongComoOCanalPodeEntregar() {
        val args = validArgs().also { it["maxLength"] = 200L }

        assertEquals(200, Args.deviceParams(args).maxLength)
    }

    // ---- Mappers ----

    @Test
    fun mappers_paramsAckTrazOTypeEOsOnzeCampos() {
        val map = Mappers.paramsAck(defaultParams())

        assertEquals("paramsAck", map["type"])
        assertEquals(ParamRanges.keys + "type", map.keys)
        assertEquals(100, map["maxForce"])
    }

    // ---- MachineController ----

    @Test
    fun leitura_antesDoInitializeViraSDK_ERROR() {
        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.deviceParams() })
    }

    @Test
    fun leitura_devolveOCacheLocalSemPrecisarDeConexao() {
        initialize()
        port.params = defaultParams().copy(minForce = 12)
        port.calls.clear()

        val map = controller.deviceParams()

        assertEquals(12, map["minForce"])
        assertEquals(ParamRanges.keys, map.keys)
        assertTrue(port.calls.isEmpty(), "ler não envia nada ao controlador")
    }

    @Test
    fun envio_semConexaoViraNOT_CONNECTED() {
        initialize()

        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.sendDeviceParams(defaultParams()) })
        assertTrue(port.applied.isEmpty())
    }

    @Test
    fun envio_gravaNoCacheEEnfileiraOCommandoUmaUnicaVez() {
        connect()
        port.calls.clear()
        val values = defaultParams().copy(minForce = 10, maxForce = 90)

        controller.sendDeviceParams(values)

        assertEquals(listOf(values), port.applied)
        assertEquals(listOf("applyParams", "send:0A"), port.calls)
    }

    @Test
    fun paramsAck_viraEventoComOsValoresDevolvidos() {
        initialize()

        port.listener!!.onParamsAck(defaultParams().copy(minForce = 8))

        val event = events.single()
        assertEquals("paramsAck", event["type"])
        assertEquals(8, event["minForce"])
    }

    @Test
    fun conectarEIniciarOPolling_nuncaEnviaParametros() {
        initialize()
        port.connected = true
        port.listener!!.onConnected("/dev/ttyS9")
        controller.startPolling(200)
        scheduler.advance(1000)
        controller.queryDeviceInfo()

        assertTrue(port.applied.isEmpty(), "DeviceParams só sai por ação explícita")
        assertTrue(port.sent.none { it.contentEquals(port.paramsBytes) })
    }

    // ---- plugin ----

    @Test
    fun plugin_getDeviceParamsDevolveOMapa() {
        initialize()

        Mockito.verify(call("getDeviceParams")).success(defaultParams().toMap())
    }

    @Test
    fun plugin_sendDeviceParamsEnviaEResponde() {
        connect()

        Mockito.verify(call("sendDeviceParams", validArgs())).success(null)
        assertEquals(listOf(defaultParams()), port.applied)
    }

    @Test
    fun plugin_sendDeviceParamsForaDaFaixaViraOUT_OF_RANGEENaoAplicaNada() {
        connect()
        val args = validArgs().also { it["minForce"] = 99 }

        Mockito.verify(call("sendDeviceParams", args)).error(eq(BridgeException.OUT_OF_RANGE), any(), eq(listOf("minForce")))
        assertTrue(port.applied.isEmpty())
    }

    @Test
    fun plugin_sendDeviceParamsComCampoAusenteViraINVALID_ARGS() {
        connect()
        val args = validArgs().also { it.remove("torqueCoefficient") }

        Mockito.verify(call("sendDeviceParams", args)).error(eq(BridgeException.INVALID_ARGS), any(), any())
        assertTrue(port.applied.isEmpty())
    }

    @Test
    fun plugin_sendDeviceParamsSemConexaoViraNOT_CONNECTED() {
        initialize()

        Mockito.verify(call("sendDeviceParams", validArgs())).error(eq(BridgeException.NOT_CONNECTED), any(), any())
    }
}
