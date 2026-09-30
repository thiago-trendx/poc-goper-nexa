### APP适配信息

#### 1、硬件配置

- 系统版本 ：rk3568-11.0-20260708.085648

- Android 版本：11

- 内核版本：4.19.232

- 硬件版本：rk30board

- 内存：4GB

- 硬盘：32GB

- 屏幕分辨率：1920x1080 Density = 1.5

#### 2、语言切换

- 权限要求

```xml
   <!-- 修改设置的权限 -->
    <uses-permission android:name="android.permission.WRITE_SETTINGS"/>
    <uses-permission android:name="android.permission.CHANGE_CONFIGURATION" />
```

代码示例

```java
 /**
     * 通过反射调用 AOSP 隐藏 API 修改系统语言
     * LocalePicker.updateLocale(Locale) 内部会：
     *   1. 调用 ActivityManager.updateConfiguration() 立即生效
     *   2. 写入 Settings.System.LOCALE_KEY 持久化，重启后保留
     *
     * 需要 CHANGE_CONFIGURATION 权限（系统应用自动授予）
     */
    public static  void applyLocale(@NonNull Context context,Locale locale) {
        try {
            Class<?> localePicker = Class.forName("com.android.internal.app.LocalePicker");
            Method updateLocale = localePicker.getDeclaredMethod("updateLocale", Locale.class);
            updateLocale.setAccessible(true);
            updateLocale.invoke(null, locale);
            Log.d("LanguageUtils---", "applyLocale: " + locale.toLanguageTag());
        } catch (Exception e) {
            Log.e("LanguageUtils---", "applyLocale failed: " + e.getMessage());
            // 降级：直接修改 Configuration（不持久化，仅当次生效）
            LanguageUtils.applyLocaleFallback(context,locale);
        }
    }

    /**
     * 降级方案：通过 ActivityManager 反射修改（不依赖 LocalePicker）
     */
    @SuppressWarnings("deprecation")
    public static void applyLocaleFallback(@NonNull Context context,Locale locale) {
        try {
            Locale.setDefault(locale);
            android.content.res.Configuration config =
                    context.getResources().getConfiguration();
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                android.os.LocaleList localeList = new android.os.LocaleList(locale);
                config.setLocales(localeList);
            } else {
                config.locale = locale;
            }
            context.getResources().updateConfiguration(
                    config, context.getResources().getDisplayMetrics());
            Log.d("LanguageUtils---", "applyLocaleFallback: " + locale.toLanguageTag());
        } catch (Exception e) {
            Log.e("LanguageUtils---", "applyLocaleFallback failed: " + e.getMessage());
        }
    }
```

#### 3、恢复出厂设置

- 需要权限,系统自动授予

```xml
   <!-- 恢复出厂设置权限-->
    <uses-permission android:name="android.permission.MASTER_CLEAR"
        tools:ignore="ProtectedPermissions" />
    <uses-permission android:name="android.permission.REBOOT"
        tools:ignore="ProtectedPermissions" />
```

- 代码示例

```java
    /**
     * 恢复出厂设置
     * 需要权限：android.permission.MASTER_CLEAR（系统应用自动授予）
     */
    public void factoryReset() {
        ThreadPoolManager.getInstance().execute(()->{
            try {
                // 方式一：通过 RecoverySystem（推荐，Android 标准 API）
                RecoverySystem.rebootWipeUserData(getContext());
            } catch (Exception e) {
                //ToastUtil.show("恢复出厂设置失败");
                LogUtil.e("FactoryReset", "RecoverySystem failed: " + e.getMessage());

                sendBroadcast();
            }
        });

    }

    private void sendBroadcast() {
        mainHandler.post(()->{
            LogUtil.d("FactoryReset","发送恢复出厂设置广播");

            // 方式二：发送广播（兜底）
            Intent intent = new Intent("android.intent.action.MASTER_CLEAR");
            intent.addFlags(Intent.FLAG_RECEIVER_FOREGROUND);
            intent.setPackage("android"); // 指定发给系统，避免被其他 App 拦截
            intent.putExtra("reason", "factory_reset");           // 原因记录
            intent.putExtra("wipeExternalStorage", true);        // 是否清除外部存储
            intent.putExtra("wipeEsims", false);                  // 是否清除 eSIM
            getContext().sendBroadcast(intent);
        });
    }
```

