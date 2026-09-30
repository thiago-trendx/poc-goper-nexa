package com.sunway.l850tdemo.activity;

import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.View;

import androidx.annotation.Nullable;
import androidx.lifecycle.Observer;
import androidx.lifecycle.ViewModelProvider;

import com.sunway.l850tdemo.R;
import com.sunway.l850tdemo.bean.DownloadProgress;
import com.sunway.l850tdemo.bean.FirmWareVersion;
import com.sunway.l850tdemo.bean.Resource;
import com.sunway.l850tdemo.databinding.ActivityUpdateChildBinding;
import com.sunway.l850tdemo.dialog.ConfirmDialog;
import com.sunway.l850tdemo.dialog.OldVersionListDialog;
import com.sunway.l850tdemo.util.FileManager;
import com.sunway.l850tdemo.util.LogUtil;
import com.sunway.l850tdemo.util.ThreadPoolManager;
import com.sunway.l850tdemo.util.ToastUtil;
import com.sunway.l850tdemo.viewmodel.UpdateViewModel;
import com.sunway.sdk850.port.FirmwareInstaller;
import com.sunway.sdk850.port.bean.DeviceInfo;

import java.io.File;

public class UpdateLowerActivity extends BaseActivity {
    private static final String TAG = "UpdateLowerFragment====";

    private ActivityUpdateChildBinding mBinding;

    private UpdateViewModel viewModel;

    private DeviceInfo currentVersion = null; //上控当前 版本

    private boolean isDownloadComplete = false; //是否下载完成

    private boolean isInstallComplete = false; //是否安装完成

    private boolean haveNewVersion = false; //是否有新版本

    private Handler mHandler = new Handler(Looper.getMainLooper());

    private FirmwareInstaller installer; // ota 安装工具类

    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        mBinding =  ActivityUpdateChildBinding.inflate(getLayoutInflater());
        setContentView(mBinding.getRoot());

        initView();

        initData();

