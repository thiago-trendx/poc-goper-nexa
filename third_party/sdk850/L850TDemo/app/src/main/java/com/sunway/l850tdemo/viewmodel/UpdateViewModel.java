package com.sunway.l850tdemo.viewmodel;


import androidx.annotation.NonNull;
import androidx.lifecycle.MutableLiveData;
import androidx.lifecycle.ViewModel;

import com.sunway.l850tdemo.bean.DownloadProgress;
import com.sunway.l850tdemo.bean.FirmWareVersion;
import com.sunway.l850tdemo.bean.Resource;
import com.sunway.l850tdemo.util.FileManager;
import com.sunway.l850tdemo.util.LogUtil;
import com.sunway.l850tdemo.util.ThreadPoolManager;
import com.sunway.sdk850.base.SerialPortCallback;
import com.sunway.sdk850.base.SerialPortManager;
import com.sunway.sdk850.base.paser.SerialPacket;
import com.sunway.sdk850.port.Cmd;
import com.sunway.sdk850.port.bean.DeviceInfo;
import com.sunway.sdk850.port.bean.SerialPacketType;

import java.io.File;

public class UpdateViewModel extends ViewModel {
    private static final String TAG = "UpdateViewModel====";

    public  MutableLiveData<DeviceInfo> currentLowerVersion = new DistinctLiveData<>();

    public  MutableLiveData<Resource<FirmWareVersion>> checkLowerFirmwareResult = new DistinctLiveData<>();

    public  MutableLiveData<DownloadProgress> downloadLowerProgress = new MutableLiveData<>();

    public void registerCallback(){
        //设置串口监听
        SerialPortManager.getInstance().registerCallback(callback);
    }
    public void unRegisterCallback(){
        //移除串口监听
        SerialPortManager.getInstance().unregisterCallback(callback);
    }

    /** desc： 获取当前下控版本信息
     * create at 2026/3/27 9:48 by liuxiong
     */
    public void getCurrentLowerFirmware(){

        //发送查询下控版本信息指令
        SerialPortManager.getInstance().send(Cmd.quaryDeviceInfo());
    }


    /** desc： 下位机串口数据回调
     * create at 2026/3/3 9:29 by liuxiong
     */
    SerialPortCallback.Simple callback = new SerialPortCallback.Simple(){
        @Override
        public void onDataReceived(@NonNull SerialPacket serialPacket) {
            SerialPacketType type = (SerialPacketType) serialPacket.getType();
            switch (type){
                case DEVICE_INFO: //控制器版本 信息

                    DeviceInfo deviceInfo= (DeviceInfo)serialPacket.getData();
                    LogUtil.d(TAG,"上控版本 信息："+deviceInfo.toString());
                    currentLowerVersion.postValue(deviceInfo);
                    break;
            }

        }
    };

    /**
     * 获取下控新版本
     * */
    public void getLowerControllerVersion(String softwareNum){

        FirmWareVersion firmWareVersion = new FirmWareVersion();
        firmWareVersion.setCode("xxx");
        firmWareVersion.setVersion(41L);
        firmWareVersion.setUrl("http//***");

        checkLowerFirmwareResult.postValue( Resource.success(firmWareVersion));
    }


    /**
     * 模拟下载
     * */
    public void downloadLowerFirmware() {
        String url = checkLowerFirmwareResult.getValue().getData().getUrl();

        ThreadPoolManager.getInstance().execute(()->{
            //拷贝
            File destFile = FileManager.getLowerFirmwareFile("41");
            FileManager.downLower(destFile);

            //
            int progress = 0;
            while (progress <= 100){

                downloadLowerProgress.postValue(DownloadProgress.progress(progress));
                progress ++;
                try {
                    Thread.sleep(30);
                } catch (InterruptedException e) {
                    //
                }
            }

            //下载完成
            downloadLowerProgress.postValue(DownloadProgress.complete(destFile));
        });

    }
}
