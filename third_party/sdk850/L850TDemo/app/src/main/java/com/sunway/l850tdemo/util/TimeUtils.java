package com.sunway.l850tdemo.util;

import java.util.Locale;

public class TimeUtils {

    /**
     * 将秒数格式化为时长字符串
     * @param totalSeconds 总秒数，如 90
     * @return 时长字符串，如 "00:01:30"
     */
    public static String formatDuration(long totalSeconds) {
        if (totalSeconds < 0) totalSeconds = 0;
        long hours   = totalSeconds / 3600;
        long minutes = (totalSeconds % 3600) / 60;
        long seconds = totalSeconds % 60;
        return String.format(Locale.getDefault(), "%02d:%02d:%02d", hours, minutes, seconds);
    }
}
