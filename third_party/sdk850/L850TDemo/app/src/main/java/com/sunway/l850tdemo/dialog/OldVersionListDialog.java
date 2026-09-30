package com.sunway.l850tdemo.dialog;

import android.app.Dialog;
import android.content.Context;
import android.graphics.Color;
import android.graphics.drawable.ColorDrawable;
import android.view.Gravity;
import android.view.LayoutInflater;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.LinearLayoutManager;

import com.sunway.l850tdemo.R;
import com.sunway.l850tdemo.databinding.DialogOldVersionListBinding;
import com.sunway.l850tdemo.util.LogUtil;
import com.sunway.l850tdemo.util.ToastUtil;

import java.io.File;
import java.util.ArrayList;
import java.util.List;

import lombok.Setter;

/**
 * 上控/下控  老版本列表
 * */
public class OldVersionListDialog extends Dialog {
    private final List<File> fileList = new ArrayList<>();

    private OldVersionListAdapter mAdapter;
    private DialogOldVersionListBinding mBinding;

    @Setter
    private Callback callback;

    public OldVersionListDialog(@NonNull Context context, File[] files) {
        super(context);
        for (int i = 0; i < files.length; i++) {
            fileList.add(files[i]);
        }

        init();
    }

    private void init() {
        requestWindowFeature(Window.FEATURE_NO_TITLE);

        mBinding = DialogOldVersionListBinding.inflate(LayoutInflater.from(getContext()));
        setContentView(mBinding.getRoot());

        Window window = getWindow();
        if (window != null) {
            window.setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            WindowManager.LayoutParams params = window.getAttributes();
            params.gravity = Gravity.CENTER;
            window.setAttributes(params);
        }
        LogUtil.d("OldVersionListDialog","fileList="+fileList);

        mBinding.recyclerView.setLayoutManager(new LinearLayoutManager(getContext()));
        mBinding.recyclerView.addItemDecoration(new WifiDividerDecoration(getContext()));
        mAdapter = new OldVersionListAdapter(fileList);
        mBinding.recyclerView.setAdapter(mAdapter);

        mBinding.tvCancel.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                dismiss();
            }
        });

        mBinding.tvConfirm.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                File selectedFile = mAdapter.getSelectedFile();

                if(selectedFile == null){
                    ToastUtil.show(getContext().getString(R.string.update_not_selected_verison));
                    return;
                }

                if(callback != null){
                    callback.onConfirm(selectedFile);
                }
                dismiss();
            }
        });
    }

    public interface  Callback{
        void onConfirm(File file);
    }

}
