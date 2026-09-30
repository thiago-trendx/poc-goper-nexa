package com.sunway.l850tdemo.activity;

import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import com.sunway.l850tdemo.databinding.ActivityWelcomeBinding;
import com.sunway.l850tdemo.util.LogUtil;
import com.sunway.sdk850.base.SerialPortCallback;
import com.sunway.sdk850.base.SerialPortConfig;
import com.sunway.sdk850.base.SerialPortManager;
import com.sunway.sdk850.base.paser.SerialPacket;
import com.sunway.sdk850.port.Cmd;
import com.sunway.sdk850.port.DeviceManager;
import com.sunway.sdk850.port.bean.DeviceParams;
import com.sunway.sdk850.port.bean.SerialPacketType;


public class WelcomeActivity extends BaseActivity {

    private ActivityWelcomeBinding mBinding;

    private Handler mHandler = new Handler(Looper.getMainLooper());

    private int count = 0;


    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        mBinding = ActivityWelcomeBinding.inflate(getLayoutInflater());
        setContentView(mBinding.getRoot());
        mHandler.post(runnable);

        connectPort();

        mBinding.btnTraning.setOnClickListener(v -> {
            Intent intent = new Intent(mActivity, TrainingActivity.class);
            startActivity(intent);
        });

        mBinding.btnFactory.setOnClickListener(v -> {
            Intent intent = new Intent(mActivity, FactoryActivity.class);
            startActivity(intent);
        });

        mBinding.btnUpdate.setOnClickListener(v -> {
            Intent intent = new Intent(mActivity, UpdateLowerActivity.class);
            startActivity(intent);
        });
    }

    private void connectPort() {
        //打开日志开关（默认是打开的）
        SerialPortConfig config = SerialPortManager.getInstance().getConfig();
        config
                .setBaudRate(115200) //设置波特率
                .setCmd(new Cmd())  //设置指令构建类实例，必须实现ICmd 接口
                .setSendInterval(50)  //设置发送指令间隔
                .setTestTime(500)  //设置握手指令超时时间
                .setLogEnable(true); //设置是否打开入职输出

        SerialPortManager.getInstance().getConfig().setLogEnable(true);
        //注册回调
        SerialPortManager.getInstance().registerCallback(callback);
        //开始连接
        SerialPortManager.getInstance().autoConnect();
    }

    /** 串口回调 */
    SerialPortCallback callback = new SerialPortCallback.Simple(){
        @Override
        public void onConnectFailed(@NonNull String portPath, @NonNull String reason) {
            LogUtil.d(tag,"串口连接失败："+reason);
        }

        @Override
        public void onDisconnected(@NonNull String portPath) {
            super.onDisconnected(portPath);
        }

        @Override
        public void onConnected(@NonNull String portPath) {
            LogUtil.d(tag,"串口已连接");

            //参数下发
            DeviceParams deviceParams = DeviceManager.getInstance().getDeviceParams();
            byte[] cmd = Cmd.sendParams(deviceParams);
            SerialPortManager.getInstance().send(cmd);
        }

        @Override
        public void onDataReceived(@NonNull SerialPacket serialPacket) {
            SerialPacketType type = (SerialPacketType) serialPacket.getType();
            if(type == SerialPacketType.SEND_PARAMS){
                DeviceParams data = (DeviceParams) serialPacket.getData();
                LogUtil.d("====",data.toString());
            }
        }
    };

    @Override
    protected void onDestroy() {
        super.onDestroy();
        //取消注册回调
        SerialPortManager.getInstance().unregisterCallback(callback);
    }

    private Runnable runnable = new Runnable() {
        @Override
        public void run() {
            if( count< 40 ){
                count++;
                mHandler.postDelayed(this,50);
                int progress = count*100/40 ;
                mBinding.pbDownload.setProgress(progress);

            }else{
                mBinding.clsLuanch.setVisibility(View.GONE);
                mBinding.lltBtns.setVisibility(View.VISIBLE);
            }
        }
    };
}
