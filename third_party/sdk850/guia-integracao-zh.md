# 850 SDK 接入文档

## 1、简介

本sdk 封装了850 项目APP 和 控制器之间的串口通信功能，使用者只需要关注自身业务逻辑，与控制器之间的通信通过直接调用sdk中的API 实现，本SDK 对如下功能进行了封装。

- 自动扫描所有串口，并对所有串口逐个进行通信连接尝试，直到找到能正常通信的串口为止；

- 对所有指令进行封装，使用只需要修改对应参数，然后生成指令发送即可；

- 发送线程和读取线程都是独立子线程，并且发送线程内部持有**无界、非阻塞、线程安全**的指令队列，无需担心指令阻塞。

- 串口回调自动切换到主线程

- 自动保存（SharePrefrence）设备相关的参数配置，如串口地址、最大拉力、最小拉力、升降电机位置等，使用时无需关注。

## 2、集成

### 2.1、将arr包加入项目

- 将arr包放入 app/libs 文件夹

- 在build.gradle.kts 中添加依赖

```kotlin
dependencies {

    implementation(files("libs/sdk850-release.aar")
}
```

### 2.2、初始化

1. 在 Application 的 onCreate 中调用 init

```java
//初始化参数 serial_port 是shareprefrence 文件的名字
DeviceManager.getInstance().init(this,"serial_port");
```

### 2.3、参数配置

在项目启动时配置参数,也可在任意地方更改配置

1. 可以配置串口相关的参数 波特率、串口地址、握手指令、日志开关等；

2. 850 可直接使用默认配置，只需要关注是否需要打印日志。

```java
 SerialPortConfig config = SerialPortManager.getInstance().getConfig();
        config
                .setBaudRate(115200) //设置波特率
                .setCmd(new Cmd())  //设置指令构建类实例，必须实现ICmd 接口
                .setSendInterval(50)  //设置发送指令间隔
                .setTestTime(500)  //设置握手指令超时时间
                .setLogEnable(true); //设置是否打开入职输出
```

### 2.4、注册串口监听

1. 可以在任何需要监听串口数据的地方注册串口监听, sdk 会回调以下状态和数据
- onConnectFailed  连接失败

- onConnected 连接成功

- onError 错误

- onDisconnected 断开连接

- onDataSent  发送数据监听 - 是否发送成功

- onDataReceived 串口返回数据，回调的是解析成JavaBean 数据，封装在SerialPacket 内

示例：

```java
 //注册回调
 SerialPortManager.getInstance().registerCallback(callback);

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
```

2、取消注册

```java
//取消注册回调
SerialPortManager.getInstance().unregisterCallback(callback);
```

> 记得注册和反注册需要意义对应

### 2.5、连接串口

1、连接

- autoConnect 方法内部会自动走 扫描串口 => 遍历尝试串口（通过握手指令验证） => 找出可用串口 => 连接串口 => 检查通信（通过握手指令验证 => 回调连接成功）

- 如果所有串口都无法通信，会回调onConnectFailed

```java
//开始连接
SerialPortManager.getInstance().autoConnect();
```

2、断开连接

```java
//开始连接
SerialPortManager.getInstance().disConnect();
```

3、串口重连

```java
//开始连接
SerialPortManager.getInstance().reConnect();
```

## 3、数据解析

- 串口数据会在解析后通过SerialPortCallback 回调，可以根据类型来判断返回数据类型

- DEVICE_INFO  控制器版本信息

- SEND_PARAMS 是下发参数指令的返回

- CONTROL  控制指令返回，返回的是运动状态数据

SDK 在解析串口数据时，会自动将 **控制器版本信息**、**下发参数返回**保存到DeviceManager，需要时可随时提取。

```java
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
```

运动数据解析示例

```java
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
```

## 4、指令发送

控制器遵循 APP 下发  和 控制器回复 一对一 原则，只有APP发送一条指令，控制器才会回复一条指令，因此，控制指令（CONTROL）需要轮询，轮询间隔建议为200ms。

### 4.1、升降电机自检

升降电机自检：即升降电机会以当前位置为起点，先后运动到最长行程和最短行程，控制器会记录升降电机的行程范围。

- 升降电机自检发送的是控制指令

- 发送控制指令后需要一直轮询状态

```java
//设置开始自检
ControlParams controlParams = DeviceManager.getInstance().getControlParams();
controlParams.setMotorSelfCheck( true );

//自检倒计时
downTime.postValue(130);
loopHandler.postDelayed(motorDownTimeRunnable,100);
```

指令轮询示例：

