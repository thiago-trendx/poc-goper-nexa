package com.sunway.l850tdemo;


import com.sunway.sdk850.port.DeviceManager;
import com.sunway.sdk850.port.bean.DefaultUserConfig;

import lombok.Data;

/**
 * 训练配置
 * */
@Data
public class UserTrainingConfig {

    /** 重量 */
    int force = DeviceManager.getInstance().getDeviceParams().getMinForce();
    /** 等速系数 */
    int velocity = DefaultUserConfig.VELOCITY_COEFFICIENT;
    /** 弹力系数 */
    int elastic = DefaultUserConfig.ELASTIC_COEFFICIENT;

    /** 向心力系数 */
    int centripetal = DefaultUserConfig.CENTRIPETAL_COEFFICIENT;

    /** 离心力系数 */
    int centrifugal = DefaultUserConfig.CENTRIFUGAL_COEFFICIENT;

    /** 升降电机1位置 */
    int motorPosition1 = DefaultUserConfig.MOTOR_1_POSITION;
    /** 升降电机2位置 */
    int motorPosition2 = DefaultUserConfig.MOTOR_2_POSITION;
}
