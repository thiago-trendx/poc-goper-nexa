package com.sunway.l850tdemo;

import android.app.Application;
import android.content.Context;

import com.sunway.l850tdemo.util.ToastUtil;
import com.sunway.sdk850.port.DeviceManager;

public class App extends Application {

    private static Context appContext;

    @Override
    public void onCreate() {
        super.onCreate();
        appContext = getApplicationContext();
        //
        ToastUtil.init(appContext);
        //初始化参数
        DeviceManager.getInstance().init(this,"serial_port");
    }

    public static Context getContext(){
        return appContext;
    }
}