```java
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
```

- 发送电机自检指令后，控制器不一定会将状态置为 自检状态，使解析返回数据时无法判断是否结束，因此需要一个超时兜底,时间以实际测算为准。

示例：

```java
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
```

### 4.2、参数下发

参数下发子需要从DeviceManager 获取DeviceParams 实例，然后修改参数，通过Cmd 生成指令，然后通SerialPortManager 发送即可。

```java
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
```

### 4.3、开始、停止 、原点重置、错误复位

```java
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
```

### 4.4、清除数据

```java
 /**
 *  清除数据指令不能一直发，这里通过克隆的方式规避
 **/
ControlParams controlParams = DeviceManager.getInstance().getControlParams();
controlParams.setClearMode(ClearMode.ALL);
```

### 4.5、调节阻力

```java
ControlParams controlParams = DeviceManager.getInstance().getControlParams();
controlParams.setForce(force);
```

### 4.6、切换拉力模式

```java
public void switchMode(ForceMode forceMode) {
    LogUtil.d(TAG,"switchMode :"+ forceMode);
    //this.forceMode.postValue(forceMode);

    ControlParams controlParams = DeviceManager.getInstance().getControlParams();
    controlParams.setMode(forceMode);
}
```

### 4.7、设置向心、离心、等速 系数

- 向心模式：回力 = 拉力 x (1.0 - 向心系数x 0.1) + 0.5f

- 离心模式：回力 = 拉力 x (1.0 + 离心系数x0.1) + 0.5f

- 等速模式：速度越大拉力越大，等速系数越大，相同速度下拉力越小

```java
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
```

### 4.8 设置弹力

- 弹力模式：拉力 = 基础拉力 + 最大弹力变化量 x 当前行程 / 弹力最大行程

- 最大弹力变化量 = （弹力系数 = 最大阻力 - 当前设置的阻力）x 弹力系数

- 弹力最大行程 = 默认为50，可以设置

```java
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
     * 设置最大弹力行程
     * */
    public void setElasticMaxLength(int elasticMaxLength){
        LogUtil.d(TAG,"setElasticMaxLength :"+ elasticMaxLength);

        ControlParams controlParams = DeviceManager.getInstance().getControlParams();
        controlParams.setMaxElectricLength(elasticMaxLength);
    }
```

### 4.9 升降电机调节

- 升降电机调节 和 升降电机自检一样，都是控制指令，需要轮询状态

- 控制器不保证每次调节开始后都回复 正在调节，需要超时兜底

- 电机1、2可以一起调节

- 不同型号的电机一级需要的时间不同，需要实际测算

示例：

```java
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
```

## 5、 OTA 更新

- 没有版本高低限制，低版本、同版本、高版本都可以覆盖安装

- 更新完成后需要断电重启才能生效

- FirmwareInstaller(int type, File destFile ) ，type 代表类型（转接板1 或 控制器2），destFile 为要安装的bin文件

示例：

```java
    installer = new FirmwareInstaller(2, file);
    installer.setCallBack(new FirmwareInstaller.CallBack() {
        @Override
        public void startSend() {
            mBinding.pbInstall.setVisibility(View.GONE);

            mBinding.pbDownload.setVisibility(View.VISIBLE);
            mBinding.pbDownload.setProgress(0);
            mBinding.tvDownloadTip.setText(getString(R.string.update_installing_firmware));
        }

        @Override
        public void progress(int progress) {
            mBinding.pbDownload.setProgress(progress);
        }

        @Override
        public void success() {
            isInstallComplete = true;
            //安装完成，提示用户断电重启才能生效
            mBinding.tvDownloadTip.setText(getString(R.string.update_install_compeleted));

            //将文件移动到对应到历史文件夹
            ThreadPoolManager.getInstance().execute(new Runnable() {
                @Override
                public void run() {
                    FileManager.moveFile(file);
                    LogUtil.d(TAG,"移动完成");
                }
            });

            //展示确认框，提示用户重启
            new ConfirmDialog(mActivity)
                    .setConfirmButtonHide()
                    .setContent(getString(R.string.update_restart_tip))
                    .show();
        }

        @Override
        public void error(String message) {
            mBinding.btnCheck.setVisibility(View.VISIBLE);
            mBinding.btnCheck.setText(getString(R.string.update_reinstall));
            mBinding.tvDownloadTip.setText(getString(R.string.update_install_error));
            mBinding.pbDownload.setVisibility(View.GONE);
            mBinding.pbInstall.setVisibility(View.GONE);
        }
    });
    installer.startInstall(mHandler);
```
