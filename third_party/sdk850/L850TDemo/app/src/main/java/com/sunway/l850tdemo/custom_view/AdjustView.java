package com.sunway.l850tdemo.custom_view;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.res.TypedArray;
import android.util.AttributeSet;
import android.view.LayoutInflater;
import android.view.View;
import android.widget.LinearLayout;

import androidx.appcompat.widget.AppCompatButton;

import com.sunway.l850tdemo.R;
import com.sunway.l850tdemo.util.LogUtil;
import com.sunway.l850tdemo.util.ToastUtil;
import com.sunway.sdk850.port.DeviceManager;
import com.sunway.sdk850.port.bean.DeviceParams;

import lombok.Setter;

public class AdjustView extends LinearLayout {

    private AppCompatButton btnLeft;
    private AppCompatButton btnCenter;
    private AppCompatButton btnRight;

    @Setter
    private Callback callback;

    private int value; // 值

    @Setter
    private String unit = ""; //单位

    private int type = 0;

    @Setter
    private int maxValue = 10; //最大值
    @Setter
    private int minValue = 0; //最小值

    private long toastTime = 0;

    public AdjustView(Context context) {
        this(context, null);
    }

    public AdjustView(Context context, AttributeSet attrs) {
        this(context, attrs, 0);
    }

    public AdjustView(Context context, AttributeSet attrs, int defStyleAttr) {
        super(context, attrs, defStyleAttr);
        init(context, attrs);
    }

    @SuppressLint("ClickableViewAccessibility")
    private void init(Context context, AttributeSet attrs) {
        // 设置布局方向（因为merge中不包含父布局，需要在这里设置）
        setOrientation(HORIZONTAL);
        setBackgroundResource(R.drawable.shape_bg_e2e2e2);
        setPadding(dpToPx(20), dpToPx(10), dpToPx(20), dpToPx(10));
        
        // 使用merge加载布局
        LayoutInflater.from(context).inflate(R.layout.view_resistance_control, this, true);
        
        // 初始化控件
        btnLeft = findViewById(R.id.btn_sub);
        btnCenter = findViewById(R.id.btn_resistance_vaule);
        btnRight = findViewById(R.id.btn_add);
        
        // 读取自定义属性
        if (attrs != null) {
            TypedArray ta = context.obtainStyledAttributes(attrs, R.styleable.ResistanceControlView);
            
            String leftText = ta.getString(R.styleable.ResistanceControlView_leftText);
            String centerText = ta.getString(R.styleable.ResistanceControlView_centerText);
            String rightText = ta.getString(R.styleable.ResistanceControlView_rightText);
            
            if (leftText != null) setLeftText(leftText);
            if (centerText != null) setCenterText(centerText);
            if (rightText != null) setRightText(rightText);
            
            ta.recycle();
        }

        btnLeft.setOnTouchListener(new LongPressTouchListener(new LongPressTouchListener.OnLongPressListener() {
            @Override
            public void onLongPress(View v) {
                if(value <= minValue){
                    if(System.currentTimeMillis() - toastTime > 3000){
                        toast("已是最小值");
                        toastTime = System.currentTimeMillis();
                    }
                    return;
                }

                value --;

                setValue(value);
                LogUtil.d("--- onLongPress", "value = "+ value);
            }

            @Override
            public void onUp(View v) {


                if(callback != null){
                    callback.onChange(value);
                }
            }
        }));

        btnRight.setOnTouchListener(new LongPressTouchListener(new LongPressTouchListener.OnLongPressListener() {
            @Override
            public void onLongPress(View v) {
                if(value >= maxValue){
                    if(System.currentTimeMillis() - toastTime > 3000){
                        toast("已是最大值");
                        toastTime = System.currentTimeMillis();
                    }
                    return;
                }

                value ++;

                setValue(value);
                LogUtil.d("--- onLongPress", "value = "+ value);
            }

            @Override
            public void onUp(View v) {
                if(callback != null){
                    callback.onChange(value);
                }
            }
        }));
    }

    private  void toast(String message){
        ToastUtil.show(message);
    }

    public void setType(int type) {
        this.type = type;
        DeviceParams params = DeviceManager.getInstance().getDeviceParams();
        switch (type){
            case 0: //阻力
                minValue = params.getMinForce();
                maxValue = params.getMaxForce();
                break;

            case 1: //向心、离心
                minValue = 0;
                maxValue = 6;
                break;

            case 2: //等速 、弹力
                minValue = 0;
                maxValue = 10;
                break;

            case 3: //电机1 、电机2
                minValue = 0;
                maxValue = 10;
                break;
        }
    }

    // 设置左按钮文字
    public void setLeftText(String text) {
        btnLeft.setText(text);
    }

    public void setValue(int value){
        this.value = value;
        btnCenter.setText(value + " " + unit);
    }

    public void setCenterText(String text){
        btnCenter.setText(text);
    }

    // 设置右按钮文字
    public void setRightText(String text) {
        btnRight.setText(text);
    }

    // dp转px工具方法
    private int dpToPx(int dp) {
        return (int) (dp * getResources().getDisplayMetrics().density + 0.5f);
    }

    public interface Callback{
        void onChange(int vaule);
    }

}