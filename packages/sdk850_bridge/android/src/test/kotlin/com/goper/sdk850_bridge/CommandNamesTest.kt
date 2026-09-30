package com.goper.sdk850_bridge

import kotlin.test.Test
import kotlin.test.assertEquals

internal class CommandNamesTest {
    @Test
    fun traduzOsNomesConhecidosObservadosNoHardware() {
        assertEquals("CONTROL", CommandNames.translate("控制指令"))
        assertEquals("QUERY_DEVICE_INFO", CommandNames.translate("查询设备信息"))
    }

    @Test
    fun mantemONomeOriginalQuandoDesconhecido() {
        assertEquals("未知", CommandNames.translate("未知"))
        assertEquals("OTHER", CommandNames.translate("OTHER"))
    }
}
