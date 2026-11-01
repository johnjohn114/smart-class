package com.announcementzone.app

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.Shader
import android.view.View
import android.view.animation.LinearInterpolator

class SplashScreenView(context: Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private var rotation = 0f
    private val animator = ValueAnimator.ofFloat(0f, 360f).apply {
        duration = 2600L
        repeatCount = ValueAnimator.INFINITE
        interpolator = LinearInterpolator()
        addUpdateListener {
            rotation = it.animatedValue as Float
            invalidate()
        }
    }

    init {
        setLayerType(View.LAYER_TYPE_SOFTWARE, null)
        animator.start()
    }

    fun stopAnimation() {
        if (animator.isRunning) animator.cancel()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val w = width.toFloat()
        val h = height.toFloat()
        if (w <= 0f || h <= 0f) return

        val bg = android.graphics.LinearGradient(0f, 0f, w, h,
            intArrayOf(Color.rgb(2, 9, 31), Color.rgb(3, 28, 78), Color.rgb(1, 8, 28)),
            null, Shader.TileMode.CLAMP)
        paint.shader = bg
        canvas.drawRect(0f, 0f, w, h, paint)
        paint.shader = null

        val cx = w / 2f
        val cy = h * 0.39f
        // Soft central blue glow
        paint.shader = RadialGradient(cx, cy, w * 0.48f,
            intArrayOf(0x66308FFF, 0x22205DCC, Color.TRANSPARENT), null, Shader.TileMode.CLAMP)
        canvas.drawCircle(cx, cy, w * 0.48f, paint)
        paint.shader = null

        // Subtle digital star field
        paint.color = 0x6652A9FF
        paint.style = Paint.Style.FILL
        for (i in 0..85) {
            val x = ((i * 83L + 29L) % 997L) / 997f * w
            val y = ((i * 137L + 61L) % 991L) / 991f * h
            canvas.drawCircle(x, y, if (i % 7 == 0) 2.2f else 1.1f, paint)
        }

        // Rotating holographic rings
        canvas.save()
        canvas.rotate(rotation, cx, cy)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2.2f
        paint.color = 0xCC25BFFF.toInt()
        canvas.drawOval(cx - w * .34f, cy - w * .13f, cx + w * .34f, cy + w * .13f, paint)
        paint.strokeWidth = 1f
        paint.color = 0x8857AFFF.toInt()
        canvas.drawOval(cx - w * .39f, cy - w * .16f, cx + w * .39f, cy + w * .16f, paint)
        canvas.restore()

        // Glowing platform
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 3f
        paint.color = 0xFF25BFFF.toInt()
        canvas.drawOval(cx - w * .37f, cy + w * .12f, cx + w * .37f, cy + w * .22f, paint)
        paint.strokeWidth = 1f
        paint.color = 0x8875D9FF.toInt()
        canvas.drawOval(cx - w * .43f, cy + w * .105f, cx + w * .43f, cy + w * .235f, paint)

        // Document tile
        val card = Path().apply {
            moveTo(cx - w*.19f, cy - w*.20f)
            quadTo(cx - w*.19f, cy - w*.23f, cx - w*.16f, cy - w*.23f)
            lineTo(cx + w*.13f, cy - w*.23f)
            quadTo(cx + w*.17f, cy - w*.23f, cx + w*.17f, cy - w*.19f)
            lineTo(cx + w*.17f, cy + w*.045f)
            quadTo(cx + w*.17f, cy + w*.08f, cx + w*.13f, cy + w*.08f)
            lineTo(cx - w*.15f, cy + w*.08f)
            quadTo(cx - w*.19f, cy + w*.08f, cx - w*.19f, cy + w*.04f)
            close()
        }
        paint.style = Paint.Style.FILL
        paint.color = 0xFF087FEA.toInt()
        canvas.drawRoundRect(cx - w*.205f, cy - w*.245f, cx + w*.185f, cy + w*.10f, 22f, 22f, paint)
        paint.color = 0xFFEAF7FF.toInt()
        canvas.drawPath(card, paint)
        paint.color = 0xFF0875D9.toInt()
        paint.strokeWidth = 5f
        paint.strokeCap = Paint.Cap.ROUND
        paint.style = Paint.Style.STROKE
        for (i in 0..2) {
            val yy = cy - w*.12f + i*w*.075f
            canvas.drawLine(cx - w*.12f, yy, cx + w*(if (i == 1) .04f else .09f), yy, paint)
        }
        // Orange bookmark
        paint.style = Paint.Style.FILL
        paint.color = 0xFFFFA52E.toInt()
        val bookmark = Path().apply {
            moveTo(cx - w*.13f, cy - w*.245f); lineTo(cx - w*.055f, cy - w*.245f)
            lineTo(cx - w*.055f, cy - w*.13f); lineTo(cx - w*.092f, cy - w*.155f)
            lineTo(cx - w*.13f, cy - w*.13f); close()
        }
        canvas.drawPath(bookmark, paint)

        // Small megaphone motif
        paint.color = Color.WHITE
        canvas.drawRoundRect(cx + w*.12f, cy - w*.015f, cx + w*.28f, cy + w*.065f, 12f, 12f, paint)
        paint.color = 0xFF36B9FF.toInt()
        canvas.drawCircle(cx + w*.13f, cy + w*.025f, w*.038f, paint)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 3f
        paint.color = 0xFFFFB64A.toInt()
        canvas.drawArc(cx + w*.24f, cy - w*.11f, cx + w*.39f, cy + w*.17f, -65f, 130f, false, paint)

        // Brand title and subtitle
        paint.style = Paint.Style.FILL
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.BOLD)
        paint.color = Color.WHITE
        paint.textSize = w * .083f
        canvas.drawText("事項公告區", cx, h * .61f, paint)
        paint.typeface = android.graphics.Typeface.create("sans-serif", android.graphics.Typeface.NORMAL)
        paint.textSize = w * .034f
        paint.color = 0xFFD5E9FF.toInt()
        canvas.drawText("即時公告・重要訊息・一手掌握", cx, h * .655f, paint)

        // Animated loading arc
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 5f
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = 0x553B9DFF
        canvas.drawCircle(cx, h*.77f, w*.055f, paint)
        paint.color = 0xFF39BFFF.toInt()
        canvas.drawArc(cx - w*.055f, h*.77f - w*.055f, cx + w*.055f, h*.77f + w*.055f,
            rotation, 105f, false, paint)
        paint.style = Paint.Style.FILL
        paint.textSize = w * .043f
        paint.color = 0xFFEAF5FF.toInt()
        canvas.drawText("載入中…", cx, h*.84f, paint)

        // Bottom horizon line
        paint.color = 0x9935BFFF.toInt()
        paint.strokeWidth = 1.5f
        canvas.drawLine(0f, h*.93f, w, h*.93f, paint)
    }
}
