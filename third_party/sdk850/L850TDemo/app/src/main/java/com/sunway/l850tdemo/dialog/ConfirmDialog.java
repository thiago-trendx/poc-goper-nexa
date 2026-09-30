package com.sunway.l850tdemo.dialog;

import android.app.Dialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.os.Bundle;
import android.text.TextUtils;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import com.sunway.l850tdemo.R;
import com.sunway.l850tdemo.databinding.DialogConfirmBinding;


/** desc： 通用确认框
 * create at 2026/3/21 10:27 by liuxiong
 */
public class ConfirmDialog extends Dialog {

    DialogConfirmBinding mBinding;
    private boolean needDismissForConfirm = true;
    private View.OnClickListener confirmListener;

    public ConfirmDialog(@NonNull Context context) {
        this(context,true);
    }

    public ConfirmDialog(@NonNull Context context, boolean needDismissForConfirm) {
        super(context);

        this.needDismissForConfirm = needDismissForConfirm;

        setCancelable(false);
        setCanceledOnTouchOutside(false);

        init();
    }

    private void init(){
        mBinding = DialogConfirmBinding.inflate(LayoutInflater.from(getContext()));

        mBinding.btnConfirm.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                if(confirmListener!=null){
                    confirmListener.onClick(v);
                }

                if(needDismissForConfirm){
                    dismiss();
                }
            }
        });
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(mBinding.getRoot());

        Window window = getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            WindowManager.LayoutParams params = window.getAttributes();
            params.gravity = Gravity.CENTER;
            // 用真实屏幕像素的百分比，跟 dp / 密度 / AutoSize 都无关
            int screenWidth = getContext().getResources().getDisplayMetrics().widthPixels;
            params.width = (int) (screenWidth * 0.75f);
            params.height = WindowManager.LayoutParams.WRAP_CONTENT;
            window.setAttributes(params);
        }
    }

    public ConfirmDialog setTitle(String title){
        if(TextUtils.isEmpty(title)){
            mBinding.tvTitle.setVisibility(View.GONE);
            return this;
        }
        mBinding.tvTitle.setText(title);
        mBinding.tvTitle.setVisibility(View.VISIBLE);
        return this;
    }

    public ConfirmDialog setContent(CharSequence content){
        if(TextUtils.isEmpty(content)){
            return this;
        }
        mBinding.tvContent.setText(content);

        return this;
    }

    public ConfirmDialog setConfirmButtonHide(){
        mBinding.btnConfirm.setVisibility(View.GONE);

        return this;
    }

    public  ConfirmDialog setConfirmBtnText(String btnText){
        if(TextUtils.isEmpty(btnText)){
            mBinding.btnConfirm.setVisibility(View.GONE);
            return this;
        }
        mBinding.btnConfirm.setText(btnText);
        mBinding.btnConfirm.setVisibility(View.VISIBLE);
        return this;
    }

    public ConfirmDialog setOnConfirmClickListener(boolean needDismiss, View.OnClickListener confirmListener){
        this.needDismissForConfirm = needDismiss;
        this.confirmListener = confirmListener;
        return this;
    }
}
