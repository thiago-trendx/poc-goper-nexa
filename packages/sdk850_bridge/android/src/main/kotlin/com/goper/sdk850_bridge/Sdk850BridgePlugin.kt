package com.goper.sdk850_bridge

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Registra os canais do contrato (`sdk850_bridge/methods` e `sdk850_bridge/events`).
 *
 * Os métodos ainda não estão implementados: a ponte com o SDK chega na Fase 2.
 * Até lá, toda chamada responde `notImplemented` e o Dart a converte em `MachineException`.
 */
class Sdk850BridgePlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler {
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, METHODS_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENTS_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result
    ) {
        result.notImplemented()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = Unit

    override fun onCancel(arguments: Any?) = Unit

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
    }

    companion object {
        const val METHODS_CHANNEL = "sdk850_bridge/methods"
        const val EVENTS_CHANNEL = "sdk850_bridge/events"
    }
}
