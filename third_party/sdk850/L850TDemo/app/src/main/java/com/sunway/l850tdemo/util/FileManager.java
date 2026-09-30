package com.sunway.l850tdemo.util;

import android.content.Context;
import android.os.Build;
import android.os.Environment;
import android.text.TextUtils;
import android.util.Log;


import com.sunway.l850tdemo.App;

import java.io.File;
import java.io.FileFilter;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;

/** desc： 文件管理
 * create at 2026/3/28 10:11 by liuxiong
 */
public class FileManager {

    private static final String TAG = "FileManager";
    public static final String LOWER_FIRMWARE_NAME = "lower_firmware_%s.bin";
    public static final String OLD_LOWER = "old_lower";

    /**
     * 获取下载目录（带回退）
     * 桌面应用场景下，外部存储可能还未挂载，此时回退到内部存储
     */
    public static File getDownloadDir() {
        Context ctx = App.getContext();
        if (ctx == null) {
            Log.w(TAG, "App context is null, cannot get download dir");
            return null;
        }

        // 1. 先尝试外部存储（仅在已挂载时）
        if (isExternalStorageAvailable()) {
            File dir = ctx.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS);
            if (dir != null) {
                if (!dir.exists()) dir.mkdirs();
                return dir;
            }
        }

        // 2. 回退到内部存储 files/Downloads
        File fallback = new File(ctx.getFilesDir(), "Downloads");
        if (!fallback.exists()) fallback.mkdirs();
        Log.w(TAG, "External storage unavailable, fallback to: " + fallback.getAbsolutePath());
        return fallback;
    }

    /**
     * 检查外部存储是否可用
     */
    public static boolean isExternalStorageAvailable() {
        String state = Environment.getExternalStorageState();
        return Environment.MEDIA_MOUNTED.equals(state);
    }

    /**
     * 安全构建文件路径
     */
    private static File safeFile(File dir, String name) {
        if (dir == null || TextUtils.isEmpty(name)) return null;
        return new File(dir, name);
    }

    /** 下控程序下载文件 */
    public static File getLowerFirmwareFile(String versionCode) {

        String fileName = String.format(LOWER_FIRMWARE_NAME, versionCode);

        return safeFile(getDownloadDir(), fileName);
    }

    public static String getFileName(String filePath){
        Path path = null;
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            path = Paths.get(filePath);
            return  path.getFileName().toString();
        }

        return new File(filePath).getName();
    }


    /**
     * 移动文件（将 originFile 移动到 targetFile 位置）
     * 如果目标文件已存在，则覆盖；如果目标父目录不存在，则自动创建。
     */
    public static void moveFile(File originFile, File targetFile) throws IOException {
        // 1. 校验源文件是否存在
        if (originFile == null || !originFile.exists()) {
            throw new IllegalArgumentException("源文件不存在或为空");
        }
        if (targetFile == null) {
            throw new IllegalArgumentException("目标文件不能为空");
        }

        // 2. 确保目标文件的父目录存在（否则移动会报 NoSuchFileException）
        File parentDir = targetFile.getParentFile();
        if (parentDir != null && !parentDir.exists()) {
            parentDir.mkdirs(); // 创建父目录
        }

        // 3. 执行移动操作（REPLACE_EXISTING 表示覆盖同名文件）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Files.move(originFile.toPath(), targetFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
        }
    }

    /**
     * 移动文件
     * */
    public static void moveFile(File originFile ){
        try {
            if(!originFile.exists()){
                LogUtil.d(TAG,"源文件不存在");
            }

            //拼接文件地址
            String targetFilePath = "";
            String fileName = originFile.getName();

            targetFilePath = OLD_LOWER + "/" + fileName;


            File targetFile = new File(getDownloadDir() , targetFilePath);

            moveFile(originFile, targetFile);
        } catch (IOException e) {
            LogUtil.d(TAG, "移动文件异常："+e.getMessage());
        }
    }

    /**
     * 获取下控旧版本列表
     * */
    public static File[] getLowerOldVersion(){
        return  getOldVersion();
    }

    /**
     * 获取旧版本列表
     * */
    private  static File[] getOldVersion(){
        String targetFilePath = OLD_LOWER;

        File targetFile = new File(getDownloadDir() , targetFilePath);
        if(!targetFile.exists()){
            LogUtil.d(TAG,"目标文件夹不存在");
            return null;
        }

        return targetFile.listFiles(new FileFilter() {
            @Override
            public boolean accept(File pathname) {
                return pathname.isFile();
            }
        });
    }

    public static void copyLowerFromAsset(){
        String assetName = "lower_firmware_41.bin";
        File destFile = new File(getDownloadDir() , OLD_LOWER+"/" + assetName);
        if(destFile.exists() && destFile.length() > 1024){
            LogUtil.d(TAG,"文件 "+assetName+" 已存在 filepath="+ destFile.getAbsolutePath());
            return;
        }
        copyAssetToFile(App.getContext(),assetName,destFile);
    }

    private static void copyAssetToFile(Context context, String assetName, File destFile){
        try {
            // 2. 确保目标文件的父目录存在（否则移动会报 NoSuchFileException）
            File parentDir = destFile.getParentFile();
            if (parentDir != null && !parentDir.exists()) {
                parentDir.mkdirs(); // 创建父目录
            }

            InputStream in = context.getAssets().open(assetName);
            FileOutputStream out = new FileOutputStream(destFile);
            byte[] buffer = new byte[8192];
            int read;
            while ((read = in.read(buffer)) != -1) {
                out.write(buffer, 0, read);
            }
            out.flush();
        }catch (IOException e){
            LogUtil.d(TAG,"从 assets 拷贝 "+assetName+" 出错：" + e.getMessage());
        }
    }

    public static void downLower(File destFile) {
        if(destFile == null){
            return;
        }

        String assetName = "lower_firmware_41.bin";
        if(destFile.exists() && destFile.length() > 1024){
            LogUtil.d(TAG,"文件 "+assetName+" 已存在 filepath="+ destFile.getAbsolutePath());
            return;
        }
        copyAssetToFile(App.getContext(),assetName,destFile);
    }
}