#### 4、nfc 配置

- nfc芯片型号：NXP PN7160 

- Android 系统版本：1

- nfc 支持读卡和模拟卡两种模式，nfc 芯片程序会在两种模式中来回切换。

- 可以单独开启只读模式，在只读模式下，模拟卡（卡监听）阶段会被关掉，此时只能作为读卡器使用。

- 不能单独关闭读卡模式，只能同时关闭两种模式，进入静默状态。

##### 4、1 读卡模式

  读卡模式支持类型：

```xml
# NFA_TECHNOLOGY_MASK_A             0x01    /* NFC Technology A             */
# NFA_TECHNOLOGY_MASK_B             0x02    /* NFC Technology B             */
# NFA_TECHNOLOGY_MASK_F             0x04    /* NFC Technology F             */
# NFA_TECHNOLOGY_MASK_ISO15693        0x08    /* Proprietary Technology       */
# NFA_TECHNOLOGY_MASK_KOVIO            0x20    /* Proprietary Technology       */
# NFA_TECHNOLOGY_MASK_A_ACTIVE      0x40    /* NFC Technology A active mode */
# NFA_TECHNOLOGY_MASK_F_ACTIVE      0x80    /* NFC Technology F active mode */
```

国内常见 A、B 、ISO15693、A_ACTIVE 的卡片，B 为保密级别更高的标签卡，比如银行卡、交通卡等，其他为普通卡片，常用于门禁卡、会员卡等，F、F_ACTIVE 是日本国内用的。

###### 4、1、1  在需要的activity声明应用在前台（响应较慢）

在 onresume 调用

```java
 /** desc： 提高本应用优先级，声明activity在前台
     * create at 2026/7/8 9:49 by liuxiong
     */
    private void enableNfcForegroundDispatch() {
        if (nfcAdapter == null || !nfcAdapter.isEnabled()) return;

        Intent intent = new Intent(this, getClass());
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);

        PendingIntent pendingIntent = PendingIntent.getActivity(this, 0, intent,
                PendingIntent.FLAG_MUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);

        IntentFilter[] filters = new IntentFilter[] {
                new IntentFilter(NfcAdapter.ACTION_NDEF_DISCOVERED),
                new IntentFilter(NfcAdapter.ACTION_TECH_DISCOVERED),
                new IntentFilter(NfcAdapter.ACTION_TAG_DISCOVERED)
        };
        // null 代表捕获所有支持的NFC技术标签
        String[][] techLists = null;
        nfcAdapter.enableForegroundDispatch(this, pendingIntent, filters, techLists);
    }
```

在onPause调用

```java
if (nfcAdapter != null) {
    //取消 提高本应用优先级，强行接管nfc
    nfcAdapter.disableForegroundDispatch(this);
}
```

本方式读卡结果会通过 onNewIntent(Intent intent) 回调，需要从Intent 获取标签卡数据

```java
/** desc： 处理NFC数据
     * create at 2026/7/11 10:17 by liuxiong
     */
    private void handleNfcIntent(Intent intent) {
        String action = intent.getAction();
        if (!NfcAdapter.ACTION_TAG_DISCOVERED.equals(action)
                && !NfcAdapter.ACTION_TECH_DISCOVERED.equals(action)
                && !NfcAdapter.ACTION_NDEF_DISCOVERED.equals(action)) {
            return;
        }
        // API 33+ 建议用带 Class 的重载,这里用旧签名兼容低版本
        Tag tag = intent.getParcelableExtra(NfcAdapter.EXTRA_TAG);
        if (tag == null) return;

        String uid = NfcUtil.toHex(tag.getId());   // getId() 对任何 tag 都能取到 UID
        if (TextUtils.isEmpty(uid)) return;

        LogUtils.d("okhttp nfc read , UID: "+NfcUtil.toHexString(tag.getId()));

        //通过UID等
        processNfcData(uid);
    }
```

可以直接使用UID 做身份识别登录，也可从 NDEF 数据中读取自定义数据。

