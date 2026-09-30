package com.sunway.l850tdemo.activity;

import android.os.Bundle;

import androidx.activity.EdgeToEdge;
import androidx.lifecycle.Observer;
import androidx.lifecycle.ViewModelProvider;

import com.sunway.l850tdemo.dialog.DownTimeDialog;
import com.sunway.l850tdemo.R;
import com.sunway.l850tdemo.databinding.ActivityTrainingBinding;
import com.sunway.l850tdemo.util.LogUtil;
import com.sunway.l850tdemo.viewmodel.RunViewModel;
import com.sunway.l850tdemo.UserTrainingConfig;
import com.sunway.l850tdemo.util.TimeUtils;
import com.sunway.sdk850.port.bean.ForceMode;
import com.sunway.sdk850.port.bean.RunState;

public class TrainingActivity extends BaseActivity {

    private ActivityTrainingBinding mBinding;

    private RunViewModel viewModel;
    private DownTimeDialog downTimeDialog;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        EdgeToEdge.enable(this);
        mBinding = ActivityTrainingBinding.inflate(getLayoutInflater());
        setContentView(mBinding.getRoot());

    }

    @Override
    protected void onResume() {
        super.onResume();

        viewModel = new ViewModelProvider(this).get(RunViewModel.class);

        //初始化观察者
        initObserve();

        //初始化view
        initView();

        //初始化
        viewModel.init(new RunViewModel.InitCallback() {
            @Override
            public void onInited() {
                //开始运动
                viewModel.start();
            }
        });
    }

    /**
     * 初始化view
     *
     */
    private void initView() {

        mBinding.tvClose.setOnClickListener(v -> finish());

        // 开始/停止
        mBinding.ivStart.setOnClickListener(v -> {
            if(viewModel.runStatus.getValue() == RunState.RUNNING){
                viewModel.stop();
            }else{
                viewModel.start();
            }
        });

        // 原点重置
        mBinding.btnOriginReset.setOnClickListener(v -> {
             viewModel.originReset();
        });

        //错误恢复
        mBinding.btnErrorRestore.setOnClickListener(v -> {
             viewModel.restore();
        });

        //清除数据
        mBinding.btnClear.setOnClickListener(v -> {
            viewModel.clearData();
        });

        /** 模式切换 */
        mBinding.btnMode1.setOnClickListener(v -> viewModel.switchMode(ForceMode.STANDARD));
        mBinding.btnMode2.setOnClickListener(v -> viewModel.switchMode(ForceMode.CENTRIPETAL));
        mBinding.btnMode3.setOnClickListener(v -> viewModel.switchMode(ForceMode.CENTRIFUGAL));
        mBinding.btnMode4.setOnClickListener(v -> viewModel.switchMode(ForceMode.VELOCITY));
        mBinding.btnMode5.setOnClickListener(v -> viewModel.switchMode(ForceMode.ELASTIC));

        /** 阻力、系数调节 */
        //设置的阻力
        mBinding.avForce.setUnit("kg");
        mBinding.avForce.setCallback(vaule -> viewModel.setForce(vaule));
        mBinding.avCentripetal.setCallback(vaule -> viewModel.setCentripetal(vaule));
        mBinding.avCentrifugal.setCallback(vaule -> viewModel.setCentrifugal(vaule));
        mBinding.avVelocity.setCallback(vaule -> viewModel.setVelocity(vaule));
        mBinding.avElastic.setCallback(vaule -> viewModel.setElastic(vaule));
        mBinding.avMotor1.setCallback(vaule -> viewModel.setMotor1Position(vaule));
        mBinding.avMotor2.setCallback(vaule -> viewModel.setMotor2Position(vaule));

        mBinding.avForce.setType(0);
        mBinding.avCentripetal.setType(1);
        mBinding.avCentrifugal.setType(1);
        mBinding.avVelocity.setType(2);
        mBinding.avElastic.setType(2);
        mBinding.avMotor1.setType(3);
        mBinding.avMotor2.setType(3);

        /** 默认值 */
        UserTrainingConfig userConfig = viewModel.getUserConfig();
        mBinding.avForce.setValue(userConfig.getForce());
        mBinding.avCentripetal.setValue(userConfig.getCentripetal());
        mBinding.avCentrifugal.setValue(userConfig.getCentrifugal());
        mBinding.avVelocity.setValue(userConfig.getVelocity());
        mBinding.avElastic.setValue(userConfig.getElastic());
        mBinding.avMotor1.setValue(userConfig.getMotorPosition1());
        mBinding.avMotor2.setValue(userConfig.getMotorPosition2());
    }

    /**
     * 初始化观察者
     *
     */
    private void initObserve() {
        viewModel.portState.observe(this, new Observer<Integer>() {
            @Override
            public void onChanged(Integer state) {
                /** 0 未连接 ， 1 连接中  ，2 已连接 ，3 连接失败 */
                String stateStr = "未连接";
                switch (state) {
                    case 0:
                        stateStr = "未连接";
                        break;
                    case 1:
                        stateStr = "连接中";
                        break;
                    case 2:
                        stateStr = "已连接";
                        break;
                    case 3:
                        stateStr = "连接失败";
                        break;
                }
                mBinding.tvPortState.setText("串口状态: " + stateStr);
            }
        });

        //控制器软件信息
        viewModel.controlSoftNum.observe(this, softNum -> mBinding.tvControlSoftNum.setText("控制器软件料号: " + softNum));
        viewModel.controlVerison.observe(this, version -> mBinding.tvControlVerion.setText("控制器版本号: " + version));

        //运动时间
        viewModel.runTime.observe(this, runTime -> mBinding.tvRunTime.setText(TimeUtils.formatDuration(runTime / 1000) + "\n 运动时间"));

        //运动状态
        viewModel.runStatus.observe(this, runState -> {
            if (runState == RunState.RUNNING) {
                mBinding.ivStart.setImageResource(R.drawable.workout_pause);
            } else {
                mBinding.ivStart.setImageResource(R.drawable.workout_start);
            }
        });

        //次数
        viewModel.pullNum.observe(this, pullNum -> mBinding.btnPullNum.setText(pullNum + " \n 次数"));

        //速度
        viewModel.speed.observe(this, speed -> mBinding.btnSpeed.setText(speed + " cm/s \n 速度"));

        //行程
        viewModel.distance.observe(this, distance -> mBinding.btnDistance.setText(distance + " cm \n 行程"));

        //错误码
        viewModel.errorCode.observe(this, errorCode -> {
            mBinding.btnErrorCode.setText("E - " + String.format("%02x", errorCode) + "\n 错误码");
        });

        //速度
        viewModel.temperature.observe(this, temp -> mBinding.btnTempleate.setText(temp + " °C \n 温度"));

        //实时力
        viewModel.realForce.observe(this, realForce -> mBinding.btnRealForce.setText(realForce + " kg \n 最大力矩"));

        //升降电机状态
        viewModel.liftMotorStatus.observe(this, status -> mBinding.btnMotorStatus.setText(String.format("%02x", status) + "\n 升降电机状态"));

        //阻力模式
        viewModel.forceMode.observe(this, new Observer<ForceMode>() {
            @Override
            public void onChanged(ForceMode forceMode) {
                mBinding.btnMode1.setSelected(forceMode == ForceMode.STANDARD);
                mBinding.btnMode2.setSelected(forceMode == ForceMode.CENTRIPETAL);
                mBinding.btnMode3.setSelected(forceMode == ForceMode.CENTRIFUGAL);
                mBinding.btnMode4.setSelected(forceMode == ForceMode.VELOCITY);
                mBinding.btnMode5.setSelected(forceMode == ForceMode.ELASTIC);
            }
        });

        //升降电机倒计时
        viewModel.downTime.observe(this, downTime -> {

            LogUtil.d(tag,"downTime= "+ downTime);

            if(downTime > 0 ){ //正在倒计时
                if(downTimeDialog == null){
                    downTimeDialog = new DownTimeDialog(this);
                    downTimeDialog.setOnCancelClickListener(v -> {
                        downTimeDialog.dismiss();
                    });
                }

                if(!downTimeDialog.isShowing()){
                    downTimeDialog.show();
                }

                //更新倒计时
                downTimeDialog.updateTime(downTime);

            }else{
                //更新倒计时
                if(downTimeDialog != null && downTimeDialog.isShowing()){
                    downTimeDialog.updateTime(downTime);
                }
            }
        });
    }


    @Override
    protected void onDestroy() {
        super.onDestroy();
        if(downTimeDialog != null && downTimeDialog.isShowing()){
            downTimeDialog.dismiss();
        }

        if (viewModel != null) {
            viewModel.unInit();
        }
    }
}