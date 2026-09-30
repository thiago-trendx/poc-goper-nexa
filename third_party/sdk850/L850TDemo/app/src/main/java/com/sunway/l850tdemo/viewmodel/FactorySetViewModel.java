package com.sunway.l850tdemo.viewmodel;

import android.os.Handler;
import android.os.HandlerThread;

import androidx.annotation.NonNull;
import androidx.lifecycle.MutableLiveData;
import androidx.lifecycle.ViewModel;

import com.sunway.l850tdemo.util.LogUtil;
import com.sunway.l850tdemo.util.ToastUtil;
import com.sunway.sdk850.base.SerialPortCallback;
import com.sunway.sdk850.base.SerialPortManager;
import com.sunway.sdk850.base.paser.SerialPacket;
import com.sunway.sdk850.port.Cmd;
import com.sunway.sdk850.port.DeviceManager;
import com.sunway.sdk850.port.bean.ControlParams;
import com.sunway.sdk850.port.bean.DeviceParams;
import com.sunway.sdk850.port.bean.DeviceStatus;
import com.sunway.sdk850.port.bean.SerialPacketType;

import lombok.Getter;

public class FactorySetViewModel  extends ViewModel {

    private static final String TAG = "MainViewModel ====";

    /**
     * 指令轮询间隔
     * */
    private static final long LOOP_SPACE = 200L;

    /** 串口连接状态 0 未连接 ， 1 连接中  ，2 已连接 ，3 连接失败*/
    public MutableLiveData<Integer> portState = new DistinctLiveData<>(0);

    /** 错误码 */
    public MutableLiveData<Integer> errorCode = new DistinctLiveData<>(0);

    /** 最小阻力  */
    public MutableLiveData<Integer> minForce = new DistinctLiveData<>(0);
    /** 最大阻力  */
    public MutableLiveData<Integer> maxForce = new DistinctLiveData<>(0);
    /** 空闲阻力  */
    public MutableLiveData<Integer> inactiveForce = new DistinctLiveData<>(0);
    /** 最大拉绳长度  */
    public MutableLiveData<Integer> maxLength = new DistinctLiveData<>(0);
    /** 额定转速  */
    public MutableLiveData<Integer> ratedSpeed = new DistinctLiveData<>(0);
    /** 绳轨直径  */
    public MutableLiveData<Integer> ropeGuideDiameter = new DistinctLiveData<>(0);
    /** 原点最小距离  */
    public MutableLiveData<Integer> minDistance = new DistinctLiveData<>(0);
    /** 原点最大距离  */
    public MutableLiveData<Integer> maxDistance = new DistinctLiveData<>(0);
    /** 等速系数范围  */
    public MutableLiveData<Integer> velocityRange = new DistinctLiveData<>(0);
    /** 力矩周期系数  */
    public MutableLiveData<Integer> torqueCycle = new DistinctLiveData<>(0);
    /** 力矩系数  */
    public MutableLiveData<Integer> torque = new DistinctLiveData<>(0);

    private DeviceParams deviceParams = DeviceManager.getInstance().getDeviceParams();

    /**
     * 用于循环处理的handler  时间更新、运动指令循环发送等
     */
    private Handler loopHandler;
    private HandlerThread handlerThread;

    @Getter
    private boolean isInited = false;

    @Getter
    private boolean isChecking = false;


    /** 自检倒计时 */
    public MutableLiveData<Integer>  downTime= new MutableLiveData<>(0);

    private InitCallback initCallback;

    /** 升降电机是否正在运动 */
    private boolean liftMotorIsRun = false;

    public interface InitCallback{
        void onInited();
    }

    public void init(){
        //自动连接
        SerialPortManager.getInstance().registerCallback(serialPortCallback);

        //开启loop循环
        handlerThread = new HandlerThread("循环");
        handlerThread.start();
        loopHandler = new Handler(handlerThread.getLooper());

        if(!SerialPortManager.getInstance().isConnected()){
            SerialPortManager.getInstance().autoConnect();
        }else{
            inited();
        }
    }

    private void inited(){

        //已连接
        portState.postValue(2);

        //开始指令循环
        loopHandler.post(cmdLoopRunnable);

        //初始化值
        minForce.postValue(deviceParams.getMinForce());
        maxForce.postValue(deviceParams.getMaxForce());
        inactiveForce.postValue(deviceParams.getInactiveForce());
        maxLength.postValue(deviceParams.getMaxLength());
        ratedSpeed.postValue(deviceParams.getRatedSpeed());
        ropeGuideDiameter.postValue(deviceParams.getRopeGuideDiameter());
        minDistance.postValue(deviceParams.getOrginMinDistance());
        maxDistance.postValue(deviceParams.getOrginMaxDistance());
        maxDistance.postValue(deviceParams.getOrginMaxDistance());
        velocityRange.postValue(deviceParams.getVelocityRange());
        torqueCycle.postValue(deviceParams.getTorqueVariationCycle());
        torque.postValue(deviceParams.getTorqueCoefficient());

        if(initCallback!=null){
            initCallback.onInited();
        }

        isInited = true;
    }


    /**
     * 反初始化
     * */
    public void unInit(){
        isInited = false;

        LogUtil.d(TAG,"unInit ");
        if(loopHandler!=null){
            loopHandler.removeCallbacksAndMessages(null);
            loopHandler = null;
        }

        if(handlerThread !=null ){
            handlerThread.quitSafely();
            handlerThread = null;
        }
    }

