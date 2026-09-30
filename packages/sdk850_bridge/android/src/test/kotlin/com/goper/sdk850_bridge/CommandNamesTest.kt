package com.goper.sdk850_bridge

import kotlin.test.Test
import kotlin.test.assertEquals

internal class CommandNamesTest {
    @Test
    fun traduzOsNomesConhecidosObservadosNoHardware() {
        assertEquals("CONTROL", CommandNames.translate("控制指令"))
        assertEquals("QUERY_DEVICE_INFO", CommandNames.translate("查询设备信息"))
        assertEquals("SEND_PARAMS", CommandNames.translate("\u53c2\u6570\u4e0b\u53d1\u6307\u4ee4"))
    }

    @Test
    fun mantemONomeOriginalQuandoDesconhecido() {
        assertEquals("未知", CommandNames.translate("未知"))
        assertEquals("OTHER", CommandNames.translate("OTHER"))
    }
}
