package com.sunway.l850tdemo.viewmodel;

import android.os.Handler;
import android.os.HandlerThread;

import androidx.annotation.NonNull;
import androidx.lifecycle.MutableLiveData;
import androidx.lifecycle.ViewModel;

import com.sunway.l850tdemo.UserTrainingConfig;
import com.sunway.l850tdemo.util.LogUtil;
import com.sunway.sdk850.base.SerialPortCallback;
import com.sunway.sdk850.base.SerialPortManager;
import com.sunway.sdk850.base.paser.SerialPacket;
import com.sunway.sdk850.port.Cmd;
import com.sunway.sdk850.port.Contancts;
import com.sunway.sdk850.port.DeviceManager;
import com.sunway.sdk850.port.bean.ClearMode;
import com.sunway.sdk850.port.bean.ControlParams;
import com.sunway.sdk850.port.bean.DeviceInfo;
import com.sunway.sdk850.port.bean.DeviceParams;
import com.sunway.sdk850.port.bean.DeviceStatus;
import com.sunway.sdk850.port.bean.ForceMode;
import com.sunway.sdk850.port.bean.RunState;
import com.sunway.sdk850.port.bean.SerialPacketType;

import lombok.Getter;
import lombok.Setter;

public class RunViewModel extends ViewModel {
    private static final String TAG = "MainViewModel ====";

    /**
     * 指令轮询间隔
     * */
    private static final long LOOP_SPACE = 200L;

    /** 串口连接状态 0 未连接 ， 1 连接中  ，2 已连接 ，3 连接失败*/
    public MutableLiveData<Integer> portState = new MutableLiveData<>(0);
    /** 控制版本 */
    public MutableLiveData<String> controlVerison = new MutableLiveData<>("--");
    /** 控制器软件料号 */
    public MutableLiveData<String> controlSoftNum = new MutableLiveData<>("--");

    /** 次数 */
    public MutableLiveData<Integer> pullNum = new MutableLiveData<>(0);
    /** 速度 */
    public MutableLiveData<Double> speed = new MutableLiveData<>(0.0);
    /** 行程 */
    public MutableLiveData<Integer> distance = new MutableLiveData<>(0);
    /** 错误码 */
    public MutableLiveData<Integer> errorCode = new MutableLiveData<>(0);
    /** 温度 */
    public MutableLiveData<Double> temperature = new MutableLiveData<>(0.0);
    /** 实时力 */
    public MutableLiveData<Integer> realForce = new MutableLiveData<>(0);
    /** 升降电机状态  */
    public MutableLiveData<Integer> liftMotorStatus = new MutableLiveData<>(0);

    /** 阻力模式*/
    public MutableLiveData<ForceMode> forceMode = new MutableLiveData<>(ForceMode.STANDARD);

    /** 运行状态
     *     RUNNING,  //运动状态   开始运动到运动结束一直发送次状态
     *     STOP,  //停止状态   发送此指令可使电机进入基础力模式，此时发送除启动命令以外的指令都是无效的
     *     ORIGIN_RESET, //起点重置   发送此指令会将里程重新清零,旨在调整把手高度的时候进行一次起点重置
     *     ERROR_RESTORE  //故障复位   当驱动器故障时，上位机发送该指令，复位驱动器
     * */
    public MutableLiveData<RunState>  runStatus= new MutableLiveData<>(RunState.STOP);

    /** 运行时间 */
    public MutableLiveData<Long>  runTime= new MutableLiveData<>(0L);

    /** 调节电机倒计时 */
    public MutableLiveData<Integer>  downTime= new MutableLiveData<>(0);

    /**
     * 用户训练配置,实际项目从网络获取
     * */
    @Getter @Setter
    private UserTrainingConfig userConfig = new UserTrainingConfig();

    @Getter
    private boolean isInited = false;

    private DeviceParams deviceParams = DeviceManager.getInstance().getDeviceParams();

    /**
     * 用于循环处理的handler  时间更新、运动指令循环发送等
     */
    private Handler loopHandler;
    private HandlerThread handlerThread;

    private InitCallback initCallback;

    /** 升降电机是否正在运动 */
    private boolean liftMotorIsRun = false;



    public interface InitCallback{
        void onInited();
    }

    /**
     * 初始化
     * */
    public void init(InitCallback initCallback){
        this.initCallback = initCallback;
        LogUtil.d(TAG,"init ");

        //开启loop循环
        handlerThread = new HandlerThread("循环");
        handlerThread.start();
        loopHandler = new Handler(handlerThread.getLooper());

        //注册串口监听
        SerialPortManager.getInstance().registerCallback(serialPortCallback);

        //检查串口是否已连接
        boolean connected = SerialPortManager.getInstance().isConnected();
        if(connected){
            //初始化完成
            inited();
        }else{
            SerialPortManager.getInstance().autoConnect();
            portState.postValue(1); //连接中
        }
    }