        initListener();
    }

    protected void initView() {

        /**
         * congAssist 拷贝 下空程序到下载目录
         * */
        new Thread(() -> FileManager.copyLowerFromAsset()).start();
    }

    protected void initData() {

        viewModel = new ViewModelProvider(this).get(UpdateViewModel.class);

        mBinding.tvTabName.setText(getString(R.string.update_lower_controller));
        mBinding.tvVersion.setText(getString(R.string.update_version)+" ---" );
        mBinding.tvCurrentVersionValue.setText("---");
        mBinding.tvLatestVersionValue.setText("---");

        //当前上控版本
        viewModel.currentLowerVersion.observe(this, new Observer<DeviceInfo>() {
            @Override
            public void onChanged(DeviceInfo deviceInfoBean) {
                currentVersion = deviceInfoBean;

                mBinding.tvSoftNumberValue.setText(deviceInfoBean.getSoftwareNum());
                mBinding.tvProductModelValue.setText(deviceInfoBean.getProduceCode());
                mBinding.tvVersion.setText(getString(R.string.update_version)+" V"+ deviceInfoBean.getVersionCode());
                mBinding.tvCurrentVersionValue.setText(String.valueOf(deviceInfoBean.getVersionCode()));

                //接口获取最新下控版本
                viewModel.getLowerControllerVersion(deviceInfoBean.getSoftwareNum());
            }
        });

        //最新A上控 版本
        viewModel.checkLowerFirmwareResult.observe(this, new Observer<Resource<FirmWareVersion>>() {
            @Override
            public void onChanged(Resource<FirmWareVersion> resource) {
                switch (resource.getStatus()){
                    case LOADING:
                        //showLoading();
                        break;

                    case ERROR:
                        LogUtil.d(TAG,resource.getMessage());
                        //dismissLoading();
                        break;

                    case SUCCESS:
                        //dismissLoading();
                        FirmWareVersion lastUpperVersion = resource.getData();
                        LogUtil.d(TAG,lastUpperVersion.toString());

                        mBinding.tvLatestVersionValue.setText(String.valueOf(lastUpperVersion.getVersion()));

                        if(currentVersion!=null){
                            if(lastUpperVersion.getVersion() > currentVersion.getVersionCode()){
                                mBinding.btnCheck.setText(getString(R.string.update_download_updates));
                                mBinding.tvIsLastVeriosn.setVisibility(View.GONE);
                                haveNewVersion = true;
                            }else{
                                mBinding.tvIsLastVeriosn.setVisibility(View.VISIBLE);
                            }
                        }
                        break;
                }
            }
        });

        //下载固件 监听
        viewModel.downloadLowerProgress.observe(this, new Observer<DownloadProgress>() {
            @Override
            public void onChanged(DownloadProgress downloadProgress) {
                switch (downloadProgress.getStatus()){
                    case ERROR:
                        LogUtil.d(TAG,"ERROR---message=="+downloadProgress.getMessage());
                        mBinding.pbDownload.setVisibility(View.GONE);
                        mBinding.tvDownloadTip.setText(getString(R.string.update_download_error));
                        mBinding.btnCheck.setVisibility(View.VISIBLE);
                        mBinding.btnCheck.setText(getString(R.string.update_redownload));
                        break;

                    case PROGRESS:
                        LogUtil.d(TAG,"progress=="+downloadProgress.getProgress());
                        mBinding.pbDownload.setProgress(downloadProgress.getProgress());
                        break;

                    case COMPLETED:
                        LogUtil.d(TAG,"COMPLETED---filePath=="+downloadProgress.getDownLoadFile().getAbsolutePath());
                        isDownloadComplete = true;

                        mBinding.pbDownload.setVisibility(View.GONE);
                        mBinding.tvDownloadTip.setVisibility(View.GONE);
                        mBinding.btnCheck.setVisibility(View.VISIBLE);
                        mBinding.btnCheck.setText(getString(R.string.update_install_update));

                        break;
                }
            }
        });


        viewModel.registerCallback();
        //串口获取当前下控版本
        viewModel.getCurrentLowerFirmware();

    }

    protected void initListener() {

        //恢复
        mBinding.btnRevert.setVisibility(View.VISIBLE);
        mBinding.btnRevert.setOnClickListener(v -> {

            File[] files = FileManager.getLowerOldVersion();
            if(files == null || files.length == 0){
                ToastUtil.show(getString(R.string.update_is_factory_version));
                return;
            }

            OldVersionListDialog dialog = new OldVersionListDialog(mActivity, files);
            dialog.setCallback(file -> {
                // 隐藏已是最新版本
                mBinding.tvIsLastVeriosn.setVisibility(View.GONE);
                //隐藏 检查更新/下载/安装 按钮
                mBinding.btnCheck.setVisibility(View.GONE);
                //显示 清除数据进度条
                mBinding.pbInstall.setVisibility(View.VISIBLE);
                //隐藏 下载进度条
                mBinding.pbDownload.setVisibility(View.GONE);
                //显示 等待数据清除
                mBinding.tvDownloadTip.setVisibility(View.VISIBLE);
                mBinding.tvDownloadTip.setText(getString(R.string.update_wait_clear));

                installFirmware(file);
            });
            dialog.show();
        });

        //确认按钮
        mBinding.btnCheck.setOnClickListener(v -> {

            if(isInstallComplete){  //已经安装完成
                ToastUtil.show(getString(R.string.update_install_compeleted));
                return;
            }

            if(isDownloadComplete){ // 已下载，去安装

                mBinding.tvIsLastVeriosn.setVisibility(View.GONE);
                mBinding.btnCheck.setVisibility(View.GONE);
                mBinding.pbInstall.setVisibility(View.VISIBLE);

                mBinding.pbDownload.setVisibility(View.GONE);
                mBinding.tvDownloadTip.setVisibility(View.VISIBLE);
                mBinding.tvDownloadTip.setText(getString(R.string.update_wait_clear));

                installFirmware();

            }else if(haveNewVersion){ //有新版本 未下载,去下载

                mBinding.tvIsLastVeriosn.setVisibility(View.GONE);
                mBinding.btnCheck.setVisibility(View.GONE);
                mBinding.pbDownload.setVisibility(View.VISIBLE);
                mBinding.tvDownloadTip.setVisibility(View.VISIBLE);

                //下载下控固件
                viewModel.downloadLowerFirmware();

            }else{ //还没有检查到新版本
                if(currentVersion!= null){
                    //接口获取最新下控版本
                    viewModel.getLowerControllerVersion(currentVersion.getSoftwareNum());
                }
            }
        });
    }

    private void installFirmware() {
        String versionCode = mBinding.tvLatestVersionValue.getText().toString().trim();
        File file = FileManager.getLowerFirmwareFile(versionCode);
        installFirmware(file);
    }


    /** desc： 开始安装
     * create at 2026/3/31 14:29 by liuxiong
     */
    private void installFirmware(File file) {

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
                mBinding.tvDownloadTip.setText(message);
                mBinding.pbDownload.setVisibility(View.GONE);
                mBinding.pbInstall.setVisibility(View.GONE);
            }
        });
        installer.startInstall(mHandler);
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();

        viewModel.unRegisterCallback();
        if (installer != null) {
            installer.stop();
        }

        if (mHandler != null) {
            mHandler.removeCallbacksAndMessages(null);
        }
    }

}
