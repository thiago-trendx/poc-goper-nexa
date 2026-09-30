package com.sunway.l850tdemo.util;

import android.os.Handler;
import android.os.Looper;
import android.util.Log;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.LinkedBlockingQueue;
import java.util.concurrent.ThreadFactory;
import java.util.concurrent.ThreadPoolExecutor;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Android 通用线程池工具类
 * 特性：单例、主线程回调、防内存泄漏、支持任务取消/线程池关闭、多场景任务提交
 */
public class ThreadPoolManager {
    // 日志标签
    private static final String TAG = "ThreadPoolManager";
    // 核心线程数：CPU核心数 + 1（根据Android设备特性优化）
    private static final int CORE_POOL_SIZE = Runtime.getRuntime().availableProcessors() + 1;
    // 最大线程数：CPU核心数 * 2 + 1
    private static final int MAX_POOL_SIZE = Runtime.getRuntime().availableProcessors() * 2 + 1;
    // 非核心线程存活时间：30秒（闲置后回收）
    private static final long KEEP_ALIVE_TIME = 30L;
    // 任务队列大小：128（避免队列过大导致OOM，过小导致任务立即拒绝）
    private static final int WORK_QUEUE_SIZE = 128;

    // 单例实例
    private static volatile ThreadPoolManager sInstance;
    // 核心线程池
    private final ExecutorService mThreadPool;
    // 主线程Handler（用于将回调切换到UI线程）
    private final Handler mMainHandler;
    // 存储任务和Future的映射，用于取消单个任务（ConcurrentHashMap保证线程安全）
    private final Map<Runnable, java.util.concurrent.Future<?>> mTaskMap;

    // 线程工厂：自定义线程名称，方便日志调试
    private static final ThreadFactory sThreadFactory = new ThreadFactory() {
        private final AtomicInteger mThreadNum = new AtomicInteger(1);

        @Override
        public Thread newThread(Runnable r) {
            Thread thread = new Thread(r, "Android-ThreadPool-" + mThreadNum.getAndIncrement());
            Log.d(TAG, "创建新线程：" + thread.getName());
            // 设置为守护线程，应用退出时自动销毁，避免内存泄漏
            thread.setDaemon(true);
            return thread;
        }
    };

    // 私有构造方法：单例模式，禁止外部实例化
    private ThreadPoolManager() {
        // 创建核心线程池（ThreadPoolExecutor是Java线程池的核心实现，避免使用Executors默认方法）
        mThreadPool = new ThreadPoolExecutor(
                CORE_POOL_SIZE,
                MAX_POOL_SIZE,
                KEEP_ALIVE_TIME,
                TimeUnit.SECONDS,
                new LinkedBlockingQueue<>(WORK_QUEUE_SIZE),
                sThreadFactory,
                // 任务拒绝策略：当线程池+队列满时，在调用者线程执行（避免任务直接丢弃，适配Android）
                new ThreadPoolExecutor.CallerRunsPolicy()
        );
        // 主线程Handler（Looper.getMainLooper()保证获取的是UI线程的Looper）
        mMainHandler = new Handler(Looper.getMainLooper());
        // 线程安全的任务映射表
        mTaskMap = new ConcurrentHashMap<>();
    }

    // 双重校验锁单例：保证线程安全，懒加载
    public static ThreadPoolManager getInstance() {
        if (sInstance == null) {
            synchronized (ThreadPoolManager.class) {
                if (sInstance == null) {
                    sInstance = new ThreadPoolManager();
                }
            }
        }
        return sInstance;
    }

    // ------------------------ 基础任务提交：无返回值，无回调 ------------------------
    /**
     * 提交普通无返回值任务
     * @param runnable 待执行的任务
     */
    public void execute(Runnable runnable) {
        if (runnable == null) return;
        try {
            java.util.concurrent.Future<?> future = mThreadPool.submit(runnable);
            mTaskMap.put(runnable, future);
        } catch (Exception e) {
            Log.e(TAG, "提交任务失败：" + e.getMessage(), e);
            // 捕获异常，避免线程池崩溃
            handleException(e);
        }
    }