    private void inited(){
        //初始化设备信息
        initControlInfo();
        //已连接
        portState.postValue(2);

        //开始指令循环
        loopHandler.post(cmdLoopRunnable);
        //开始计时
        loopHandler.post(timeRunnable);

        //设置用户配置
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setForce( userConfig.getForce());
        controlParams.setCentripetal( userConfig.getCentripetal());
        controlParams.setCentrifugal( userConfig.getCentrifugal());
        controlParams.setVelocity( userConfig.getVelocity());
        controlParams.setElastic( userConfig.getElastic() );

        //设置电机位置
        setMotorPosition(userConfig.getMotorPosition1() , userConfig.getMotorPosition2());

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

        //检查运动状态，如果处于运动中，就最后发一次停止
        if(runStatus.getValue() == RunState.RUNNING){
            ControlParams controlParams = DeviceManager.getInstance().getControlParams();
            controlParams.setRun(RunState.STOP);
            SerialPortManager.getInstance().send(Cmd.control(controlParams));
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
     * 初始化设备信息
     * */
    private void initControlInfo() {
        LogUtil.d(TAG,"initControlInfo ");
        DeviceInfo deviceInfo = DeviceManager.getInstance().getDeviceInfo();
        controlVerison.postValue(deviceInfo.getVersionCode()+"");
        controlSoftNum.postValue(deviceInfo.getSoftwareNum());
    }

    /**
     * 处理串口接收数据
     * */
    private void handleReciveData(SerialPacket serialPacket) {
        SerialPacketType packetType = (SerialPacketType) serialPacket.getType();
        switch (packetType){
            case DEVICE_INFO: //控制器信息
                DeviceInfo deviceInfo = (DeviceInfo) serialPacket.getData();
                DeviceManager.getInstance().setDeviceInfo(deviceInfo);
                break;

            case SEND_PARAMS: //下发参数返回
                //初始化完成
                inited();
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
        //运动状态
        runStatus.postValue(status.getRun());
        //阻力模式
        forceMode.postValue(status.getMode());
        //设置阻力
        //force.postValue(status.getForce());

        //次数
        pullNum.postValue(status.getPullNum());
        //拉绳速度
        speed.postValue(status.getSpeed());
        //行程
        distance.postValue(status.getDistance());
        //错误码
        errorCode.postValue(status.getErrorCode());
        //ntc 温度
        temperature.postValue(status.getTemperature());
        //实时力
        realForce.postValue(status.getRealForce());
        //升降电机状态
        liftMotorStatus.postValue(status.getLiftMotorStatus());

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
     * 升降电机调节完成
     * */
    private void liftMotorCompelete() {
        downTime.postValue(0);

        //重新开始运动
        start();
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

    /**
     * 开始计时轮询
     * */
    private Runnable timeRunnable = new Runnable() {
        @Override
        public void run() {
            runTime.postValue(runTime.getValue() + 1000);

            if(loopHandler!=null){ //非常小的概率会空指针
                loopHandler.postDelayed(this,1000L);
            }
        }
    };

    /**
     * 升降电机倒计时
     * */
    private Runnable motorDownTimeRunnable = new Runnable() {
        @Override
        public void run() {
            if(downTime.getValue() > 0){
                downTime.postValue(downTime.getValue() - 1);
                loopHandler.postDelayed(this,1000L);

            }else{

                downTime.postValue(0);
            }
            LogUtil.d(TAG, "downTime= "+ downTime.getValue());
        }
    };


    /**
     * 开始运动
     * */
    public void start() {
        LogUtil.d(TAG,"start ");

        //开始运动
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setRun(RunState.RUNNING);
    }

    /**
     * 停止运动
     * */
    public void stop() {
        LogUtil.d(TAG,"stop ");

        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setRun(RunState.STOP);
    }

    /**
     * 原点重置
     * */
    public void originReset(){
        LogUtil.d(TAG,"originReset ");
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();

        //设置重置原点
        controlParams.setNeedSetOrigin(true);

        //原点重置时，清除一下运动数据
        controlParams.setClearMode(ClearMode.ALL);
    }

    /**
     * 错误复位
     * */
    public void restore(){
        LogUtil.d(TAG,"restore ");
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();

        //设置错误复位
        controlParams.setNeedErrorRestor(true);

        controlParams.setRun(RunState.ERROR_RESTORE);
    }

    /**
     *  清除数据
     *     FIRST,   //清除电机1 次数
     *     SECOND,  //清除电机2 次数
     *     ALL,      //清除所有电机 次数
     *     NONE  //不清除 次数
     * */
    public void clearData(){
        LogUtil.d(TAG,"clearData ");
        /**
         *  清除数据指令不能一直发，这里通过克隆的方式规避
         **/
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setClearMode(ClearMode.ALL);
    }

    /**
     * 切换拉力模式
     * */
    public void switchMode(ForceMode forceMode) {
        LogUtil.d(TAG,"switchMode :"+ forceMode);
        //this.forceMode.postValue(forceMode);

        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setMode(forceMode);
    }

    /**
     * 设置阻力
     * */
    public void setForce(int force){
        LogUtil.d(TAG,"setForce :"+ force);

        userConfig.setForce(force);
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setForce(force);
    }

    /**
     * 设置向心力系数
     * */
    public void setCentripetal(int centripetal){
        LogUtil.d(TAG,"setCentripetal :"+ centripetal);

        userConfig.setCentripetal(centripetal);
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setCentripetal(centripetal);
    }


    /**
     * 设置离心力系数
     * */
    public void setCentrifugal(int centrifugal){
        LogUtil.d(TAG,"setCentrifugal :"+ centrifugal);

        userConfig.setCentrifugal(centrifugal);
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setCentrifugal(centrifugal);
    }

    /**
     * 设置等速系数
     * */
    public void setVelocity(int velocity){
        LogUtil.d(TAG,"setVelocity :"+ velocity);

        userConfig.setVelocity(velocity);
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setVelocity(velocity);
    }

    /**
     * 设置弹力系数
     * */
    public void setElastic(int elastic){
        LogUtil.d(TAG,"setElastic :"+ elastic);

        userConfig.setElastic(elastic);
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setElastic(elastic);
    }

    /**
     * 设置最大弹力：最大弹力 <= （最大拉力 - 当前设置拉力）。
     * 默认值是50kg。
     * 实际拉力 = 当前设置拉力 + 最大弹力 * 当前行程/最大行程
     * */
    public void setMaxElastic(int maxElastic){
        LogUtil.d(TAG,"setMaxElastic :"+ maxElastic);

        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setMaxElectric(maxElastic);
    }

    /**
     * 调节升降电机，一般在进入运动页面时，同步座椅和悬臂调用
     * */
    public void setMotorPosition(int position1 , int position2){
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        if(position1 == controlParams.getMotorPosition1() &&  position2 == controlParams.getMotorPosition2()){
            LogUtil.d(TAG, "电机位置未发生改变");
            return;
        }

        LogUtil.d(TAG,"setMotorPosition :"+ position1 +"  "+position2);

        //开始倒计时
        int increment1 = Math.abs(position1 - userConfig.getMotorPosition1()); //增量
        int downTime1 = (int) (4 + increment1 * Contancts.MOTOR_LONG_TIME);

        int increment2 = Math.abs(position2 - userConfig.getMotorPosition2()); //增量
        int downTime2 = (int) (4 + increment2 * Contancts.MOTOR_LONG_TIME);

        this.downTime.postValue(Math.max(downTime1,downTime2));
        loopHandler.postDelayed(motorDownTimeRunnable,100);

        //调剂升降电机，需要停止运动
        stop();

        //设置电机位置
        controlParams.setMotorPosition1(position1);
        controlParams.setMotorPosition2(position2);

        userConfig.setMotorPosition1(position1);
        userConfig.setMotorPosition2(position2);
    }


    /**
     * 调节升降电机1
     * */
    public void setMotor1Position(int position){
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        if(position == controlParams.getMotorPosition1()){
            LogUtil.d(TAG, "电机1位置未发生改变");
            return;
        }
        LogUtil.d(TAG,"setMotor1Position :"+ position);

        //调剂升降电机，需要停止运动
        stop();

        //开始倒计时
        int increment = Math.abs(position - userConfig.getMotorPosition1()); //增量
        int downTime = (int) (4 + increment * Contancts.MOTOR_LONG_TIME);
        this.downTime.postValue(downTime);
        loopHandler.postDelayed(motorDownTimeRunnable,100);

        //设置电机位置
        controlParams.setMotorPosition1(position);


        userConfig.setMotorPosition1(position);
    }

    /**
     * 调节升降电机1
     * */
    public void setMotor2Position(int position){
        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        if(position == controlParams.getMotorPosition2()){
            LogUtil.d(TAG, "电机2位置未发生改变");
            return;
        }
        LogUtil.d(TAG,"setMotor2Position :"+ position);


        //调剂升降电机，需要停止运动
        stop();

        //开始倒计时
        int increment = Math.abs(position - userConfig.getMotorPosition2()); //增量
        int downTime = (int) (4 + increment * Contancts.MOTOR_LONG_TIME);
        this.downTime.postValue(downTime);
        loopHandler.postDelayed(motorDownTimeRunnable,100);

        //设置电机位置
        controlParams.setMotorPosition2(position);

        userConfig.setMotorPosition2(position);
    }
}
