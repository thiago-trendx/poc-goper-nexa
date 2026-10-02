package com.goper.sdk850_bridge

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/** Comandos de controle (Fase 4): faixas, limite de força, início seguro e rotas do canal. */
internal class ControlTest {
    private val port = FakePort()
    private val scheduler = FakeScheduler()
    private val controller = MachineController(port, scheduler, FakeClock())
    private val plugin = Sdk850BridgePlugin { controller }

    @BeforeTest
    fun setUp() {
        // Calibração do FakePort: minForce 5, maxForce 100, velocityRange 20, maxLength 200.
        controller.emitter = {}
    }

    private fun initialize(maxForceKg: Int? = null) =
        controller.initialize("sp", null, null, null, null, maxForceKg)

    private fun connect(maxForceKg: Int? = null) {
        initialize(maxForceKg)
        port.connected = true
        port.portPath = "/dev/ttyS9"
    }

    private fun connectWithPolling(maxForceKg: Int? = null) {
        connect(maxForceKg)
        controller.startPolling(200)
        scheduler.advance(0)
    }

    private fun codeOf(block: () -> Unit): String = assertFailsWith<BridgeException>(block = block).code

    private fun call(method: String, args: Map<String, Any?>? = null): MethodChannel.Result {
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(MethodCall(method, args), result)
        return result
    }

    // ---- Args ----

    @Test
    fun args_modoAceitaOsCincoEnumsDoSdk() {
        for (mode in listOf("STANDARD", "CENTRIPETAL", "CENTRIFUGAL", "VELOCITY", "ELASTIC")) {
            assertEquals(mode, Args.forceMode(mapOf("mode" to mode)))
        }
    }

