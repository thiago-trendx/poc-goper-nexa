package com.sunway.l850tdemo.viewmodel;

import androidx.lifecycle.MutableLiveData;

import java.util.Objects;

/** desc： 去重，值相等时不回调
 * create at 2026/3/21 11:55 by liuxiong
 */
public class DistinctLiveData<T> extends MutableLiveData<T> {

    public DistinctLiveData() {
        super();
    }

    public DistinctLiveData(T initialValue) {
        super(initialValue);
    }

    @Override
    public void setValue(T value) {
        // 与当前值相同则跳过，不触发回调
        if (!Objects.equals(getValue(), value)) {
            super.setValue(value);
        }
    }

    @Override
    public void postValue(T value) {
        if (!Objects.equals(getValue(), value)) {
            super.postValue(value);
        }
    }
}