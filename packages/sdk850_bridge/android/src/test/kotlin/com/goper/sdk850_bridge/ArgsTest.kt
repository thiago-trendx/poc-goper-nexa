package com.goper.sdk850_bridge

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull

internal class ArgsTest {
    private fun code(block: () -> Unit): String = assertFailsWith<BridgeException>(block = block).code

    @Test
    fun string_aceitaTextoNaoVazio() {
        assertEquals("sp", Args.string(mapOf("spFileName" to "sp"), "spFileName"))
    }

    @Test
    fun string_rejeitaAusenteVazioOuOutroTipo() {
        assertEquals(BridgeException.INVALID_ARGS, code { Args.string(null, "k") })
        assertEquals(BridgeException.INVALID_ARGS, code { Args.string(mapOf("k" to " "), "k") })
        assertEquals(BridgeException.INVALID_ARGS, code { Args.string(mapOf("k" to 3), "k") })
    }

    @Test
    fun optionalInt_aceitaIntELongEDevolveNuloQuandoAusente() {
        assertEquals(7, Args.optionalInt(mapOf("k" to 7), "k"))
        assertEquals(7, Args.optionalInt(mapOf("k" to 7L), "k"))
        assertNull(Args.optionalInt(mapOf<String, Any>(), "k"))
        assertNull(Args.optionalInt(null, "k"))
    }

    @Test
    fun optional_rejeitaTipoErrado() {
        assertEquals(BridgeException.INVALID_ARGS, code { Args.optionalInt(mapOf("k" to "7"), "k") })
        assertEquals(BridgeException.INVALID_ARGS, code { Args.optionalLong(mapOf("k" to true), "k") })
        assertEquals(BridgeException.INVALID_ARGS, code { Args.optionalBool(mapOf("k" to 1), "k") })
    }

    @Test
    fun optionalLongEBool() {
        assertEquals(50L, Args.optionalLong(mapOf("k" to 50), "k"))
        assertEquals(true, Args.optionalBool(mapOf("k" to true), "k"))
    }

    @Test
    fun pollingInterval_usaPadraoDe200ms() {
        assertEquals(200, Args.pollingInterval(null))
        assertEquals(200, Args.pollingInterval(mapOf<String, Any>()))
    }

    @Test
    fun pollingInterval_aceitaOsLimitesEOsValoresDoPlano() {
        for (ms in listOf(Args.MIN_POLLING_MS, 50, 100, 200, Args.MAX_POLLING_MS)) {
            assertEquals(ms, Args.pollingInterval(mapOf("intervalMs" to ms)))
        }
    }

    @Test
    fun pollingInterval_foraDaFaixaVira_OUT_OF_RANGE() {
        val below = Args.MIN_POLLING_MS - 1
        val above = Args.MAX_POLLING_MS + 1
        assertEquals(BridgeException.OUT_OF_RANGE, code { Args.pollingInterval(mapOf("intervalMs" to below)) })
        assertEquals(BridgeException.OUT_OF_RANGE, code { Args.pollingInterval(mapOf("intervalMs" to 0)) })
        assertEquals(BridgeException.OUT_OF_RANGE, code { Args.pollingInterval(mapOf("intervalMs" to -5)) })
        assertEquals(BridgeException.OUT_OF_RANGE, code { Args.pollingInterval(mapOf("intervalMs" to above)) })
    }

    @Test
    fun pollingInterval_tipoErradoVira_INVALID_ARGS() {
        assertEquals(BridgeException.INVALID_ARGS, code { Args.pollingInterval(mapOf("intervalMs" to "200")) })
    }
}
