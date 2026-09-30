package com.sunway.l850tdemo.activity;

import android.os.Bundle;
import androidx.annotation.Nullable;
import androidx.lifecycle.ViewModelProvider;

import com.sunway.l850tdemo.dialog.DownTimeDialog;
import com.sunway.l850tdemo.databinding.ActivityFactoryBinding;
import com.sunway.l850tdemo.util.ToastUtil;
import com.sunway.l850tdemo.viewmodel.FactorySetViewModel;
import com.sunway.sdk850.port.Contancts;

public class FactoryActivity extends BaseActivity{

    private FactorySetViewModel viewModel;

    private ActivityFactoryBinding mBinding;

    private DownTimeDialog downTimeDialog;

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        mBinding = ActivityFactoryBinding.inflate(getLayoutInflater());
        setContentView(mBinding.getRoot());


    }

    @Override
    protected void onResume() {
        super.onResume();
        viewModel = new ViewModelProvider(this).get(FactorySetViewModel.class);

        initView();

        initObserve();

        viewModel.init();
    }


    private void initView() {
        //关闭
        mBinding.tvClose.setOnClickListener(v -> finish());
        //升降电机自检
        mBinding.btnSelfMotor.setOnClickListener(v -> {
            if(viewModel.isChecking()){
                ToastUtil.show("电机正在自检，请勿重复操作");
                return;
            }
            viewModel.selfCheck();
        });

        //最小阻力
        mBinding.avMinForce.setUnit("kg");
        mBinding.avMinForce.setMinValue(Contancts.MIN_FORCE[0]);
        mBinding.avMinForce.setMaxValue(Contancts.MIN_FORCE[1]);
        mBinding.avMinForce.setCallback(vaule -> viewModel.setMinForce(vaule));

        //最大阻力
        mBinding.avMaxForce.setUnit("kg");
        mBinding.avMaxForce.setMinValue(Contancts.MAX_FORCE[0]);
        mBinding.avMaxForce.setMaxValue(Contancts.MAX_FORCE[1]);
        mBinding.avMaxForce.setCallback(vaule -> viewModel.setMaxForce(vaule));

        //空闲阻力
        mBinding.avInactiveForce.setUnit("kg");
        mBinding.avInactiveForce.setMinValue(Contancts.INACTIVE_FORCE[0]);
        mBinding.avInactiveForce.setMaxValue(Contancts.INACTIVE_FORCE[1]);
        mBinding.avInactiveForce.setCallback(vaule -> viewModel.setInactiveForce(vaule));

        //最大拉绳长度
        mBinding.avMaxLength.setUnit("cm");
        mBinding.avMaxLength.setMinValue(Contancts.MAX_LENGTH[0]);
        mBinding.avMaxLength.setMaxValue(Contancts.MAX_LENGTH[1]);
        mBinding.avMaxLength.setCallback(vaule -> viewModel.setMaxLength(vaule));

        //额定转速
        mBinding.avRatedSpeed.setUnit("Rpm");
        mBinding.avRatedSpeed.setMinValue(Contancts.RATED_SPEED[0]);
        mBinding.avRatedSpeed.setMaxValue(Contancts.RATED_SPEED[1]);
        mBinding.avRatedSpeed.setCallback(vaule -> viewModel.setRatedSpeed(vaule));

        //绳轨直径
        mBinding.avRopeGuideDiameter.setUnit("cm");
        mBinding.avRopeGuideDiameter.setMinValue(Contancts.ROPE_GUIDE_DIAMETER[0]);
        mBinding.avRopeGuideDiameter.setMaxValue(Contancts.ROPE_GUIDE_DIAMETER[1]);
        mBinding.avRopeGuideDiameter.setCallback(vaule -> viewModel.setRopeGuideDiameter(vaule));

        //原点最小距离
        mBinding.avOriginMin.setUnit("cm");
        mBinding.avOriginMin.setMinValue(Contancts.ORIGIN_MIN[0]);
        mBinding.avOriginMin.setMaxValue(Contancts.ORIGIN_MIN[1]);
        mBinding.avOriginMin.setCallback(vaule -> viewModel.setOrginMinDistance(vaule));

        //原点最大距离
        mBinding.avOriginMax.setUnit("cm");
        mBinding.avOriginMax.setMinValue(Contancts.ORIGIN_MAX[0]);
        mBinding.avOriginMax.setMaxValue(Contancts.ORIGIN_MAX[1]);
        mBinding.avOriginMax.setCallback(vaule -> viewModel.setOrginMaxDistance(vaule));

        //等速系数范围
        mBinding.avVelocityRange.setMinValue( Contancts.VELOCITY_RANGE[0]);
        mBinding.avVelocityRange.setMaxValue( Contancts.VELOCITY_RANGE[1]);
        mBinding.avVelocityRange.setCallback(vaule -> viewModel.setVelocityRange(vaule));

        //力矩周期系数
        mBinding.avTorqueCycle.setMinValue( Contancts.TORQUE_CYCLE[0]);
        mBinding.avTorqueCycle.setMaxValue( Contancts.TORQUE_CYCLE[1]);
        mBinding.avTorqueCycle.setCallback(vaule -> viewModel.setTorqueVariationCycle(vaule));

        //力矩系数
        mBinding.avTorque.setMinValue( Contancts.TORQUE[0]);
        mBinding.avTorque.setMaxValue( Contancts.TORQUE[1]);
        mBinding.avTorque.setCallback(vaule -> viewModel.setTorqueCoefficient(vaule));
    }

    private void initObserve() {
        //升降电机倒计时
        viewModel.downTime.observe(this, downTime -> {

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

        viewModel.minForce.observe(this, value -> mBinding.avMinForce.setValue(value));

        viewModel.maxForce.observe(this, value -> mBinding.avMaxForce.setValue(value));

        viewModel.inactiveForce.observe(this, value -> mBinding.avInactiveForce.setValue(value));

        viewModel.maxLength.observe(this, value -> mBinding.avMaxLength.setValue(value));

        viewModel.ratedSpeed.observe(this, value -> mBinding.avRatedSpeed.setValue(value));

        viewModel.ropeGuideDiameter.observe(this, value -> mBinding.avRopeGuideDiameter.setValue(value));

        viewModel.minDistance.observe(this, value -> mBinding.avOriginMin.setValue(value));

        viewModel.maxDistance.observe(this, value -> mBinding.avOriginMax.setValue(value));

        viewModel.velocityRange.observe(this, value -> mBinding.avVelocityRange.setValue(value));

        viewModel.torqueCycle.observe(this, value -> mBinding.avTorqueCycle.setValue(value));

        viewModel.torque.observe(this, value -> mBinding.avTorque.setValue(value));
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
