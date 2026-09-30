package com.sunway.l850tdemo.util;

import android.content.Context;
import android.os.Handler;
import android.os.Looper;
import android.util.DisplayMetrics;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.WindowManager;
import android.widget.ImageView;
import android.widget.TextView;
import android.widget.Toast;

import androidx.annotation.DrawableRes;
import androidx.annotation.NonNull;

import com.sunway.l850tdemo.R;

import java.util.Queue;
import java.util.concurrent.ConcurrentLinkedQueue;

/**
 * 线程安全 Toast 工具类，支持自定义布局
 *
 * 调用方式：
 *   ToastUtil.show("提示内容")
 *   ToastUtil.show("提示内容", Toast.LENGTH_LONG)
 *   ToastUtil.showWithIcon("提示内容", R.drawable.ic_success)
 */
public class ToastUtil {

    // ── 字段 ──────────────────────────────────────────────────

    private static Context sAppContext;
    private static final Handler sMainHandler   = new Handler(Looper.getMainLooper());
    private static final Queue<ToastItem> sQueue = new ConcurrentLinkedQueue<>();
    private static volatile boolean sIsShowing   = false;

    // 实际显示时长（毫秒）
    private static final int DURATION_SHORT    = 2000;
    private static final int DURATION_LONG     = 3500;
    private static final int DURATION_SHORTENED = 1500; // 队列积压时缩短

    // ── Toast 实体 ────────────────────────────────────────────

    private static class ToastItem {
        final String message;
        final int    duration;    // Toast.LENGTH_SHORT / LENGTH_LONG
        final int    iconRes;     // 0 表示无图标

        ToastItem(String message, int duration, int iconRes) {
            this.message  = message;
            this.duration = duration;
            this.iconRes  = iconRes;
        }
    }

    // ── 初始化 ────────────────────────────────────────────────

    /** 必须在 Application.onCreate() 中调用一次 */
    public static void init(@NonNull Context appContext) {
        sAppContext = appContext.getApplicationContext();
    }

    // ── 公开 API ──────────────────────────────────────────────

    /** 显示短时长 Toast */
    public static void show(String message) {
        enqueue(message, Toast.LENGTH_SHORT, 0);
    }

    /** 显示指定时长 Toast */
    public static void show(String message, int duration) {
        enqueue(message, duration, 0);
    }

    /** 带图标的 Toast */
    public static void showWithIcon(String message, @DrawableRes int iconRes) {
        enqueue(message, Toast.LENGTH_SHORT, iconRes);
    }

    /** 带图标、指定时长的 Toast */
    public static void showWithIcon(String message, int duration, @DrawableRes int iconRes) {
        enqueue(message, duration, iconRes);
    }

    /** 清空所有待显示的 Toast */
    public static void clearAll() {
        sQueue.clear();
        sMainHandler.removeCallbacksAndMessages(null);
        sIsShowing = false;
    }

    // ── 内部逻辑 ──────────────────────────────────────────────

    private static void enqueue(String message, int duration, int iconRes) {
        if (sAppContext == null) {
            throw new IllegalStateException("ToastUtil 未初始化，请在 Application 中调用 ToastUtil.init(this)");
        }
        if (message == null || message.isEmpty()) {
            return;
        }
        sQueue.offer(new ToastItem(message, duration, iconRes));
        if (!sIsShowing) {
            processNext();
        }
    }

    private static void processNext() {
        ToastItem item = sQueue.poll();
        if (item == null) {
            sIsShowing = false;
            return;
        }
        sIsShowing = true;

        // 必须在主线程创建和显示 Toast
        sMainHandler.post(() -> {
            Toast toast = buildToast(item);
            toast.show();

            // 队列积压时缩短单条显示时长，避免等待过久
            int delay = sQueue.size() > 3
                    ? DURATION_SHORTENED
                    : (item.duration == Toast.LENGTH_SHORT ? DURATION_SHORT : DURATION_LONG);

            sMainHandler.postDelayed(ToastUtil::processNext, delay);
        });
    }

    /**
     * 构建自定义布局 Toast
     * Android 11（API 30）之后系统 Toast 不再允许自定义布局（非系统应用），
     * 但本项目是系统应用，自定义布局仍然有效。
     */
    private static Toast buildToast(ToastItem item) {
        Toast toast = new Toast(sAppContext);
        toast.setDuration(item.duration);

        View view = LayoutInflater.from(sAppContext)
                .inflate(R.layout.view_toast_custom, null);

        TextView tvMsg = view.findViewById(R.id.tv_toast_msg);
        ImageView ivIcon = view.findViewById(R.id.iv_toast_icon);

        tvMsg.setText(item.message);

        if (item.iconRes != 0) {
            ivIcon.setImageResource(item.iconRes);
            ivIcon.setVisibility(View.VISIBLE);
        } else {
            ivIcon.setVisibility(View.GONE);
        }

        toast.setView(view);

        // 显示在屏幕底部居中，距底部 200px
        toast.setGravity(Gravity.BOTTOM | Gravity.CENTER_HORIZONTAL, 0, getScreenHeight()/2-100);
        return toast;
    }

    public static int getScreenHeight() {
        WindowManager wm = (WindowManager) sAppContext.getSystemService(Context.WINDOW_SERVICE);
        DisplayMetrics metrics = new DisplayMetrics();
        wm.getDefaultDisplay().getRealMetrics(metrics);
        return metrics.heightPixels;
    }
}