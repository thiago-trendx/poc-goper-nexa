package com.sunway.l850tdemo.dialog;

import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;


import com.chad.library.adapter.base.BaseQuickAdapter;
import com.chad.library.adapter.base.viewholder.BaseViewHolder;
import com.sunway.l850tdemo.R;
import com.sunway.l850tdemo.databinding.ItemOldVersionListBinding;
import com.sunway.l850tdemo.util.LogUtil;
import com.sunway.l850tdemo.util.TimeUtils;

import java.io.File;
import java.text.SimpleDateFormat;
import java.util.List;
import java.util.logging.SimpleFormatter;

/**
 * 上控/下控  老版本列表
 * */
public class OldVersionListAdapter extends BaseQuickAdapter<File, BaseViewHolder> {

    private int index = -1;

    public OldVersionListAdapter(@Nullable List<File> data) {
        super(R.layout.item_old_version_list, data);
    }

    @Override
    protected void convert(@NonNull BaseViewHolder baseViewHolder, File file) {
        LogUtil.d("OldVersionListAdapter","filePath = "+file.getAbsolutePath());

        ItemOldVersionListBinding binding = ItemOldVersionListBinding.bind(baseViewHolder.itemView);

        String versionCode = getContext().getString(R.string.update_revert_version_code,getCode(file));


        String format = format(file.lastModified());
        String updateTime = getContext().getString(R.string.update_revert_time,format );

        binding.tvCode.setText(versionCode);
        binding.tvTime.setText(updateTime);

        if(baseViewHolder.getAbsoluteAdapterPosition() == index){
            binding.getRoot().setSelected(true);
        }else{
            binding.getRoot().setSelected(false);
        }

        binding.getRoot().setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                index = baseViewHolder.getAbsoluteAdapterPosition();
                notifyDataSetChanged();
            }
        });
    }

    public static String format(long date){
        SimpleDateFormat dateFormat = new SimpleDateFormat("yyyy-MM-dd HH:mm");
        return dateFormat.format(date);
    }

    public File getSelectedFile(){
        if(index>=0 && index <= getData().size()-1){
            return getData().get(index);
        }

        return  null;
    }

    /**
     * 从 upper_firmware_xx.bin 提取版本数字
     * @param file 文件
     * @return 解析到的数字；解析失败返回-1
     */
    public static String getCode(File file){
        String fileName = file.getName();
        if (fileName == null || !fileName.endsWith(".bin")) {
            return "--";
        }
        // 去掉后缀 .bin
        String nameNoSuffix = fileName.substring(0, fileName.lastIndexOf('.'));
        // 找最后一个下划线
        int lastUnderscore = nameNoSuffix.lastIndexOf('_');
        if (lastUnderscore < 0) {
            return "--";
        }
        String numStr = nameNoSuffix.substring(lastUnderscore + 1);
        return numStr;
    }
}
