package com.goper.sdk850_bridge

import com.sunway.sdk850.base.SerialPortCallback
import com.sunway.sdk850.base.SerialPortManager
import com.sunway.sdk850.base.paser.SerialPacket
import com.sunway.sdk850.port.Cmd
import com.sunway.sdk850.port.DeviceManager
import com.sunway.sdk850.port.bean.ClearMode
import com.sunway.sdk850.port.bean.DeviceInfo
import com.sunway.sdk850.port.bean.DeviceParams
import com.sunway.sdk850.port.bean.ControlParams
import com.sunway.sdk850.port.bean.DeviceStatus
import com.sunway.sdk850.port.bean.ForceMode
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

                    SerialPacketType.SEND_PARAMS ->
                        (serialPacket.getData() as? DeviceParams)?.let { listener.onParamsAck(it.toValues()) }

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

    private val control: ControlParams
        get() = DeviceManager.getInstance().getControlParams()

    override fun markStop() = setRunning(false)

    override fun setRunning(running: Boolean) {
        control.setRun(if (running) RunState.RUNNING else RunState.STOP)
    }

    override fun controlValues(): ControlValues {
        val c = control
        return ControlValues(
            run = c.getRun()?.name,
            mode = c.getMode()?.name,
            force = c.getForce(),
            centripetal = c.getCentripetal(),
            centrifugal = c.getCentrifugal(),
            velocity = c.getVelocity(),
            elastic = c.getElastic(),
            safeMode = c.getSafeMode(),
            clearMode = c.getClearMode()?.name,
            motorPosition1 = c.getMotorPosition1(),
            motorPosition2 = c.getMotorPosition2(),
            motorSelfCheck = c.isMotorSelfCheck(),
            balancingForce = c.getBalancingForce(),
            maxElectric = c.getMaxElectric(),
            needSetOrigin = c.isNeedSetOrigin(),
            needErrorRestor = c.isNeedErrorRestor()
        )
    }

    override fun setForce(kg: Int) = control.setForce(kg)

    override fun setMode(mode: String) = control.setMode(ForceMode.valueOf(mode))

    override fun setCoefficient(kind: String, value: Int) {
        when (kind) {
            "centripetal" -> control.setCentripetal(value)
            "centrifugal" -> control.setCentrifugal(value)
            "velocity" -> control.setVelocity(value)
            "elastic" -> control.setElastic(value)
            else -> throw IllegalArgumentException("kind inválido: $kind")
        }
    }

    // O Javadoc usa setMaxElectric; o guia do fabricante cita setMaxElectricLength (pergunta 7).
    override fun setElasticMax(value: Int) = control.setMaxElectric(value)

    override fun setSafeMode(value: Int) = control.setSafeMode(value)

    override fun setBalancingForce(kg: Int) = control.setBalancingForce(kg)

    override fun setNeedSetOrigin(value: Boolean) = control.setNeedSetOrigin(value)

    override fun setNeedErrorRestore(value: Boolean) = control.setNeedErrorRestor(value)

    override fun setClearMode(mode: String) = control.setClearMode(ClearMode.valueOf(mode))

    override fun setRunErrorRestore() = control.setRun(RunState.ERROR_RESTORE)

    override fun setMotorSelfCheck(value: Boolean) = control.setMotorSelfCheck(value)

    override fun setMotorPositions(p1: Int, p2: Int) {
        control.setMotorPosition1(p1)
        control.setMotorPosition2(p2)
    }

    override fun deviceParams(): ParamsValues = DeviceManager.getInstance().getDeviceParams().toValues()

    override fun paramsCommand(values: ParamsValues): ByteArray {
        val params = DeviceManager.getInstance().getDeviceParams()
        params.setMinForce(values.minForce)
        params.setMaxForce(values.maxForce)
        params.setInactiveForce(values.inactiveForce)
        params.setMaxLength(values.maxLength)
        params.setRatedSpeed(values.ratedSpeed)
        params.setRopeGuideDiameter(values.ropeGuideDiameter)
        params.setOrginMinDistance(values.orginMinDistance)
        params.setOrginMaxDistance(values.orginMaxDistance)
        params.setVelocityRange(values.velocityRange)
        params.setTorqueVariationCycle(values.torqueVariationCycle)
        params.setTorqueCoefficient(values.torqueCoefficient)
        return Cmd.sendParams(params)
    }

    private fun DeviceParams.toValues() = ParamsValues(
        minForce = getMinForce(),
        maxForce = getMaxForce(),
        inactiveForce = getInactiveForce(),
        maxLength = getMaxLength(),
        ratedSpeed = getRatedSpeed(),
        ropeGuideDiameter = getRopeGuideDiameter(),
        orginMinDistance = getOrginMinDistance(),
        orginMaxDistance = getOrginMaxDistance(),
        velocityRange = getVelocityRange(),
        torqueVariationCycle = getTorqueVariationCycle(),
        torqueCoefficient = getTorqueCoefficient()
    )

    override fun deviceInfoQuery(): ByteArray = Cmd.quaryDeviceInfo()

    override fun commandName(data: ByteArray): String = CommandNames.translate(cmd.getCmdName(data))
}
