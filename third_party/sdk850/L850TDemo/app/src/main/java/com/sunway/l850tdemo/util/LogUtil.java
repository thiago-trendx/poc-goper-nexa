package com.sunway.l850tdemo.util;

import android.util.Log;

/**
 * 智能 Log 工具类：
 * - 默认 TAG 自动取当前调用类的类名，无需手动传入
 * - 支持 Throwable 异常堆栈打印
 * - Logcat 输出开关（LOG_ENABLE）与文件收集开关（FILE_LOG_ENABLE）分离
 * - 所有日志自动转发给 LogCollector，由其异步写入本地文件
 *
 * 调用示例：
 * LogUtil.d("调试信息");                           // TAG 自动为当前类名
 * LogUtil.e("错误信息", new Exception("发生异常"));  // 带异常堆栈
 * LogUtil.i("CUSTOM_TAG", "自定义 TAG 的信息");      // 自定义 TAG
 */
public final class LogUtil {

    // ══════════════════════════════════════════════════════════
    //  配置项
    // ══════════════════════════════════════════════════════════

    /**
     * Logcat 输出总开关
     * 发布版本改为 false 可关闭所有 Logcat 输出，文件收集不受影响
     */
    private static final boolean LOG_ENABLE = true;

    /**
     * 文件收集开关
     * 改为 false 则不写入本地文件
     */
    private static final boolean FILE_LOG_ENABLE = true;

    /** 兜底默认 TAG，堆栈获取失败时使用 */
    private static final String FALLBACK_TAG = "AndroidDevLog";

    /**
     * 堆栈偏移量：定位到实际调用 LogUtil 的类
     *
     * Thread.getStackTrace() 层级：
     *   0 = VMStack.getThreadStackTrace (native)
     *   1 = Thread.getStackTrace
     *   2 = LogUtil.getCurrentClassName
     *   3 = LogUtil.printLog
     *   4 = LogUtil.d / e / w / i / v 等公开方法
     *   5 = 实际调用方  ← 目标
     *
     * 若在 LogUtil 外部再封装一层，此值需 +1
     */
    private static final int STACK_OFFSET = 5;

    // ══════════════════════════════════════════════════════════
    //  构造方法（禁止实例化）
    // ══════════════════════════════════════════════════════════

    private LogUtil() {
        throw new UnsupportedOperationException("不能实例化 LogUtil 工具类");
    }

    // ══════════════════════════════════════════════════════════
    //  基础调用（TAG 自动取当前类名）
    // ══════════════════════════════════════════════════════════

    public static void v(String msg) {
        printLog(Log.VERBOSE, getCurrentClassName(), msg, null);
    }

    public static void v(String msg, Throwable tr) {
        printLog(Log.VERBOSE, getCurrentClassName(), msg, tr);
    }

    public static void d(String msg) {
        printLog(Log.DEBUG, getCurrentClassName(), msg, null);
    }

    public static void d(String msg, Throwable tr) {
        printLog(Log.DEBUG, getCurrentClassName(), msg, tr);
    }

    public static void i(String msg) {
        printLog(Log.INFO, getCurrentClassName(), msg, null);
    }

    public static void i(String msg, Throwable tr) {
        printLog(Log.INFO, getCurrentClassName(), msg, tr);
    }

    public static void w(String msg) {
        printLog(Log.WARN, getCurrentClassName(), msg, null);
    }

    public static void w(String msg, Throwable tr) {
        printLog(Log.WARN, getCurrentClassName(), msg, tr);
    }

    public static void e(String msg) {
        printLog(Log.ERROR, getCurrentClassName(), msg, null);
    }

    public static void e(String msg, Throwable tr) {
        printLog(Log.ERROR, getCurrentClassName(), msg, tr);
    }

    // ══════════════════════════════════════════════════════════
    //  自定义 TAG 调用
    // ══════════════════════════════════════════════════════════

    public static void v(String tag, String msg) {
        printLog(Log.VERBOSE, tag, msg, null);
    }

    public static void v(String tag, String msg, Throwable tr) {
        printLog(Log.VERBOSE, tag, msg, tr);
    }

    public static void d(String tag, String msg) {
        printLog(Log.DEBUG, tag, msg, null);
    }

    public static void d(String tag, String msg, Throwable tr) {
        printLog(Log.DEBUG, tag, msg, tr);
    }

