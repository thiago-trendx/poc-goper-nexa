package com.goper.sdk850_bridge

import com.sunway.sdk850.port.bean.DeviceInfo
import com.sunway.sdk850.port.bean.DeviceStatus

/**
 * Coordena conexão, polling e eventos da máquina 850. Uma instância por processo
 * ([shared]): o `DeviceManager` só pode ser inicializado uma vez.
 *
 * Tudo roda na thread principal (chamadas do canal e callbacks do SDK); nada aqui é
 * sincronizado de propósito.
 */
class MachineController(
    private val port: SdkPort,
    scheduler: Scheduler,
    private val clock: Clock = SystemClockSource,
    private val liftAdjustTimeoutSec: Int = LIFT_ADJUST_TIMEOUT_SEC
) : PortListener {

    /** Destino dos eventos (o `EventSink` do canal). Nulo enquanto ninguém escuta. */
    var emitter: ((Map<String, Any?>) -> Unit)? = null

    private var deviceInitialized = false
    private var configured = false
    private var logEnabled = false

    /** Limite de força informado pelo app em `initialize`; nulo = só a calibração limita. */
    private var safetyMaxForceKg: Int? = null

    private val loop = PollingLoop(scheduler, onTickError = ::onPollingError) { pollOnce() }

    val isPolling: Boolean
        get() = loop.isRunning

    private val lift = LiftMotorGuard(scheduler, ::onLiftPhase)

    /** Operação que a [lift] está acompanhando; só tem valor enquanto ela está ativa. */
    private var liftKind: LiftKind? = null

    private enum class LiftKind { ADJUST, SELF_CHECK }

    // ---- Inicialização e conexão ----

    fun initialize(
        spFileName: String,
        baudRate: Int?,
        sendIntervalMs: Long?,
        testTimeMs: Long?,
        logEnabled: Boolean?,
        maxForceKg: Int? = null
    ) {
        if ((baudRate ?: Args.DEFAULT_BAUD_RATE) <= 0) {
            throw BridgeException(BridgeException.INVALID_ARGS, "baudRate deve ser > 0")
        }
        if ((sendIntervalMs ?: Args.DEFAULT_SEND_INTERVAL_MS) < 0) {
            throw BridgeException(BridgeException.INVALID_ARGS, "sendIntervalMs deve ser >= 0")
        }
        if ((testTimeMs ?: Args.DEFAULT_TEST_TIME_MS) <= 0) {
            throw BridgeException(BridgeException.INVALID_ARGS, "testTimeMs deve ser > 0")
        }
        if (maxForceKg != null && maxForceKg <= 0) {
            throw BridgeException(BridgeException.INVALID_ARGS, "maxForceKg deve ser > 0")
        }
        if (port.isConnected()) {
            throw BridgeException(BridgeException.BUSY, "Desconecte antes de reconfigurar a serial")
        }

        if (!deviceInitialized) {
            port.initDevice(spFileName)
            deviceInitialized = true
        }
        this.logEnabled = logEnabled ?: false
        this.safetyMaxForceKg = maxForceKg
        port.configure(
            baudRate = baudRate ?: Args.DEFAULT_BAUD_RATE,
            sendIntervalMs = sendIntervalMs ?: Args.DEFAULT_SEND_INTERVAL_MS,
            testTimeMs = testTimeMs ?: Args.DEFAULT_TEST_TIME_MS,
            logEnabled = this.logEnabled
        )
        port.register(this)
        configured = true
    }

    /** Varre as portas; o resultado chega por evento `connection`. */
    fun autoConnect() {
        requireInitialized()
        port.autoConnect()
    }

    /** O resultado final chega por evento `connection`. */
    fun connect(portPath: String): Boolean {
        requireInitialized()
        return port.connect(portPath)
    }

    fun disconnect() {
        if (!configured) return
        loop.stop()
        port.clearSendQueue()
        haltPolling()
        port.disconnect()
    }

    fun reconnect() {
        requireInitialized()
        port.reConnect()
    }

    fun connectionInfo(): Map<String, Any?> = Mappers.connectionInfo(port.stateName(), port.currentPortPath())

    // ---- Parâmetros do dispositivo ----

    /**
     * Parâmetros guardados no `DeviceManager` (cache local). O controlador não tem comando de
     * leitura: ele só devolve seus parâmetros em resposta a um envio (evento `paramsAck`).
     */
    fun deviceParams(): Map<String, Any?> {
        requireInitialized()
        return port.deviceParams().toMap()
    }

    /**
     * Envia [values] ao controlador. Só por ação explícita: nada aqui envia parâmetros ao
     * conectar. A confirmação chega pelo evento `paramsAck`.
     */
    fun sendDeviceParams(values: ParamsValues) {
        requireConnected()
        port.send(port.paramsCommand(values))
    }

    // ---- Polling e comandos ----

    /**
     * Liga o polling. O valor padrão de `ControlParams.run` do SDK não é documentado, então o
     * polling sempre começa em `STOP` (motor em força base) para o primeiro envio nunca mandar
     * a máquina se mexer; quem quiser movimento usa `start` depois.
     */
    fun startPolling(intervalMs: Int) {
        requireConnected()
        port.markStop()
        disarmOneShot()
        port.setMotorSelfCheck(false)
        loop.start(intervalMs.toLong())
    }

    fun stopPolling() {
        loop.stop()
        if (configured) port.clearSendQueue()
        haltPolling()
    }

    fun queryDeviceInfo() {
        requireConnected()
        port.send(port.deviceInfoQuery())
    }

    /**
     * STOP imediato: coloca `run = STOP` e envia o comando na hora, sem esperar o próximo
     * ciclo do polling.
     */
    fun stop() {
        requireConnected()
        port.markStop()
        port.send(port.controlCommand())
    }

    /**
     * Encerra o uso da serial: para o polling, tira o callback e desconecta, nessa ordem.
     * `release()` do SDK fica para o desligamento do processo e nunca é chamado aqui.
     */
    fun shutdown() {
        emitter = null // o canal já foi cancelado: a limpeza abaixo não publica eventos
        loop.stop()
        runCatching { port.clearSendQueue() }
        runCatching { haltPolling() }
        runCatching { port.unregister() }
        runCatching { port.disconnect() }
        configured = false
    }

    // ---- Controle (Fase 4) ----

    /**
     * `ControlParams` atuais, os mesmos que o polling reenvia a cada ciclo. Leitura local: não
     * envia nada ao controlador nem exige conexão.
     */
    fun controlParams(): Map<String, Any?> {
        requireInitialized()
        return Mappers.controlParams(port.controlValues())
    }

    /**
     * Inicia o movimento. O polling precisa estar ligado (sem ele a máquina não recebe as ordens
     * seguintes, inclusive o STOP) e a força atual dos `ControlParams` precisa estar dentro da
     * faixa permitida: o valor padrão do SDK não é conhecido, então o app define a força antes.
     * O `run = RUNNING` vai no próximo ciclo do polling.
     */
    fun start() {
        requireConnected()
        requireLiftIdle("iniciar")
        if (!loop.isRunning) {
            throw BridgeException(
                BridgeException.SDK_ERROR,
                "Ligue o polling antes de iniciar: sem ele a máquina não recebe as ordens seguintes, inclusive o STOP"
            )
        }
        val force = port.controlValues().force
        forceProblem(force)?.let {
            throw BridgeException(
                BridgeException.OUT_OF_RANGE,
                "A força atual ($force kg) não é válida: $it. Defina a força antes de iniciar"
            )
        }
        port.setRunning(true)
    }

    fun setForce(kg: Int) {
        requireConnected()
        forceProblem(kg)?.let { throw BridgeException(BridgeException.OUT_OF_RANGE, it) }
        port.setForce(kg)
    }

    /** [mode] já validado por [Args.forceMode]. */
    fun setMode(mode: String) {
        requireConnected()
        port.setMode(mode)
    }

    /** [kind] já validado por [Args.coefficientKind]. */
    fun setCoefficient(kind: String, value: Int) {
        requireConnected()
        val max = when (kind) {
            "centripetal" -> ControlLimits.CENTRIPETAL_MAX
            "centrifugal" -> ControlLimits.CENTRIFUGAL_MAX
            "elastic" -> ControlLimits.ELASTIC_MAX
            else -> port.deviceParams().velocityRange // velocity: de 0 até o velocityRange da calibração
        }
        if (value !in 0..max) {
            throw BridgeException(BridgeException.OUT_OF_RANGE, "Coeficiente $kind deve estar entre 0 e $max")
        }
        port.setCoefficient(kind, value)
    }

    /** Curso elástico máximo: de 1 até o comprimento máximo do cabo da calibração. */
    fun setElasticMax(value: Int) {
        requireConnected()
        val max = port.deviceParams().maxLength
        if (value !in 1..max) {
            throw BridgeException(BridgeException.OUT_OF_RANGE, "O curso elástico deve estar entre 1 e $max")
        }
        port.setElasticMax(value)
    }

    /** [value] já validado por [Args.safeMode] (0, 51 ou 53). */
    fun setSafeMode(value: Int) {
        requireConnected()
        port.setSafeMode(value)
    }

    fun setBalancingForce(kg: Int) {
        requireConnected()
        if (kg !in 0..ControlLimits.BALANCING_FORCE_MAX) {
            throw BridgeException(
                BridgeException.OUT_OF_RANGE,
                "A força de compensação deve estar entre 0 e ${ControlLimits.BALANCING_FORCE_MAX} kg"
            )
        }
        port.setBalancingForce(kg)
    }

    /**
     * Faixa de força permitida: de `minForce` a `maxForce` da calibração (como o demo do fabricante),
     * e nunca acima do limite de segurança do app, se informado. Devolve a mensagem de problema,
     * ou `null` se [kg] é válido.
     */
    private fun forceProblem(kg: Int): String? {
        val params = port.deviceParams()
        val cap = safetyMaxForceKg
        val max = if (cap == null) params.maxForce else minOf(params.maxForce, cap)
        if (max < params.minForce) {
            return "o limite de segurança do app ($cap kg) está abaixo da força mínima da calibração (${params.minForce} kg)"
        }
        if (kg !in params.minForce..max) {
            return "a força deve estar entre ${params.minForce} e $max kg" +
                if (cap != null && cap < params.maxForce) " (limite de segurança do app: $cap kg)" else ""
        }
        return null
    }

    // ---- Disparo único e motores de elevação (Fase 5) ----

    /**
     * Redefine a origem (`needSetOrigin` + `ClearMode.ALL`, como o demo). Disparo único: o comando
     * é enviado uma vez e os flags são desligados em seguida, para o polling não repeti-lo.
     * Só com a máquina parada.
     */
    fun originReset() {
        requireConnected()
        requireLiftIdle("redefinir a origem")
        requireStopped("redefinir a origem")
        sendOneShot {
            port.setNeedSetOrigin(true)
            port.setClearMode("ALL")
        }
    }

    /**
     * Restaura erros (`needErrorRestor` + `run = ERROR_RESTORE`, como o demo). Disparo único; ao
     * terminar o estado local volta a `STOP`. Só com a máquina parada.
     */
    fun errorRestore() {
        requireConnected()
        requireLiftIdle("restaurar erros")
        requireStopped("restaurar erros")
        try {
            sendOneShot {
                port.setNeedErrorRestore(true)
                port.setRunErrorRestore()
            }
        } finally {
            port.markStop()
        }
    }

    /**
     * Zera as contagens de [mode] (`FIRST`, `SECOND`, `ALL` ou `NONE`; já validado por
     * [Args.clearMode]). O guia avisa que esse comando não pode ser enviado continuamente: vai
     * uma vez só. `NONE` não faz nada.
     */
    fun clearData(mode: String) {
        requireConnected()
        requireLiftIdle("limpar dados")
        if (mode == "NONE") return
        sendOneShot { port.setClearMode(mode) }
    }

    /**
     * Ajusta a posição dos motores de elevação. Para o movimento antes (STOP enviado na hora) e
     * grava as posições, que o polling reenvia a cada ciclo. O fim é detectado pelo status do
     * motor ou pelo timeout ([LIFT_ADJUST_TIMEOUT_SEC]); em ambos o estado fica em `STOP`: o
     * demo reinicia o movimento sozinho, aqui o usuário precisa iniciar de novo.
     */
    fun setMotorPosition(p1: Int, p2: Int) {
        requireConnected()
        requireLiftIdle("ajustar a posição dos motores")
        requirePolling("ajustar a posição dos motores")
        if (p1 < 0 || p2 < 0) {
            throw BridgeException(BridgeException.OUT_OF_RANGE, "As posições dos motores devem ser >= 0")
        }
        val current = port.controlValues()
        if (p1 == current.motorPosition1 && p2 == current.motorPosition2) {
            throw BridgeException(
                BridgeException.INVALID_ARGS,
                "Os motores já estão nas posições $p1 e $p2; nada a ajustar"
            )
        }
        haltMotion()
        port.setMotorPositions(p1, p2)
        liftKind = LiftKind.ADJUST
        lift.begin(liftAdjustTimeoutSec)
    }

    /**
     * Autoteste dos motores de elevação (`motorSelfCheck = true` durante a operação). O Javadoc
     * exige o movimento parado e que o app volte o flag para `false` assim que o controlador
     * terminar: a guarda faz isso ao concluir, ao estourar [timeoutSec] ou ao abortar.
     */
    fun startMotorSelfCheck(timeoutSec: Int) {
        requireConnected()
        requireLiftIdle("iniciar o autoteste")
        requirePolling("iniciar o autoteste")
        if (timeoutSec !in 1..MAX_SELF_CHECK_TIMEOUT_SEC) {
            throw BridgeException(
                BridgeException.OUT_OF_RANGE,
                "timeoutSec deve estar entre 1 e $MAX_SELF_CHECK_TIMEOUT_SEC"
            )
        }
        haltMotion()
        port.setMotorSelfCheck(true)
        liftKind = LiftKind.SELF_CHECK
        lift.begin(timeoutSec)
    }

    /** Envia os `ControlParams` armados uma única vez e desliga os flags em seguida. */
    private fun sendOneShot(arm: () -> Unit) {
        try {
            arm()
            port.send(port.controlCommand())
        } finally {
            disarmOneShot()
        }
    }

    /** Desliga os flags de disparo único para o polling não repetir o comando. */
    private fun disarmOneShot() {
        port.setNeedSetOrigin(false)
        port.setNeedErrorRestore(false)
        port.setClearMode("NONE")
    }

    /** `run = STOP` e o comando de controle sai na hora, sem esperar o próximo ciclo. */
    private fun haltMotion() {
        port.markStop()
        port.send(port.controlCommand())
    }

    private fun requireStopped(action: String) {
        if (port.controlValues().run == "RUNNING") {
            throw BridgeException(BridgeException.BUSY, "Pare a máquina antes de $action")
        }
    }

    private fun requirePolling(action: String) {
        if (!loop.isRunning) {
            throw BridgeException(
                BridgeException.SDK_ERROR,
                "Ligue o polling antes de $action: o controlador só recebe as ordens pelo polling"
            )
        }
    }

    private fun requireLiftIdle(action: String) {
        if (lift.isActive) {
            throw BridgeException(
                BridgeException.BUSY,
                "Os motores de elevação estão em operação; aguarde o fim antes de $action"
            )
        }
    }

    /**
     * Início ou fim de uma operação dos motores. Ao terminar, por qualquer motivo, desliga o flag
     * de autoteste, volta a `STOP` e empurra a ordem na hora (o Javadoc pede resposta imediata)
     * antes de publicar o evento.
     */
    private fun onLiftPhase(phase: LiftPhase, remainingSec: Int) {
        if (phase != LiftPhase.STARTED) {
            if (liftKind == LiftKind.SELF_CHECK) runCatching { port.setMotorSelfCheck(false) }
            runCatching { port.markStop() }
            if (port.isConnected()) runCatching { port.send(port.controlCommand()) }
            liftKind = null
        }
        emit(Mappers.liftMotor(phase.wire, remainingSec))
    }

    // ---- Internos ----

    /**
     * Para o laço de polling e volta o estado local para `STOP`: sem polling a máquina não recebe
     * mais ordens, então `getControlParams` nunca deve mostrar `RUNNING` com o polling parado.
     */
    private fun haltPolling() {
        loop.stop()
        if (configured) {
            runCatching { port.markStop() }
            // Sem polling a máquina não recebe mais ordens: a guarda dos motores não pode esperar.
            lift.abort()
        }
    }

    private fun requireInitialized() {
        if (!configured) {
            throw BridgeException(BridgeException.SDK_ERROR, "initialize ainda não foi chamado")
        }
    }

    private fun requireConnected() {
        requireInitialized()
        if (!port.isConnected()) {
            throw BridgeException(BridgeException.NOT_CONNECTED, "Sem conexão com a máquina")
        }
    }

    private fun pollOnce() {
        // Um comando, uma resposta: se o controlador não acompanha, não empilha ordens velhas.
        if (port.pendingCount() >= MAX_PENDING_COMMANDS) return
        port.send(port.controlCommand())
    }

    private fun onPollingError(error: Throwable) {
        haltPolling()
        emit(Mappers.connection("error", port.currentPortPath(), "Falha no polling: ${error.message}"))
    }

    private fun emit(event: Map<String, Any?>) {
        emitter?.invoke(event)
    }

    // ---- PortListener ----

    override fun onConnected(portPath: String) = emit(Mappers.connection("connected", portPath))

    override fun onConnectFailed(portPath: String, reason: String) {
        haltPolling()
        emit(Mappers.connection("failed", portPath, reason))
    }

    override fun onDisconnected(portPath: String) {
        haltPolling()
        emit(Mappers.connection("disconnected", portPath))
    }

    override fun onError(message: String) {
        haltPolling()
        emit(Mappers.connection("error", port.currentPortPath(), message))
    }

    override fun onSent(data: ByteArray, success: Boolean) {
        if (!logEnabled) return
        val name = runCatching { port.commandName(data) }.getOrDefault("UNKNOWN")
        emit(Mappers.log("tx", if (success) name else "$name (falha no envio)", Mappers.hex(data), clock.epochMs()))
    }

    override fun onStatus(status: DeviceStatus) {
        emit(Mappers.status(status, clock.monotonicMs(), clock.epochMs()))
        lift.onLiftStatus(status.getLiftMotorStatus().toInt())
    }

    override fun onDeviceInfo(info: DeviceInfo) = emit(Mappers.deviceInfo(info))

    override fun onParamsAck(values: ParamsValues) = emit(Mappers.paramsAck(values))

    override fun onPacket(typeName: String) {
        if (logEnabled) emit(Mappers.log("rx", typeName, null, clock.epochMs()))
    }

    companion object {
        /** Acima disso o ciclo de polling é pulado até o envio andar. */
        const val MAX_PENDING_COMMANDS = 3

        /**
         * Timeout do ajuste de posição dos motores. O demo usa `4 + Δnível × MOTOR_LONG_TIME` s, mas
         * o valor de `MOTOR_LONG_TIME` não está documentado: este é um teto conservador provisório
         * (igual ao do autoteste), a ser medido na bancada e confirmado com o fabricante.
         */
        const val LIFT_ADJUST_TIMEOUT_SEC = 130

        /** Teto do timeout de autoteste aceito do app. */
        const val MAX_SELF_CHECK_TIMEOUT_SEC = 600

        val shared: MachineController by lazy {
            MachineController(SdkSerialPort(), HandlerScheduler())
        }
    }
}
