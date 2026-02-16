package com.szurubooru.szuruqueue

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Outline
import android.graphics.PixelFormat
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewOutlineProvider
import android.view.WindowManager
import android.view.animation.DecelerateInterpolator
import android.view.animation.OvershootInterpolator
import android.widget.FrameLayout
import android.widget.ImageView
import android.animation.ObjectAnimator
import android.animation.ValueAnimator
import androidx.appcompat.content.res.AppCompatResources
import androidx.appcompat.widget.AppCompatImageView
import androidx.core.content.ContextCompat
import kotlin.math.abs

/**
 * Shared bubble overlay UI: frosted circle background, app icon, touch (drag/snap/tap),
 * entry animation, haptic on tap. Used by CompanionForegroundService and FloatingBubbleService.
 */
object BubbleOverlayHelper {

    private const val BUBBLE_SIZE_DP = 56
    private const val CLICK_THRESHOLD = 10
    private const val ELEVATION_DEFAULT = 12f
    private const val ELEVATION_PRESSED = 16f
    private const val INITIAL_Y_DP = 200

    /**
     * Loads the bubble icon (app launcher icon) in a way that works from Service context.
     * Rasterizes to bitmap so it displays at the correct size with no theme substitution.
     */
    private fun loadBubbleIcon(context: Context, sizePx: Int): Drawable? {
        val drawable = AppCompatResources.getDrawable(context, R.mipmap.ic_launcher)
            ?: ContextCompat.getDrawable(context, R.mipmap.ic_launcher) ?: return null
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        drawable.setBounds(0, 0, sizePx, sizePx)
        drawable.draw(canvas)
        return BitmapDrawable(context.resources, bitmap)
    }

