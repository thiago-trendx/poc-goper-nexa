package com.sunway.l850tdemo.dialog;

import android.app.Dialog;
import android.content.Context;
import android.content.DialogInterface;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import com.sunway.l850tdemo.databinding.DialogDownTimeBinding;


/** desc： 倒计时弹窗
 * create at 2026/3/21 10:27 by liuxiong
 */
public class DownTimeDialog extends Dialog {

    com.sunway.l850tdemo.databinding.DialogDownTimeBinding mBinding;
    private View.OnClickListener cancelListener;

    private Handler mHandler = new Handler(Looper.getMainLooper());

    public DownTimeDialog(@NonNull Context context) {
        super(context);

        setCancelable(false);
        setCanceledOnTouchOutside(false);

        init();
    }

    private void init(){
        mBinding = DialogDownTimeBinding.inflate(LayoutInflater.from(getContext()));

        mBinding.btnCancel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if(cancelListener !=null){
                    cancelListener.onClick(v);
                }

                dismiss();
            }
        });
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(mBinding.getRoot());

        Window window = getWindow();
        if (window != null) {
            //window.setWindowAnimations(R.style.DialogFadeAnim);
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            WindowManager.LayoutParams params = window.getAttributes();
            params.gravity = Gravity.CENTER;
            // 用真实屏幕像素的百分比，跟 dp / 密度 / AutoSize 都无关
            int screenWidth = getContext().getResources().getDisplayMetrics().widthPixels;
            params.width = (int) (screenWidth * 0.5f);
            params.height = WindowManager.LayoutParams.WRAP_CONTENT;
            window.setAttributes(params);
        }

        setOnDismissListener(new OnDismissListener() {
            @Override
            public void onDismiss(DialogInterface dialog) {
                mHandler.removeCallbacksAndMessages(null);
            }
        });
    }

    public DownTimeDialog setContent(CharSequence content){
        if(TextUtils.isEmpty(content)){
            return this;
        }
        mBinding.tvContent.setText(content);

        return this;
    }

    public void updateTime(int value){
        mBinding.tvDownTime.setText(value + " S");

        if(value <= 0 ){ // 倒计时结束
            mBinding.tvContent.setText("升降电机调节完成");
            mBinding.tvDownTime.setVisibility(View.GONE);
            mBinding.btnCancel.setVisibility(View.VISIBLE);
        }else{
            mBinding.tvContent.setText("正在调节升降电机，请稍后...");
            mBinding.tvDownTime.setVisibility(View.VISIBLE);
            mBinding.btnCancel.setVisibility(View.GONE);
        }
    }

    /** 取消监听 */
    public DownTimeDialog setOnCancelClickListener(View.OnClickListener confirmListener){
        this.cancelListener = confirmListener;
        return this;
    }
}