    /**
     * 串口监听
     * */
    SerialPortCallback serialPortCallback = new SerialPortCallback.Simple(){

        @Override
        public void onConnectFailed(@NonNull String portPath, @NonNull String reason) {
            LogUtil.d(TAG,"onConnectFailed ");
            portState.postValue(3); //连接失败
            errorCode.postValue(0x01); //串口连接失败 E-01
        }

        @Override
        public void onConnected(@NonNull String portPath) {
            LogUtil.d(TAG,"onConnected ");
            //发送下发参数指令
            SerialPortManager.getInstance().send( Cmd.sendParams(deviceParams) );
        }

        @Override
        public void onDisconnected(@NonNull String portPath) {
            LogUtil.d(TAG,"onDisconnected ");
            portState.postValue(0); //未连接
        }
        @Override
        public void onDataReceived(@NonNull SerialPacket serialPacket) {
            //处理串口接收数据
            handleReciveData(serialPacket);
        }
    };

    /**
     * 处理串口接收数据
     * */
    private void handleReciveData(SerialPacket serialPacket) {
        SerialPacketType packetType = (SerialPacketType) serialPacket.getType();
        switch (packetType){
            case SEND_PARAMS: //下发参数返回
                if(!isInited){
                    //初始化完成
                    inited();
                }
                DeviceParams backParams = (DeviceParams) serialPacket.getData();
                minForce.postValue( backParams.getMinForce());
                maxForce.postValue( backParams.getMaxForce());
                inactiveForce.postValue( backParams.getInactiveForce());
                maxLength.postValue( backParams.getMaxLength());
                ratedSpeed.postValue( backParams.getRatedSpeed());
                ropeGuideDiameter.postValue( backParams.getRopeGuideDiameter());
                minDistance.postValue( backParams.getOrginMinDistance());
                maxDistance.postValue( backParams.getOrginMaxDistance());
                velocityRange.postValue( backParams.getVelocityRange());
                torqueCycle.postValue( backParams.getTorqueVariationCycle());
                torque.postValue( backParams.getTorqueCoefficient());


                break;

            case CONTROL: //控制指令 ，返回运动状态数据
                DeviceStatus status = (DeviceStatus) serialPacket.getData();
                LogUtil.d(TAG,status.toString());
                handleDeviceStatus(status);
                break;
        }
    }

    /**
     * 处理运动数据
     * */
    private void handleDeviceStatus(DeviceStatus status) {
        if(status.getLiftMotorStatus() == 0x01 || status.getLiftMotorStatus() == 0x02){
            //记录调节开始
            liftMotorIsRun = true;
        }else{
            //先开始，后停止，代表调节完成
            if(liftMotorIsRun){
                liftMotorCompelete();
            }
            liftMotorIsRun = false;
        }
    }


    /**
     * 升降电机自检完成
     * */
    private void liftMotorCompelete() {
        isChecking = false ;

        downTime.postValue(0);
        //停止指令轮询
        loopHandler.removeCallbacks(motorDownTimeRunnable);
    }


    /**
     * 开始指令轮询
     * */
    private Runnable cmdLoopRunnable = new Runnable() {
        @Override
        public void run() {

            ControlParams controlParams = DeviceManager.getInstance().getControlParams();
            SerialPortManager.getInstance().send( Cmd.control(controlParams) );

            if(loopHandler!=null){ //非常小的概率会空指针
                loopHandler.postDelayed(this,LOOP_SPACE);
            }
        }
    };

    private Runnable motorDownTimeRunnable = new Runnable() {
        @Override
        public void run() {
            if(downTime.getValue() > 0){
                downTime.postValue(downTime.getValue() - 1);
                loopHandler.postDelayed(this,1000L);

            }else{
                //升降电机自检完成
                liftMotorCompelete();
            }
            LogUtil.d(TAG, "downTime = "+ downTime.getValue());
        }
    };


    public void selfCheck(){
        if(!SerialPortManager.getInstance().isConnected()){
            ToastUtil.show("串口未连接");
            downTime.postValue(0);
            return;
        }

        isChecking = true;

        //设置开始自检
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setMotorSelfCheck( true );

        //自检倒计时
        downTime.postValue(130);
        loopHandler.postDelayed(motorDownTimeRunnable,100);
    }

    /**
     * 设置最小阻力
     * */
    public void  setMinForce(int minForce){
        deviceParams.setMinForce(minForce);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置最大阻力
     * */
    public void  setMaxForce(int maxForce){
        deviceParams.setMaxForce(maxForce);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置空闲拉力
     * */
    public void setInactiveForce(int inactiveForce){
        deviceParams.setInactiveForce(inactiveForce);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置最大行程
     * */
    public void setMaxLength(int maxLength){
        deviceParams.setMaxLength(maxLength);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置额定转速
     * */
    public void setRatedSpeed(int rateSpeed){
        deviceParams.setRatedSpeed(rateSpeed);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置绳轨直径
     * */
    public void setRopeGuideDiameter(int ropeGuideDiameter){
        deviceParams.setRopeGuideDiameter(ropeGuideDiameter);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置原点最小距离
     * */
    public void setOrginMinDistance(int minDistance){
        deviceParams.setOrginMinDistance(minDistance);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置原点最大距离
     * */
    public void setOrginMaxDistance(int maxDistance){
        deviceParams.setOrginMaxDistance(maxDistance);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置等速系数范围（最大值）
     * */
    public void setVelocityRange(int velocityRange){
        deviceParams.setVelocityRange(velocityRange);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置力矩周期系数
     * */
    public void setTorqueVariationCycle(int torqueVariationCycle){
        deviceParams.setTorqueVariationCycle(torqueVariationCycle);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

    /**
     * 设置力矩系数
     * */
    public void setTorqueCoefficient(int torqueCoefficient){
        deviceParams.setTorqueCoefficient(torqueCoefficient);
        SerialPortManager.getInstance().send(Cmd.sendParams(deviceParams));
    }

}