    @Test
    fun args_modoInvalidoViraINVALID_ARGS() {
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.forceMode(mapOf("mode" to "standard")) })
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.forceMode(mapOf("mode" to 3)) })
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.forceMode(null) })
    }

    @Test
    fun args_tipoDeCoeficienteEsafeMode() {
        for (kind in listOf("centripetal", "centrifugal", "velocity", "elastic")) {
            assertEquals(kind, Args.coefficientKind(mapOf("kind" to kind)))
        }
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.coefficientKind(mapOf("kind" to "torque")) })
        for (value in listOf(0, 51, 53)) assertEquals(value, Args.safeMode(mapOf("value" to value)))
        for (value in listOf(1, 50, 52, 54, -1)) {
            assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.safeMode(mapOf("value" to value)) }, "$value")
        }
    }

    @Test
    fun args_requiredIntExigeNumero() {
        assertEquals(7, Args.requiredInt(mapOf("kg" to 7L), "kg"))
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.requiredInt(mapOf("kg" to "7"), "kg") })
        assertEquals(BridgeException.INVALID_ARGS, codeOf { Args.requiredInt(null, "kg") })
    }

    // ---- leitura ----

    @Test
    fun leitura_exigeInitializeMasNaoConexaoENaoEnviaNada() {
        assertEquals(BridgeException.SDK_ERROR, codeOf { controller.controlParams() })
        initialize()
        port.control = defaultControl().copy(force = 12, mode = "VELOCITY")
        port.calls.clear()

        val map = controller.controlParams()

        assertEquals(12, map["force"])
        assertEquals("VELOCITY", map["mode"])
        assertEquals(
            setOf(
                "run", "mode", "force", "centripetal", "centrifugal", "velocity", "elastic", "safeMode",
                "clearMode", "motorPosition1", "motorPosition2", "motorSelfCheck", "balancingForce",
                "maxElectric", "needSetOrigin", "needErrorRestor"
            ),
            map.keys
        )
        assertTrue(port.calls.isEmpty())
    }

    // ---- precondições ----

    @Test
    fun comandosSemConexaoViramNOT_CONNECTED() {
        initialize()

        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.start() })
        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.setForce(10) })
        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.setMode("STANDARD") })
        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.setCoefficient("elastic", 1) })
        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.setElasticMax(50) })
        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.setSafeMode(0) })
        assertEquals(BridgeException.NOT_CONNECTED, codeOf { controller.setBalancingForce(1) })
        assertTrue(port.calls.none { it.startsWith("set") }, "nada foi aplicado aos ControlParams")
    }

    // ---- força ----

    @Test
    fun forca_aceitaDeMinForceAteMaxForceDaCalibracao() {
        connect()

        controller.setForce(5)
        controller.setForce(100)

        assertEquals(100, port.control.force)
    }

    @Test
    fun forca_foraDaCalibracaoViraOUT_OF_RANGEENaoAplica() {
        connect()

        for (kg in listOf(0, 4, 101, 500, -1)) {
            val error = assertFailsWith<BridgeException> { controller.setForce(kg) }
            assertEquals(BridgeException.OUT_OF_RANGE, error.code, "$kg")
            assertTrue(error.message!!.contains("entre 5 e 100 kg"), error.message)
        }
        assertEquals(0, port.control.force, "o valor anterior ficou intacto")
    }

    @Test
    fun forca_oLimiteDeSegurancaDoAppValeAlemDaCalibracao() {
        connect(maxForceKg = 30)

        controller.setForce(30)
        val error = assertFailsWith<BridgeException> { controller.setForce(31) }

        assertEquals(BridgeException.OUT_OF_RANGE, error.code)
        assertTrue(error.message!!.contains("limite de segurança do app: 30 kg"), error.message)
        assertEquals(30, port.control.force)
    }

    @Test
    fun forca_limiteMaiorQueAMaxForceNaoAmplia() {
        connect(maxForceKg = 500)

        assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.setForce(101) })
    }

    @Test
    fun forca_limiteAbaixoDaForcaMinimaRecusaTudoComMensagemClara() {
        connect(maxForceKg = 3)

        val error = assertFailsWith<BridgeException> { controller.setForce(5) }

        assertEquals(BridgeException.OUT_OF_RANGE, error.code)
        assertTrue(error.message!!.contains("abaixo da força mínima"), error.message)
    }

    @Test
    fun forca_limiteInvalidoNoInitializeViraINVALID_ARGS() {
        assertEquals(BridgeException.INVALID_ARGS, codeOf { initialize(maxForceKg = 0) })
        assertEquals(BridgeException.INVALID_ARGS, codeOf { initialize(maxForceKg = -5) })
        assertTrue(port.calls.isEmpty())
    }

    // ---- início seguro ----

    @Test
    fun start_semPollingViraSDK_ERRORComOMotivo() {
        connect()
        controller.setForce(10)

        val error = assertFailsWith<BridgeException> { controller.start() }

        assertEquals(BridgeException.SDK_ERROR, error.code)
        assertTrue(error.message!!.contains("Ligue o polling"), error.message)
        assertEquals("STOP", port.control.run)
    }

    @Test
    fun start_comAForcaPadraoDoSdkForaDaFaixaViraOUT_OF_RANGE() {
        connectWithPolling()
        // força 0 = valor padrão desconhecido: o app tem que defini-la antes
        port.control = defaultControl().copy(force = 0)

        val error = assertFailsWith<BridgeException> { controller.start() }

        assertEquals(BridgeException.OUT_OF_RANGE, error.code)
        assertTrue(error.message!!.contains("Defina a força antes de iniciar"), error.message)
        assertEquals("STOP", port.control.run)
    }

    @Test
    fun start_comForcaAcimaDoLimiteDeSegurancaViraOUT_OF_RANGE() {
        connectWithPolling(maxForceKg = 30)
        port.control = port.control.copy(force = 50) // o SDK ainda guarda um valor antigo/padrão

        val error = assertFailsWith<BridgeException> { controller.start() }

        assertEquals(BridgeException.OUT_OF_RANGE, error.code)
        assertEquals("STOP", port.control.run)
    }

    @Test
    fun start_comForcaValidaMarcaRUNNINGSemEnviarNaHoraEOPollingLevaNoProximoCiclo() {
        connectWithPolling(maxForceKg = 30)
        controller.setForce(10)
        port.sent.clear()
        port.calls.clear()

        controller.start()

        assertEquals("RUNNING", port.control.run)
        assertEquals(listOf("setRunning:true"), port.calls, "não há envio imediato")
        scheduler.advance(200)
        assertEquals(1, port.controlSends, "o próximo ciclo do polling leva o comando")
    }

    @Test
    fun voltarAoSTOP_pararOPollingDesconectarOuPerderAConexaoDesfazORunning() {
        for (action in listOf<(MachineController, FakePort) -> Unit>(
            { c, _ -> c.stopPolling() },
            { c, _ -> c.disconnect() },
            { _, p -> p.listener!!.onDisconnected("/dev/ttyS9") },
            { _, p -> p.listener!!.onError("cabo solto") },
            { _, p -> p.listener!!.onConnectFailed("/dev/ttyS9", "sem resposta") },
            { c, _ -> c.shutdown() }
        )) {
            val localPort = FakePort()
            val localController = MachineController(localPort, FakeScheduler(), FakeClock())
            localController.initialize("sp", null, null, null, null)
            localPort.connected = true
            localController.startPolling(200)
            localController.setForce(10)
            localController.start()
            assertEquals("RUNNING", localPort.control.run)

            action(localController, localPort)

            assertEquals("STOP", localPort.control.run)
        }
    }

    @Test
    fun startPolling_depoisDeParadoSempreVoltaAoSTOP() {
        connectWithPolling()
        controller.setForce(10)
        controller.start()

        controller.startPolling(100)

        assertEquals("STOP", port.control.run)
    }

    @Test
    fun stop_continuaEnviandoNaHoraComAMaquinaRodando() {
        connectWithPolling()
        controller.setForce(10)
        controller.start()
        port.calls.clear()

        controller.stop()

        assertEquals("STOP", port.control.run)
        assertEquals(listOf("markStop", "send:0C"), port.calls)
    }

    // ---- modo, coeficientes, elástico, proteção e compensação ----

    @Test
    fun modo_eAplicado() {
        connect()

        controller.setMode("ELASTIC")

        assertEquals("ELASTIC", port.control.mode)
    }

    @Test
    fun coeficientes_respeitamAsFaixasDoDemoEDaCalibracao() {
        connect()
        val limits = mapOf("centripetal" to 6, "centrifugal" to 6, "elastic" to 10, "velocity" to 20)

        for ((kind, max) in limits) {
            controller.setCoefficient(kind, 0)
            controller.setCoefficient(kind, max)
            assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.setCoefficient(kind, max + 1) }, "$kind acima")
            assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.setCoefficient(kind, -1) }, "$kind abaixo")
        }
    }

    @Test
    fun coeficienteIsocinetico_usaOVelocityRangeDaCalibracao() {
        connect()
        port.params = port.params.copy(velocityRange = 8)

        controller.setCoefficient("velocity", 8)

        assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.setCoefficient("velocity", 9) })
        assertEquals(8, port.control.velocity)
    }

    @Test
    fun coeficientes_vaoParaOCampoCerto() {
        connect()

        controller.setCoefficient("centripetal", 1)
        controller.setCoefficient("centrifugal", 2)
        controller.setCoefficient("velocity", 3)
        controller.setCoefficient("elastic", 4)

        assertEquals(listOf(1, 2, 3, 4), with(port.control) { listOf(centripetal, centrifugal, velocity, elastic) })
    }

    @Test
    fun cursoElastico_vaiDe1AteOComprimentoMaximoDoCabo() {
        connect()

        controller.setElasticMax(1)
        controller.setElasticMax(200)

        assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.setElasticMax(0) })
        assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.setElasticMax(201) })
        assertEquals(200, port.control.maxElectric)
    }

    @Test
    fun compensacao_vaiDe0a25() {
        connect()

        controller.setBalancingForce(0)
        controller.setBalancingForce(25)

        assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.setBalancingForce(26) })
        assertEquals(BridgeException.OUT_OF_RANGE, codeOf { controller.setBalancingForce(-1) })
        assertEquals(25, port.control.balancingForce)
    }

    @Test
    fun protecao_eAplicada() {
        connect()

        controller.setSafeMode(51)

        assertEquals(51, port.control.safeMode)
    }

    // ---- plugin ----

    @Test
    fun plugin_getControlParamsDevolveOMapa() {
        initialize()

        Mockito.verify(call("getControlParams")).success(defaultControl().toMap())
    }

    @Test
    fun plugin_comandosFelizesRespondemSucessoEAplicam() {
        connectWithPolling()

        Mockito.verify(call("setForce", mapOf("kg" to 12))).success(null)
        Mockito.verify(call("setMode", mapOf("mode" to "CENTRIFUGAL"))).success(null)
        Mockito.verify(call("setCoefficient", mapOf("kind" to "centrifugal", "value" to 3))).success(null)
        Mockito.verify(call("setElasticMax", mapOf("value" to 60))).success(null)
        Mockito.verify(call("setSafeMode", mapOf("value" to 53))).success(null)
        Mockito.verify(call("setBalancingForce", mapOf("kg" to 7))).success(null)
        Mockito.verify(call("start")).success(null)

        val control = port.control
        assertEquals(listOf("RUNNING", "CENTRIFUGAL", 12, 3, 60, 53, 7),
            listOf(control.run, control.mode, control.force, control.centrifugal, control.maxElectric, control.safeMode, control.balancingForce))
    }

    @Test
    fun plugin_errosDeValidacaoViramOCodigoCerto() {
        connect()

        Mockito.verify(call("setForce", mapOf("kg" to 500))).error(eq(BridgeException.OUT_OF_RANGE), any(), any())
        Mockito.verify(call("setForce", mapOf("kg" to "dez"))).error(eq(BridgeException.INVALID_ARGS), any(), any())
        Mockito.verify(call("setMode", mapOf("mode" to "TURBO"))).error(eq(BridgeException.INVALID_ARGS), any(), any())
        Mockito.verify(call("setCoefficient", mapOf("kind" to "x", "value" to 1))).error(eq(BridgeException.INVALID_ARGS), any(), any())
        Mockito.verify(call("setCoefficient", mapOf("kind" to "elastic", "value" to 11))).error(eq(BridgeException.OUT_OF_RANGE), any(), any())
        Mockito.verify(call("setSafeMode", mapOf("value" to 7))).error(eq(BridgeException.INVALID_ARGS), any(), any())
        Mockito.verify(call("setBalancingForce", mapOf("kg" to 30))).error(eq(BridgeException.OUT_OF_RANGE), any(), any())
        assertTrue(port.calls.none { it.startsWith("set") })
    }

    @Test
    fun plugin_startSemForcaValidaERecusado() {
        connectWithPolling()

        Mockito.verify(call("start")).error(eq(BridgeException.OUT_OF_RANGE), any(), any())
        assertEquals("STOP", port.control.run)
    }

    @Test
    fun plugin_initializeRepassaOLimiteDeForca() {
        Mockito.verify(
            call("initialize", mapOf("spFileName" to "sp", "maxForceKg" to 30))
        ).success(null)
        port.connected = true

        Mockito.verify(call("setForce", mapOf("kg" to 31))).error(eq(BridgeException.OUT_OF_RANGE), any(), any())
    }
}