###### 4、1、2 设置nfc 为只读模式（推荐）

注意：回调在子线程

```java
    /** desc： 开启只读模式
     * create at 2026/8/1 10:42 by liuxiong
     */
    private void ennableReaderMode(){
        if (adapter != null) {
            int flags = NfcAdapter.FLAG_READER_NFC_A | NfcAdapter.FLAG_READER_NFC_B
                    | NfcAdapter.FLAG_READER_NFC_F | NfcAdapter.FLAG_READER_NFC_V;
//                    | NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK;

            adapter.enableReaderMode(activity, tag -> {

                String tagId = NfcUtil.toHex(tag.getId());
                LogUtils.d("----  , tagId = "+NfcUtil.toHex(tag.getId()));
                handler.post(()->{
                    //切换到登录状态
                    switchStatus(Status.LOGING);

                });

                //登录
                cardLogin(tagId);

            }, flags, null);
        }
    }

      /**
     * 关闭只读模式
     * */
    private  void disennableReaderMode(){
        if (adapter != null) {
            adapter.disableReaderMode(activity);
        }
    }
```

##### 4、2 模拟卡模式

**1、准备服务配置文件 apduservice.xml**

示例

```xml
<?xml version="1.0" encoding="utf-8"?>
<!--
    Registers this app to emulate the NDEF Type-4 Tag application.
    AID D2760000850101 is the well-known NDEF application identifier, so a
    standard NFC reader (e.g. another phone) reading this device sees an NDEF tag.
-->
<host-apdu-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/hce_service_desc"
    android:requireDeviceUnlock="false"
    android:apduServiceBanner="@drawable/my_banner">
    <aid-group
        android:description="@string/aid_group_desc"
        android:category="payment">
        <aid-filter android:name="D2760000850101" />
    </aid-group>
</host-apdu-service>
```

- hce_service_desc  是钱包名称

- my_banner 是钱包的图标，可以用app的logo，尺寸260x96 px

- android:category="payment"  声明是钱包应用

- aid_group_desc  自己想填啥填啥

- D2760000850101 默认的aid，只有这个aid可以被手机读卡器识别

**2、实现HCE 卡模拟服务**

H5 和 微信 URL Scheme 只能选一个，手机会优先处理aar 数据，H5会被拦截。

