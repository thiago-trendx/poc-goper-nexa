package com.sunway.l850tdemo.dialog;

import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Paint;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.recyclerview.widget.RecyclerView;

/**
 * WiFi 列表条目间的分割线
 *
 * 设计规格：
 *  - 颜色：半透明白色 #33FFFFFF（与深色背景对比适中）
 *  - 高度：1px（物理像素，与布局中 px 单位保持一致）
 *  - 左右边距：0（铺满，与 wifi_item_bg_rect 直角边对齐）
 *  - 最后一条不画线（防止与外部容器底边重叠）
 */
public class WifiDividerDecoration extends RecyclerView.ItemDecoration {

    private static final int   DIVIDER_HEIGHT_PX = 1;
    private static final int   DIVIDER_COLOR     = 0x33FFFFFF; // 20% 白

    private final Paint paint;

    public WifiDividerDecoration(Context context) {
        paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        paint.setColor(DIVIDER_COLOR);
        paint.setStyle(Paint.Style.FILL);
    }

    @Override
    public void onDraw(@NonNull Canvas c, @NonNull RecyclerView parent,
                       @NonNull RecyclerView.State state) {
        int childCount = parent.getChildCount();
        int left  = parent.getPaddingLeft();
        int right = parent.getWidth() - parent.getPaddingRight();

        for (int i = 0; i < childCount - 1; i++) {   // 最后一条不画
            View child = parent.getChildAt(i);
            int bottom = child.getBottom();
            c.drawRect(left, bottom, right, bottom + DIVIDER_HEIGHT_PX, paint);
        }
    }

    @Override
    public void getItemOffsets(@NonNull android.graphics.Rect outRect,
                               @NonNull View view,
                               @NonNull RecyclerView parent,
                               @NonNull RecyclerView.State state) {
        int position  = parent.getChildAdapterPosition(view);
        int itemCount = parent.getAdapter() != null ? parent.getAdapter().getItemCount() : 0;
        // 最后一条不占偏移，其余每条底部留出分割线高度
        if (position < itemCount - 1) {
            outRect.bottom = DIVIDER_HEIGHT_PX;
        }
    }
}