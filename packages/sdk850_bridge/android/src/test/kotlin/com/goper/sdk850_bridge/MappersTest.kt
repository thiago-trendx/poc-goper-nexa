package com.goper.sdk850_bridge

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

internal class MappersTest {
    @Test
    fun hex_usaMaiusculoComEspacoEBytesNegativos() {
        val bytes = byteArrayOf(0xAA.toByte(), 0x55, 0x0F, 0x00, 0xFF.toByte())
        assertEquals("AA 55 0F 00 FF", Mappers.hex(bytes))
        assertEquals("", Mappers.hex(byteArrayOf()))
    }

    @Test
    fun deviceInfo_usaOsCamposDoContrato() {
        val expected = mapOf(
            "type" to "deviceInfo",
            "softwareNum" to "SW-1",
            "versionCode" to 41,
            "produceCode" to "P-9"
        )
        assertEquals(expected, Mappers.deviceInfo(sampleInfo()))
    }

    @Test
    fun status_trazTodosOsCamposDoContratoEOsDoisRelogios() {
        val map = Mappers.status(sampleStatus(), tsMonotonicMs = 123, tsEpochMs = 456)

        val expectedKeys = setOf(
            "type", "run", "mode", "force", "realForce", "speed", "distance", "pullNum",
            "errorCode", "temperature", "liftMotorStatus", "liftMotorError1", "liftMotorError2",
            "verityCodeError", "tsMonotonicMs", "tsEpochMs"
        )
        assertEquals(expectedKeys, map.keys)
        assertEquals("status", map["type"])
        assertEquals(123L, map["tsMonotonicMs"])
        assertEquals(456L, map["tsEpochMs"])
    }

    @Test
    fun status_enviaEnumsComoName() {
        val status = sampleStatus()
        val map = Mappers.status(status, 0, 0)
        assertEquals(status.getRun()?.name, map["run"])
        assertEquals(status.getMode()?.name, map["mode"])
    }

    @Test
    fun connection_omiteReasonQuandoNaoHa() {
        val ok = Mappers.connection("connected", "/dev/ttyS2")
        assertEquals(mapOf("type" to "connection", "state" to "connected", "portPath" to "/dev/ttyS2"), ok)
        assertFalse(ok.containsKey("reason"))

        assertEquals("timeout", Mappers.connection("failed", "/dev/ttyS2", "timeout")["reason"])
    }

    @Test
    fun connection_aceitaPortaNula() {
        val map = Mappers.connection("error", null, "x")
        assertTrue(map.containsKey("portPath"))
        assertNull(map["portPath"])
    }

    @Test
    fun log_omiteHexQuandoNaoHa() {
        val rx = Mappers.log("rx", "CONTROL", null, 10)
        assertEquals(
            mapOf("type" to "log", "direction" to "rx", "packetType" to "CONTROL", "tsEpochMs" to 10L),
            rx
        )
        assertEquals("AA", Mappers.log("tx", "CONTROL", "AA", 10)["hex"])
    }

    @Test
    fun connectionInfo_trazEstadoEPorta() {
        assertEquals(
            mapOf("state" to "CONNECTED", "portPath" to "/dev/ttyS2"),
            Mappers.connectionInfo("CONNECTED", "/dev/ttyS2")
        )
    }
}