    /**
     * Creates the bubble view and layout params. Caller must add the view with
     * windowManager.addView(view, params) then call [runEntryAnimation] on the view.
     */
    fun createBubbleView(
        context: Context,
        windowManager: WindowManager,
        onTap: () -> Unit
    ): Pair<View, WindowManager.LayoutParams> {
        val density = context.resources.displayMetrics.density
        val sizePx = (BUBBLE_SIZE_DP * density).toInt().coerceAtLeast(1)
        val initialY = (INITIAL_Y_DP * density).toInt()

        val container = FrameLayout(context).apply {
            setBackgroundResource(R.drawable.bubble_background)
            elevation = ELEVATION_DEFAULT
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    val w = if (view.width > 0) view.width else sizePx
                    val h = if (view.height > 0) view.height else sizePx
                    outline.setOval(0, 0, w, h)
                }
            }
            clipToOutline = true
        }

        val iconDrawable = loadBubbleIcon(context, (24 * density).toInt())
        val icon = AppCompatImageView(context).apply {
            setImageDrawable(iconDrawable)
            imageTintList = null
            scaleType = ImageView.ScaleType.FIT_CENTER
            val padding = (12 * density).toInt()
            setPadding(padding, padding, padding, padding)
            outlineProvider = object : ViewOutlineProvider() {
                override fun getOutline(view: View, outline: Outline) {
                    val w = if (view.width > 0) view.width else sizePx
                    val h = if (view.height > 0) view.height else sizePx
                    outline.setOval(0, 0, w, h)
                }
            }
            clipToOutline = true
        }

        container.addView(icon, FrameLayout.LayoutParams(sizePx, sizePx).apply {
            gravity = Gravity.CENTER
        })

        val params = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = initialY
        }

        val displayMetrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getMetrics(displayMetrics)

        container.setOnTouchListener(BubbleTouchListener(
            params = params,
            windowManager = windowManager,
            displayMetrics = displayMetrics,
            onTap = {
                container.performHapticFeedback(android.view.HapticFeedbackConstants.CONFIRM)
                runTapAnimation(container)
                container.postDelayed(onTap, 150)
            }
        ))

        return Pair(container, params)
    }

    /**
     * Run entry animation (scale + fade in). Call after addView.
     */
    fun runEntryAnimation(view: View) {
        view.scaleX = 0.6f
        view.scaleY = 0.6f
        view.alpha = 0f
        ObjectAnimator.ofFloat(view, "scaleX", 0.6f, 1f).apply {
            duration = 220
            interpolator = OvershootInterpolator(1.1f)
            start()
        }
        ObjectAnimator.ofFloat(view, "scaleY", 0.6f, 1f).apply {
            duration = 220
            interpolator = OvershootInterpolator(1.1f)
            start()
        }
        ObjectAnimator.ofFloat(view, "alpha", 0f, 1f).apply {
            duration = 200
            start()
        }
    }

    private fun runTapAnimation(v: View) {
        ObjectAnimator.ofFloat(v, "scaleX", 1f, 0.85f, 1.15f, 1f).apply {
            duration = 400
            interpolator = OvershootInterpolator(2f)
            start()
        }
        ObjectAnimator.ofFloat(v, "scaleY", 1f, 0.85f, 1.15f, 1f).apply {
            duration = 400
            interpolator = OvershootInterpolator(2f)
            start()
        }
        ObjectAnimator.ofFloat(v, "elevation", v.elevation, 24f, ELEVATION_DEFAULT).apply {
            duration = 400
            start()
        }
        ObjectAnimator.ofFloat(v, "alpha", 1f, 0.7f, 1f).apply {
            duration = 300
            start()
        }
    }

    private class BubbleTouchListener(
        private val params: WindowManager.LayoutParams,
        private val windowManager: WindowManager,
        private val displayMetrics: DisplayMetrics,
        private val onTap: () -> Unit
    ) : View.OnTouchListener {

        private var initialX = 0
        private var initialY = 0
        private var initialTouchX = 0f
        private var initialTouchY = 0f
        private var moved = false

        override fun onTouch(v: View, event: MotionEvent): Boolean {
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params.x
                    initialY = params.y
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    moved = false
                    ObjectAnimator.ofFloat(v, "scaleX", 1f, 1.2f).apply {
                        duration = 150
                        interpolator = OvershootInterpolator()
                        start()
                    }
                    ObjectAnimator.ofFloat(v, "scaleY", 1f, 1.2f).apply {
                        duration = 150
                        interpolator = OvershootInterpolator()
                        start()
                    }
                    v.elevation = ELEVATION_PRESSED
                    return true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (abs(dx) > CLICK_THRESHOLD || abs(dy) > CLICK_THRESHOLD) moved = true
                    val newX = initialX + dx.toInt()
                    val newY = initialY + dy.toInt()
                    val screenHeight = displayMetrics.heightPixels
                    val bubbleHeight = v.height
                    val constrainedY = newY.coerceIn(0, screenHeight - bubbleHeight)
                    params.x = newX
                    params.y = constrainedY
                    windowManager.updateViewLayout(v, params)
                    return true
                }
                MotionEvent.ACTION_UP -> {
                    if (!moved) {
                        ObjectAnimator.ofFloat(v, "scaleX", v.scaleX, 1f).apply {
                            duration = 150
                            interpolator = DecelerateInterpolator()
                            start()
                        }
                        ObjectAnimator.ofFloat(v, "scaleY", v.scaleY, 1f).apply {
                            duration = 150
                            interpolator = DecelerateInterpolator()
                            start()
                        }
                        v.elevation = ELEVATION_DEFAULT
                        onTap()
                    } else {
                        ObjectAnimator.ofFloat(v, "scaleX", v.scaleX, 1f).apply {
                            duration = 200
                            interpolator = DecelerateInterpolator()
                            start()
                        }
                        ObjectAnimator.ofFloat(v, "scaleY", v.scaleY, 1f).apply {
                            duration = 200
                            interpolator = DecelerateInterpolator()
                            start()
                        }
                        v.elevation = ELEVATION_DEFAULT
                        snapToNearestSide(v)
                    }
                    v.performClick()
                    return true
                }
            }
            return false
        }

        private fun snapToNearestSide(v: View) {
            val screenWidth = displayMetrics.widthPixels
            val screenHeight = displayMetrics.heightPixels
            val bubbleWidth = v.width
            val bubbleHeight = v.height
            val centerX = screenWidth / 2
            val currentX = params.x
            val targetX = if (currentX < centerX) 0 else screenWidth - bubbleWidth
            val currentY = params.y
            val targetY = currentY.coerceIn(0, screenHeight - bubbleHeight)
            val startX = currentX.toFloat()
            val startY = currentY.toFloat()
            val endX = targetX.toFloat()
            val endY = targetY.toFloat()

            ValueAnimator.ofFloat(0f, 1f).apply {
                duration = 320
                interpolator = OvershootInterpolator(1.25f)
                addUpdateListener { animation ->
                    val f = animation.animatedValue as Float
                    params.x = (startX + (endX - startX) * f).toInt()
                    params.y = (startY + (endY - startY) * f).toInt()
                    windowManager.updateViewLayout(v, params)
                    when {
                        f >= 1f -> {
                            v.scaleX = 1f
                            v.scaleY = 1f
                        }
                        f < 0.35f -> {
                            val s = 1f - 0.08f * (f / 0.35f)
                            v.scaleX = s
                            v.scaleY = s
                        }
                        f < 0.8f -> {
                            val s = 0.92f + 0.14f * (f - 0.35f) / 0.45f
                            v.scaleX = s
                            v.scaleY = s
                        }
                        else -> {
                            val s = 1.06f - 0.06f * (f - 0.8f) / 0.2f
                            v.scaleX = s
                            v.scaleY = s
                        }
                    }
                }
                start()
            }
        }
    }
}
