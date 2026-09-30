package com.goper.sdk850_bridge

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.mockito.Mockito
import kotlin.test.Test

internal class Sdk850BridgePluginTest {
    @Test
    fun onMethodCall_beforePhase2_respondsNotImplemented() {
        val plugin = Sdk850BridgePlugin()
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("start", null), mockResult)

        Mockito.verify(mockResult).notImplemented()
    }
}
