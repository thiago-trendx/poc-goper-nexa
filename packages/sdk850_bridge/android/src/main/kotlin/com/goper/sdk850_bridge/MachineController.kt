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
    private val clock: Clock = SystemClockSource
) : PortListener {

    /** Destino dos eventos (o `EventSink` do canal). Nulo enquanto ninguém escuta. */
    var emitter: ((Map<String, Any?>) -> Unit)? = null

    private var deviceInitialized = false
    private var configured = false
    private var logEnabled = false

    private val loop = PollingLoop(scheduler, onTickError = ::onPollingError) { pollOnce() }

    val isPolling: Boolean
        get() = loop.isRunning

    // ---- Inicialização e conexão ----

    fun initialize(
        spFileName: String,
        baudRate: Int?,
        sendIntervalMs: Long?,
        testTimeMs: Long?,
        logEnabled: Boolean?
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
        if (port.isConnected()) {
            throw BridgeException(BridgeException.BUSY, "Desconecte antes de reconfigurar a serial")
        }

        if (!deviceInitialized) {
            port.initDevice(spFileName)
            deviceInitialized = true
        }
        this.logEnabled = logEnabled ?: false
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
        port.disconnect()
    }

    fun reconnect() {
        requireInitialized()
        port.reConnect()
    }

    fun connectionInfo(): Map<String, Any?> = Mappers.connectionInfo(port.stateName(), port.currentPortPath())

    // ---- Polling e comandos ----

    /**
     * Liga o polling. O valor padrão de `ControlParams.run` do SDK não é documentado, então o
     * polling sempre começa em `STOP` (motor em força base) para o primeiro envio nunca mandar
     * a máquina se mexer; quem quiser movimento usa `start` depois.
     */
    fun startPolling(intervalMs: Int) {
        requireConnected()
        port.markStop()
        loop.start(intervalMs.toLong())
    }

    fun stopPolling() {
        loop.stop()
        if (configured) port.clearSendQueue()
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
        loop.stop()
        runCatching { port.clearSendQueue() }
        runCatching { port.unregister() }
        runCatching { port.disconnect() }
        emitter = null
        configured = false
    }

    // ---- Internos ----

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
        loop.stop()
        emit(Mappers.connection("error", port.currentPortPath(), "Falha no polling: ${error.message}"))
    }

    private fun emit(event: Map<String, Any?>) {
        emitter?.invoke(event)
    }

    // ---- PortListener ----

    override fun onConnected(portPath: String) = emit(Mappers.connection("connected", portPath))

    override fun onConnectFailed(portPath: String, reason: String) {
        loop.stop()
        emit(Mappers.connection("failed", portPath, reason))
    }

    override fun onDisconnected(portPath: String) {
        loop.stop()
        emit(Mappers.connection("disconnected", portPath))
    }

    override fun onError(message: String) {
        loop.stop()
        emit(Mappers.connection("error", port.currentPortPath(), message))
    }

    override fun onSent(data: ByteArray, success: Boolean) {
        if (!logEnabled) return
        val name = runCatching { port.commandName(data) }.getOrDefault("UNKNOWN")
        emit(Mappers.log("tx", if (success) name else "$name (falha no envio)", Mappers.hex(data), clock.epochMs()))
    }

    override fun onStatus(status: DeviceStatus) =
        emit(Mappers.status(status, clock.monotonicMs(), clock.epochMs()))

    override fun onDeviceInfo(info: DeviceInfo) = emit(Mappers.deviceInfo(info))

    override fun onPacket(typeName: String) {
        if (logEnabled) emit(Mappers.log("rx", typeName, null, clock.epochMs()))
    }

    companion object {
        /** Acima disso o ciclo de polling é pulado até o envio andar. */
        const val MAX_PENDING_COMMANDS = 3

        val shared: MachineController by lazy {
            MachineController(SdkSerialPort(), HandlerScheduler())
        }
    }
}
