package com.goper.sdk850_bridge

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Registra os canais do contrato (`sdk850_bridge/methods` e `sdk850_bridge/events`) e
 * encaminha os métodos ao [MachineController].
 *
 * Métodos ainda não implementados respondem `notImplemented`; o Dart os converte em
 * `MachineException(SDK_ERROR)`.
 */
class Sdk850BridgePlugin(
    private val controllerProvider: () -> MachineController = { MachineController.shared }
) : FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler {
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

    private val controller: MachineController
        get() = controllerProvider()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        AppContext.application = flutterPluginBinding.applicationContext
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, METHODS_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENTS_CHANNEL).also {
            it.setStreamHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        try {
            when (call.method) {
                "initialize" -> {
                    controller.initialize(
                        spFileName = Args.string(args, "spFileName"),
                        baudRate = Args.optionalInt(args, "baudRate"),
                        sendIntervalMs = Args.optionalLong(args, "sendIntervalMs"),
                        testTimeMs = Args.optionalLong(args, "testTimeMs"),
                        logEnabled = Args.optionalBool(args, "logEnabled")
                    )
                    result.success(null)
                }

                "autoConnect" -> {
                    controller.autoConnect()
                    result.success(null)
                }

                "connect" -> result.success(controller.connect(Args.string(args, "portPath")))

                "disconnect" -> {
                    controller.disconnect()
                    result.success(null)
                }

                "reconnect" -> {
                    controller.reconnect()
                    result.success(null)
                }

                "getConnectionInfo" -> result.success(controller.connectionInfo())

                "startPolling" -> {
                    controller.startPolling(Args.pollingInterval(args))
                    result.success(null)
                }

                "stopPolling" -> {
                    controller.stopPolling()
                    result.success(null)
                }

                "queryDeviceInfo" -> {
                    controller.queryDeviceInfo()
                    result.success(null)
                }

                "stop" -> {
                    controller.stop()
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        } catch (e: BridgeException) {
            result.error(e.code, e.message, e.details)
        } catch (e: Exception) {
            result.error(BridgeException.SDK_ERROR, e.message ?: e.javaClass.simpleName, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val sink = events ?: return
        controller.emitter = { event ->
            // Os eventos do SDK chegam na thread principal, mas o envio de dados pode não chegar.
            if (Looper.myLooper() == Looper.getMainLooper()) {
                sink.success(event)
            } else {
                mainHandler.post { sink.success(event) }
            }
        }
    }

    /** O Dart parou de escutar (app fechando ou engine reiniciando): solta a serial. */
    override fun onCancel(arguments: Any?) {
        controller.shutdown()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        controller.shutdown()
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        AppContext.application = null
    }

    companion object {
        const val METHODS_CHANNEL = "sdk850_bridge/methods"
        const val EVENTS_CHANNEL = "sdk850_bridge/events"
    }
}