    public static void i(String tag, String msg) {
        printLog(Log.INFO, tag, msg, null);
    }

    public static void i(String tag, String msg, Throwable tr) {
        printLog(Log.INFO, tag, msg, tr);
    }

    public static void w(String tag, String msg) {
        printLog(Log.WARN, tag, msg, null);
    }

    public static void w(String tag, String msg, Throwable tr) {
        printLog(Log.WARN, tag, msg, tr);
    }

    public static void e(String tag, String msg) {
        printLog(Log.ERROR, tag, msg, null);
    }

    public static void e(String tag, String msg, Throwable tr) {
        printLog(Log.ERROR, tag, msg, tr);
    }

    // ══════════════════════════════════════════════════════════
    //  扩展：仅打印异常堆栈
    // ══════════════════════════════════════════════════════════

    public static void e(Throwable tr) {
        printLog(Log.ERROR, getCurrentClassName(), "", tr);
    }

    public static void et(String tag, Throwable tr) {
        printLog(Log.ERROR, tag, "", tr);
    }

    // ══════════════════════════════════════════════════════════
    //  核心：统一打印 + 转发给 LogCollector
    // ══════════════════════════════════════════════════════════

    /**
     * 统一处理日志打印，并将日志转发给 LogCollector 异步写文件
     *
     * @param level 日志等级（Log.VERBOSE / DEBUG / INFO / WARN / ERROR）
     * @param tag   日志 TAG
     * @param msg   日志消息
     * @param tr    异常（可为 null）
     */
    private static void printLog(int level, String tag, String msg, Throwable tr) {
        // 空消息保护
        String finalMsg = (msg == null) ? "null" : msg;

        // ── 1. 输出到 Logcat ──────────────────────────────────
        if (LOG_ENABLE) {
            switch (level) {
                case Log.VERBOSE:
                    Log.v(tag, finalMsg, tr);
                    break;
                case Log.DEBUG:
                    Log.d(tag, finalMsg, tr);
                    break;
                case Log.INFO:
                    Log.i(tag, finalMsg, tr);
                    break;
                case Log.WARN:
                    Log.w(tag, finalMsg, tr);
                    break;
                case Log.ERROR:
                    Log.e(tag, finalMsg, tr);
                    break;
                default:
                    Log.d(tag, finalMsg, tr);
                    break;
            }
        }

        // ── 2. 转发给 LogCollector 异步写文件 ─────────────────
        /*if (FILE_LOG_ENABLE) {
            try {
                LogCollector.getInstance().enqueue(levelToChar(level), tag, finalMsg, tr);
            } catch (IllegalStateException e) {
                // LogCollector 未初始化时静默忽略，不影响正常日志输出
            }
        }*/
    }

    // ══════════════════════════════════════════════════════════
    //  工具方法
    // ══════════════════════════════════════════════════════════

    /**
     * 获取当前调用 LogUtil 的类的简单类名（不含包名）
     *
     * @return 类名；堆栈获取失败时返回兜底 TAG
     */
    private static String getCurrentClassName() {
        if (!LOG_ENABLE) {
            return FALLBACK_TAG;
        }
        try {
            StackTraceElement[] stackTrace = Thread.currentThread().getStackTrace();
            // 校验堆栈长度，避免数组越界
            if (stackTrace == null || stackTrace.length <= STACK_OFFSET) {
                return FALLBACK_TAG;
            }
            StackTraceElement targetElement = stackTrace[STACK_OFFSET];
            String fullClassName = targetElement.getClassName();
            // 截取简单类名：com.example.MainActivity → MainActivity
            return fullClassName.substring(fullClassName.lastIndexOf(".") + 1);
        } catch (Exception e) {
            // 任何异常都返回兜底 TAG，避免影响日志打印
            return FALLBACK_TAG;
        }
    }

    /**
     * 将 Log.xxx 级别常量转为 Logcat 风格的单字符标识
     *
     * @param level Log.VERBOSE / DEBUG / INFO / WARN / ERROR
     * @return 'V' / 'D' / 'I' / 'W' / 'E'
     */
    private static char levelToChar(int level) {
        switch (level) {
            case Log.VERBOSE:
                return 'V';
            case Log.DEBUG:
                return 'D';
            case Log.INFO:
                return 'I';
            case Log.WARN:
                return 'W';
            case Log.ERROR:
                return 'E';
            default:
                return 'D';
        }
    }
}