    // ------------------------ 带结果回调的任务：自动切换主线程 ------------------------
    /**
     * 提交带结果的任务，回调自动在主线程执行
     * @param callable 带返回值的任务（Callable<T> 相比Runnable支持返回值和异常抛出）
     * @param callback 结果回调（成功/失败，均在UI线程执行）
     * @param <T>      结果泛型
     */
    public <T> void execute(java.util.concurrent.Callable<T> callable, final Callback<T> callback) {
        if (callable == null || callback == null) return;
        execute(new Runnable() {
            @Override
            public void run() {
                T result = null;
                Exception exception = null;
                try {
                    // 执行耗时任务，获取结果
                    result = callable.call();
                } catch (Exception e) {
                    exception = e;
                    LogUtil.e(TAG, "带结果任务执行失败：" + e.getMessage(), e);
                } finally {
                    // 最终将结果通过主线程Handler切换到UI线程
                    final T finalResult = result;
                    final Exception finalException = exception;
                    mMainHandler.post(new Runnable() {
                        @Override
                        public void run() {
                            if (finalException == null) {
                                callback.onSuccess(finalResult);
                            } else {
                                callback.onFailure(finalException);
                            }
                        }
                    });
                }
            }
        });
    }

    // ------------------------ 任务取消 & 线程池管理 ------------------------
    /**
     * 取消单个任务
     * @param runnable 要取消的任务
     * @param mayInterruptIfRunning 是否中断正在运行的任务（true：立即中断，false：等待任务执行完成）
     * @return 是否取消成功
     */
    public boolean cancelTask(Runnable runnable, boolean mayInterruptIfRunning) {
        if (runnable == null || !mTaskMap.containsKey(runnable)) return false;
        try {
            java.util.concurrent.Future<?> future = mTaskMap.get(runnable);
            boolean isCancelled = future.cancel(mayInterruptIfRunning);
            if (isCancelled) {
                mTaskMap.remove(runnable);
                LogUtil.d(TAG, "任务取消成功：" + runnable.toString());
            }
            return isCancelled;
        } catch (Exception e) {
            LogUtil.e(TAG, "取消任务失败：" + e.getMessage(), e);
            return false;
        }
    }

    /**
     * 取消所有任务
     * @param mayInterruptIfRunning 是否中断正在运行的任务
     */
    public void cancelAllTasks(boolean mayInterruptIfRunning) {
        for (java.util.concurrent.Future<?> future : mTaskMap.values()) {
            future.cancel(mayInterruptIfRunning);
        }
        mTaskMap.clear();
        LogUtil.d(TAG, "所有任务已取消，共取消：" + mTaskMap.size() + "个");
    }

    /**
     * 关闭线程池（谨慎使用！应用退出时调用，关闭后无法再提交任务）
     * 步骤：1. 停止接收新任务 2. 尝试中断正在运行的任务 3. 等待队列任务执行完成 4. 回收线程
     */
    public void shutdown() {
        if (!mThreadPool.isShutdown()) {
            cancelAllTasks(true);
            mThreadPool.shutdown();
            LogUtil.d(TAG, "线程池已关闭");
        }
    }

    /**
     * 立即关闭线程池（强制关闭，不等待队列任务执行）
     * @return 未执行的任务列表
     */
    public java.util.List<Runnable> shutdownNow() {
        cancelAllTasks(true);
        java.util.List<Runnable> unExecutedTasks = mThreadPool.shutdownNow();
        LogUtil.d(TAG, "线程池立即关闭，未执行的任务数：" + unExecutedTasks.size());
        return unExecutedTasks;
    }

    /**
     * 检查线程池是否已关闭
     */
    public boolean isShutdown() {
        return mThreadPool.isShutdown();
    }

    // ------------------------ 内部工具方法 & 回调接口 ------------------------
    // 处理任务提交异常（如线程池已满、任务为null等）
    private void handleException(Exception e) {
        // 可根据业务需求扩展：如弹Toast、上报埋点等
        mMainHandler.post(new Runnable() {
            @Override
            public void run() {
                // 主线程处理异常（如UI提示）
//                Toast.makeText(AppContext.getInstance(), "任务执行异常：" + e.getMessage(), Toast.LENGTH_SHORT).show();
            }
        });
    }

    /**
     * 任务结果回调接口（所有方法均在**主线程/UI线程**执行）
     * @param <T> 回调结果的泛型
     */
    public interface Callback<T> {
        /**
         * 任务执行成功
         * @param result 任务执行结果
         */
        void onSuccess(T result);

        /**
         * 任务执行失败
         * @param e 异常信息
         */
        void onFailure(Exception e);
    }

    // 供外部获取主线程Handler（可选，方便其他地方切换主线程）
    public Handler getMainHandler() {
        return mMainHandler;
    }
}