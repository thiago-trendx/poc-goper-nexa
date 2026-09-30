package com.goper.sdk850_bridge

import com.sunway.sdk850.base.SerialPortCallback
import com.sunway.sdk850.base.SerialPortManager
import com.sunway.sdk850.base.paser.SerialPacket
import com.sunway.sdk850.port.Cmd
import com.sunway.sdk850.port.DeviceManager
import com.sunway.sdk850.port.bean.DeviceInfo
import com.sunway.sdk850.port.bean.DeviceStatus
import com.sunway.sdk850.port.bean.RunState
import com.sunway.sdk850.port.bean.SerialPacketType

/**
 * [SdkPort] sobre o SDK real. Só usa os nomes do Javadoc e do demo
 * (`WelcomeActivity`, `RunViewModel`).
 */
class SdkSerialPort : SdkPort {
    private val cmd = Cmd()
    private var callback: SerialPortCallback? = null

    private val manager: SerialPortManager
        get() = SerialPortManager.getInstance()

    override fun initDevice(spFileName: String) {
        DeviceManager.getInstance().init(AppContext.require(), spFileName)
    }

    override fun configure(baudRate: Int, sendIntervalMs: Long, testTimeMs: Long, logEnabled: Boolean) {
        val config = manager.getConfig()
        config
            .setBaudRate(baudRate)
            .setCmd(cmd)
            .setSendInterval(sendIntervalMs)
            .setTestTime(testTimeMs)
        config.setLogEnable(logEnabled)
    }

    override fun register(listener: PortListener) {
        unregister()
        val newCallback = object : SerialPortCallback.Simple() {
            override fun onConnected(portPath: String) = listener.onConnected(portPath)

            override fun onConnectFailed(portPath: String, reason: String) =
                listener.onConnectFailed(portPath, reason)

            override fun onDisconnected(portPath: String) = listener.onDisconnected(portPath)

            override fun onError(message: String) = listener.onError(message)

            override fun onDataSent(data: ByteArray, success: Boolean) = listener.onSent(data, success)

            override fun onDataReceived(serialPacket: SerialPacket) {
                val type = serialPacket.getType()
                listener.onPacket((type as? Enum<*>)?.name ?: type.toString())
                when (type) {
                    SerialPacketType.CONTROL ->
                        (serialPacket.getData() as? DeviceStatus)?.let { listener.onStatus(it) }

                    SerialPacketType.DEVICE_INFO ->
                        (serialPacket.getData() as? DeviceInfo)?.let {
                            // Como o demo: o DeviceManager guarda a última versão informada.
                            DeviceManager.getInstance().setDeviceInfo(it)
                            listener.onDeviceInfo(it)
                        }

                    else -> Unit
                }
            }
        }
        callback = newCallback
        manager.registerCallback(newCallback)
    }

    override fun unregister() {
        callback?.let { manager.unregisterCallback(it) }
        callback = null
    }

    override fun autoConnect() = manager.autoConnect()

    override fun connect(portPath: String): Boolean = manager.connect(portPath)

    override fun reConnect() = manager.reConnect()

    override fun disconnect() = manager.disconnect()

    override fun isConnected(): Boolean = manager.isConnected()

    override fun stateName(): String = manager.getState().name

    override fun currentPortPath(): String? = manager.getCurrentPortPath()

    override fun send(data: ByteArray) = manager.send(data)

    override fun clearSendQueue() = manager.clearSendQueue()

    override fun pendingCount(): Int = manager.getPendingCount()

    override fun controlCommand(): ByteArray =
        Cmd.control(DeviceManager.getInstance().getControlParams())

    override fun markStop() {
        DeviceManager.getInstance().getControlParams().setRun(RunState.STOP)
    }

    override fun deviceInfoQuery(): ByteArray = Cmd.quaryDeviceInfo()

    override fun commandName(data: ByteArray): String = CommandNames.translate(cmd.getCmdName(data))
}
