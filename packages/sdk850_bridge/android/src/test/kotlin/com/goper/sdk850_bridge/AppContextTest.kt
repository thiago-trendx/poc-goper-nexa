package com.goper.sdk850_bridge

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

internal class AppContextTest {
    @Test
    fun require_semEngineAnexadoVira_SDK_ERROR() {
        AppContext.application = null

        val error = assertFailsWith<BridgeException> { AppContext.require() }

        assertEquals(BridgeException.SDK_ERROR, error.code)
    }
}
