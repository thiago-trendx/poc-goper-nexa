package com.sunway.l850tdemo.custom_view;

import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.view.MotionEvent;
import android.view.View;

public class LongPressTouchListener implements View.OnTouchListener {
    
    private static final int DEFAULT_INTERVAL = 300;
    private static final int MSG_LONG_PRESS = 1001;
    private static final int MSG_INTERVAL = 1002;
    
    private Handler handler;
    private OnLongPressListener listener;
    private int interval;
    private boolean isLongPressTriggered = false;
    private boolean isDown = false;
    private View touchedView;
    
    public LongPressTouchListener(OnLongPressListener listener) {
        this(listener, DEFAULT_INTERVAL);
    }
    
    public LongPressTouchListener(OnLongPressListener listener, int interval) {
        this.listener = listener;
        this.interval = interval;
        this.handler = new Handler(Looper.getMainLooper()) {
            @Override
            public void handleMessage(Message msg) {
                if (msg.what == MSG_LONG_PRESS) {
                    // 长按触发
                    if (listener != null && isDown && touchedView != null) {
                        isLongPressTriggered = true;
                        listener.onLongPress(touchedView);
                        // 开始间隔回调
                        sendEmptyMessageDelayed(MSG_INTERVAL, interval);
                    }
                } else if (msg.what == MSG_INTERVAL) {
                    // 间隔回调
                    if (listener != null && isDown && touchedView != null) {
                        listener.onLongPress(touchedView);
                        // 继续下一次间隔回调
                        sendEmptyMessageDelayed(MSG_INTERVAL, interval);
                    }
                }
            }
        };
    }
    
    @Override
    public boolean onTouch(View v, MotionEvent event) {
        switch (event.getAction()) {
            case MotionEvent.ACTION_DOWN:
                isDown = true;
                isLongPressTriggered = false;
                touchedView = v;
                
                // 延迟触发长按
                handler.sendEmptyMessageDelayed(MSG_LONG_PRESS, interval);

                // 返回 false 让按钮也能处理点击事件
                return false;
                
            case MotionEvent.ACTION_MOVE:
                // 如果移动距离过大，取消长按
                /*if (isDown) {
                    float dx = event.getX();
                    float dy = event.getY();
                    if (Math.abs(dx) > 50 || Math.abs(dy) > 50) {
                        cancelLongPress();
                        isDown = false;
                        touchedView = null;
                    }
                }*/

                // 返回 false 让按钮也能处理点击事件
                return false;
                
            case MotionEvent.ACTION_UP:
            case MotionEvent.ACTION_CANCEL:
                // 如果还没触发长按，但按下的时间已经超过了最小间隔，触发一次
                if (!isLongPressTriggered && isDown && touchedView != null) {
                    // 取消延迟消息
                    handler.removeMessages(MSG_LONG_PRESS);
                    // 触发一次长按回调
                    if (listener != null) {
                        listener.onLongPress(touchedView);
                    }
                }
                
                // 清理状态
                cancelLongPress();
                isDown = false;
                touchedView = null;

                // 触发一次长按回调
                if (listener != null) {
                    listener.onUp(touchedView);
                }

                // 返回 false 让按钮也能处理点击事件
                return false;
        }
        return false;
    }
    
    /**
     * 取消长按
     */
    public void cancelLongPress() {
        handler.removeMessages(MSG_LONG_PRESS);
        handler.removeMessages(MSG_INTERVAL);
        isLongPressTriggered = false;
    }
    
    /**
     * 设置回调间隔
     */
    public void setInterval(int interval) {
        this.interval = interval;
    }
    
    /**
     * 长按监听回调接口
     */
    public interface OnLongPressListener {
        /**
         * 长按回调
         * @param v 触发的View
         */
        void onLongPress(View v);

        /**
         * 手指移开
         * */
        void onUp(View v);
    }
}