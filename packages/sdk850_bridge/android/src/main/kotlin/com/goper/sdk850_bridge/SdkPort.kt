package com.goper.sdk850_bridge

import android.os.SystemClock
import com.sunway.sdk850.port.bean.DeviceInfo
import com.sunway.sdk850.port.bean.DeviceStatus

/** Eventos do SDK já separados por tipo. Os callbacks de dados chegam na thread principal. */
interface PortListener {
    fun onConnected(portPath: String)
    fun onConnectFailed(portPath: String, reason: String)
    fun onDisconnected(portPath: String)
    fun onError(message: String)
    fun onSent(data: ByteArray, success: Boolean)
    fun onStatus(status: DeviceStatus)
    fun onDeviceInfo(info: DeviceInfo)

    /** Resposta `SEND_PARAMS`: os parâmetros que o controlador devolveu. */
    fun onParamsAck(values: ParamsValues)

    /** Qualquer pacote recebido, pelo nome do tipo (`CONTROL`, `DEVICE_INFO`…), para o log. */
    fun onPacket(typeName: String)
}

/**
 * Tudo que o [MachineController] usa do SDK 850. A implementação real é o [SdkSerialPort];
 * nos testes entra um fake, sem o SDK nem a serial.
 */
interface SdkPort {
    /** `DeviceManager.init` com o contexto da aplicação; só pode rodar uma vez por processo. */
    fun initDevice(spFileName: String)

    /** Configura o `SerialPortConfig`; precisa ser chamado antes de conectar. */
    fun configure(baudRate: Int, sendIntervalMs: Long, testTimeMs: Long, logEnabled: Boolean)

    /** Registra [listener], substituindo o anterior. */
    fun register(listener: PortListener)
    fun unregister()

    fun autoConnect()
    fun connect(portPath: String): Boolean
    fun reConnect()
    fun disconnect()
    fun isConnected(): Boolean
    fun stateName(): String
    fun currentPortPath(): String?

    /** Enfileira [data] para envio, sem bloquear. */
    fun send(data: ByteArray)
    fun clearSendQueue()
    fun pendingCount(): Int

    /** `Cmd.control` dos `ControlParams` atuais. */
    fun controlCommand(): ByteArray

    /** Coloca `ControlParams.run` em `STOP`; o envio é feito por [controlCommand] + [send]. */
    fun markStop()

    /**
     * `DeviceParams` guardados no `DeviceManager`. É o cache local (SharedPreferences), que o SDK
     * também atualiza com o retorno de `SEND_PARAMS`; **não** é uma leitura do controlador.
     */
    fun deviceParams(): ParamsValues

    /**
     * Grava [values] nos `DeviceParams` do `DeviceManager` (cada setter persiste na hora, antes de
     * o controlador confirmar) e devolve o `Cmd.sendParams` correspondente.
     */
    fun paramsCommand(values: ParamsValues): ByteArray

    /** `Cmd.quaryDeviceInfo` (a grafia é do SDK). */
    fun deviceInfoQuery(): ByteArray

    /** Nome do comando que [data] representa, só para o log de debug. */
    fun commandName(data: ByteArray): String
}

/** Relógios usados nos eventos `status` e `log`. */
interface Clock {
    fun monotonicMs(): Long
    fun epochMs(): Long
}

object SystemClockSource : Clock {
    override fun monotonicMs(): Long = SystemClock.elapsedRealtime()
    override fun epochMs(): Long = System.currentTimeMillis()
}