```java
package com.oma.doublecontrolLT.login;

import android.content.Context;
import android.content.SharedPreferences;
import android.nfc.NdefMessage;
import android.nfc.NdefRecord;
import android.nfc.cardemulation.HostApduService;
import android.os.Bundle;
import android.provider.Settings;
import android.util.Log;

import com.oma.doublecontrolLT.common.network.UUIDUtils;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.UUID;

/**
 * ============================================================
 * HCE 服务 —— 模拟 NFC Type 4 Tag（NDEF 标签）
 * ============================================================
 *
 * 【用途】
 *   当手机（读卡器）碰触本设备时，本服务会返回一个 NDEF 消息，
 *   用于拉起微信并打开指定小程序，同时携带设备唯一标识。
 *
 * 【NDEF 消息结构】（共 3 条记录）
 *   1. URI Record      : 微信小程序 URL Scheme（含 device_id 参数）
 *   2. AAR Record      : Android Application Record，指定微信包名
 *   3. MIME Record     : 自定义类型 "application/device-id"，内容仅为 device_id（纯文本）
 *
 * 【通信流程（读卡器侧）】
 *   1. SELECT AID = D2760000850101（NDEF Type 4 Tag 标准 AID）
 *   2. SELECT CC 文件（E103）
 *   3. READ BINARY 读取 CC 文件（15 字节）
 *   4. SELECT NDEF 文件（E104）
 *   5. READ BINARY 读取 NDEF 文件（2 字节长度 + NDEF 消息）
 *
 * 【设备标识（device_id）】
 *   - 首次启动时生成，并持久化到 SharedPreferences。
 *   - 生成策略：优先使用 Android ID，若不可用则生成随机 UUID。
 *   - 此 device_id 会同时放入 URI 参数和自定义 MIME 记录中，保证一致性。
 *
 * 【配置文件】
 *   可通过 SharedPreferences 动态修改 URL Scheme 模板（KEY_PAYLOAD）。
 *   模板中的占位符 "DEVICE_ID_PLACEHOLDER" 会被自动替换为实际 device_id。
 * ============================================================
 */
public class NfcHceService extends HostApduService {

    // ======================= 日志与 SharedPreferences =======================
    public static final String TAG = "NfcHceService";    public static final String PREFS = "nfc_sim_prefs";
    public static final String KEY_PAYLOAD = "emulation_payload";   // URL Scheme 模板

    // ======================= 微信相关常量 =======================
    /** 微信包名（AAR 使用） */
    public static final String WECHAT_PACKAGE = "com.tencent.mm";

    public static final String DEFAULT_SCHEME = "weixin://***"; //微信的 Scheme 连接
    public static final String DEFAULT_H5 = "https://***";  //小程序的H5 链接

    // ======================= ISO 7816-4 状态字 =======================
    private static final byte[] SW_OK                  = {(byte) 0x90, 0x00};
    private static final byte[] SW_FILE_NOT_FOUND      = {(byte) 0x6A, (byte) 0x82};
    private static final byte[] SW_INS_NOT_SUPPORTED   = {(byte) 0x6D, 0x00};
    private static final byte[] SW_WRONG_LENGTH        = {(byte) 0x67, 0x00};

    // ======================= NDEF Type 4 Tag 文件标识符 =======================
    /** NDEF 应用的 AID（标准值） */
    private static final byte[] NDEF_AID = {
            (byte) 0xD2, 0x76, 0x00, 0x00, (byte) 0x85, 0x01, 0x01
    };
    private static final byte[] CC_FILE_ID   = {(byte) 0xE1, 0x03};   // Capability Container 文件 ID
    private static final byte[] NDEF_FILE_ID = {(byte) 0xE1, 0x04};   // NDEF 文件 ID

    /**
     * Capability Container（CC）文件内容（固定 15 字节）
     *  - 声明 NDEF 文件 E104，最大大小 0x7FFF，读/写权限分别设为自由/只读
     */
    private static final byte[] CC_FILE = {
            0x00, 0x0F,             // CCLEN = 15
            0x20,                   // Mapping version 2.0
            0x00, (byte) 0x3B,      // MLe（最大 R-APDU 数据长度）
            0x00, (byte) 0x34,      // MLc（最大 C-APDU 数据长度）
            0x04, 0x06,             // NDEF File Control TLV：tag=0x04, length=0x06
            (byte) 0xE1, 0x04,      // NDEF 文件 ID
            0x7F, (byte) 0xFF,      // 最大 NDEF 文件大小（32767 字节）
            0x00,                   // 读访问：自由
            (byte) 0xFF             // 写访问：只读
    };

    // ======================= 运行时状态 =======================
    /** 当前 NDEF 文件数据（含 2 字节长度前缀 + NDEF 消息） */
    private byte[] ndefFile = {0x00, 0x00};

    /** 当前是否选中了 CC 文件 */
    private boolean ccSelected = false;
    /** 当前是否选中了 NDEF 文件 */
    private boolean ndefSelected = false;

    /** 设备唯一标识（缓存，避免频繁读取 SP） */
    private String uuid = null;

    // ======================= 生命周期方法 =======================

    @Override
    public void onCreate() {
        super.onCreate();
        Log.d(TAG, "Service created");
        // 构建 NDEF 文件数据
        rebuildNdefFile();
    }

    @Override
    public void onDeactivated(int reason) {
        // 当 NFC 连接断开（如移开手机）时调用，重置文件选择状态
        Log.d(TAG, "Deactivated, reason: " + reason);
        ccSelected = false;
        ndefSelected = false;
    }

    // ======================= NDEF 消息构建 =======================

    /**
     * 构建包含三条记录的 NDEF 消息：
     *  1. URI Record  : 微信小程序 Scheme（含 device_id 参数）
     *  2. AAR Record  : 微信包名
     *  3. MIME Record : 自定义类型，仅存放 device_id（纯文本 UTF-8）
     *
     * @param schemeWithDeviceId 已替换占位符的完整 Scheme
     * @param uuid           uuid（与 URI 中一致）
     * @return NdefMessage 对象
     */
    private NdefMessage buildWechatMessage(String schemeWithDeviceId, String uuid) {
        // 1. URI 记录 Scheme
        //NdefRecord uriRecord = NdefRecord.createUri(schemeWithDeviceId);

        // 2. AAR 记录（指定微信包名，确保安卓系统优先拉起微信）
        //NdefRecord aarRecord = NdefRecord.createApplicationRecord(WECHAT_PACKAGE);

        // 3. URI 记录 H5
        String h5 = DEFAULT_H5.replace("DEVICE_ID_PLACEHOLDER",uuid);
        NdefRecord uriRecordH5 = NdefRecord.createUri(h5);

        // 4、UUID
        NdefRecord uuidRecord = NdefRecord.createTextRecord("en", uuid);

        // 按顺序组装：URI → AAR → 自定义（顺序重要，系统通常处理前几条）
        //return new NdefMessage(new NdefRecord[]{ uuidRecord});
//        return new NdefMessage(new NdefRecord[]{uriRecord, uuidRecord});
//        return new NdefMessage(new NdefRecord[]{uriRecord, aarRecord, uriRecordH5, uuidRecord});
        return new NdefMessage(new NdefRecord[]{uriRecordH5, uuidRecord});
    }

    /**
     * 从 SharedPreferences 读取 Scheme 模板，替换占位符，
     * 然后构建完整的 NDEF 文件数据（含 2 字节长度前缀）。
     *
     * 此方法会在每次会话开始时（SELECT AID）调用，确保使用最新的配置和设备 ID。
     */
    private void rebuildNdefFile() {
        SharedPreferences sp = getSharedPreferences(PREFS, Context.MODE_PRIVATE);
        // 读取用户自定义的 Scheme 模板，若不存在则使用默认值
        String schemeTemplate = sp.getString(KEY_PAYLOAD, DEFAULT_SCHEME);

        // 保证 deviceId 已初始化
        if (uuid == null) {
            uuid = UUIDUtils.generateNFCUUID();
        }

        // 替换占位符
        String finalScheme = schemeTemplate.replace("DEVICE_ID_PLACEHOLDER", uuid);
        Log.d(TAG, "Final scheme: " + finalScheme);

        try {
            // 构建 NDEF 消息
            NdefMessage msg = buildWechatMessage(finalScheme, uuid);
            byte[] msgBytes = msg.toByteArray();

            // Type 4 Tag 要求 NDEF 文件内容为 [2字节长度] + [NDEF 消息]
            byte[] file = new byte[msgBytes.length + 2];
            file[0] = (byte) ((msgBytes.length >> 8) & 0xFF);
            file[1] = (byte) (msgBytes.length & 0xFF);
            System.arraycopy(msgBytes, 0, file, 2, msgBytes.length);

            ndefFile = file;
        } catch (Exception e) {
            Log.e(TAG, "Failed to build NDEF file", e);
            // 失败时置空，避免返回无效数据
            ndefFile = new byte[]{0x00, 0x00};
        }
    }

    // ======================= APDU 命令处理 =======================

    /**
     * 处理读卡器发送的 APDU 命令（在 NFC 通信线程中调用）
     *
     * @param apdu   读卡器发来的命令字节数组
     * @param extras 附加参数（通常为空）
     * @return 要返回给读卡器的响应 APDU（包含状态字）
     */
    @Override
    public byte[] processCommandApdu(byte[] apdu, Bundle extras) {
        Log.d(TAG, "Received APDU: " + NfcUtil.toHex(apdu));

        if (apdu == null || apdu.length < 4) {
            return SW_WRONG_LENGTH;
        }

        byte ins = apdu[1];  // 指令字节
        byte p1  = apdu[2];  // 参数1

        switch (ins) {
            case (byte) 0xA4:  // SELECT 命令
                return handleSelect(apdu, p1);
            case (byte) 0xB0:  // READ BINARY 命令
                return handleReadBinary(apdu);
            default:
                return SW_INS_NOT_SUPPORTED;
        }
    }

    /**
     * 处理 SELECT 命令
     * - P1=0x04：通过 AID 选择应用（选择 NDEF AID）
     * - P1=0x00：通过文件 ID 选择文件（CC 或 NDEF 文件）
     */
    private byte[] handleSelect(byte[] apdu, byte p1) {
        Log.d(TAG, "handleSelect, p1=" + String.format("%02X", p1));

        // ---------- 1. 通过 AID 选择应用 ----------
        if (p1 == (byte) 0x04) {
            if (apdu.length >= 6) {
                int lc = apdu[4] & 0xFF;       // 数据长度
                if (apdu.length >= 5 + lc) {
                    byte[] aid = Arrays.copyOfRange(apdu, 5, 5 + lc);
                    if (Arrays.equals(aid, NDEF_AID)) {
                        // 选中 NDEF 应用 → 重新构建 NDEF 数据（确保最新）
                        rebuildNdefFile();
                        // 重置文件选择状态
                        ccSelected = false;
                        ndefSelected = false;
                        return SW_OK;
                    }
                }
            }
            return SW_FILE_NOT_FOUND;
        }

        // ---------- 2. 通过文件 ID 选择文件 ----------
        if (p1 == (byte) 0x00 && apdu.length >= 7) {
            int lc = apdu[4] & 0xFF;
            if (lc == 2 && apdu.length >= 5 + lc) {
                byte[] fid = Arrays.copyOfRange(apdu, 5, 7);  // 2 字节文件 ID
                if (Arrays.equals(fid, CC_FILE_ID)) {
                    ccSelected = true;
                    ndefSelected = false;
                    return SW_OK;
                }
                if (Arrays.equals(fid, NDEF_FILE_ID)) {
                    ndefSelected = true;
                    ccSelected = false;
                    return SW_OK;
                }
            }
        }

        return SW_FILE_NOT_FOUND;
    }

    /**
     * 处理 READ BINARY 命令
     * - 根据当前选中的文件（CC 或 NDEF），从指定偏移读取指定长度的数据
     * - 若长度不足，返回实际可用数据（ISO 7816-4 允许短响应）
     */
    private byte[] handleReadBinary(byte[] apdu) {
        // 确定读取源
        byte[] source;
        if (ccSelected) {
            source = CC_FILE;
        } else if (ndefSelected) {
            source = ndefFile;
        } else {
            return SW_FILE_NOT_FOUND;
        }

        // 解析偏移量（P1:P2 组成 16 位偏移）
        int offset = ((apdu[2] & 0xFF) << 8) | (apdu[3] & 0xFF);
        // 期望读取长度（Le），若未提供则默认读全部
        int le = (apdu.length > 4) ? (apdu[4] & 0xFF) : 0;

        if (offset > source.length) {
            return SW_WRONG_LENGTH;
        }

        // 计算实际读取长度（若 Le=0 或超出范围，则读至文件末尾）
        int length = le;
        if (length == 0 || (offset + length) > source.length) {
            length = source.length - offset;
        }

        // 组装响应：数据 + 状态字 9000
        byte[] response = new byte[length + 2];
        System.arraycopy(source, offset, response, 0, length);
        response[length] = (byte) 0x90;
        response[length + 1] = 0x00;

        Log.d(TAG, "ReadBinary: offset=" + offset + ", length=" + length + ", response length=" + response.length);
        return response;
    }
}
```

**3、AndroidManifest.xml  里面注册**

- 权限要求



```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="true" />
```

- 注册HCE 服务

```xml
    <service
            android:name=".login.NfcHceService"
            android:exported="true"
            android:permission="android.permission.BIND_NFC_SERVICE">
            <intent-filter>
                <action android:name="android.nfc.cardemulation.action.HOST_APDU_SERVICE" />
                <!-- 添加 DEFAULT category，使系统能在付款应用列表中识别此服务 -->
                <category android:name="android.intent.category.DEFAULT" />
            </intent-filter>
            <meta-data
                android:name="android.nfc.cardemulation.host_apdu_service"
                android:resource="@xml/apduservice" />
        </service>
```

**4、注意事项**

如果NfcHceService服务未生效，可以在设置 => 已连接设备 => 连接偏好设置 => NFC 查看NFC是否开启，点击 感应式付款  可以查看默认钱包应用是否为当前应用
