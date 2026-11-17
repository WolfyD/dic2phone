package com.dic2phone.ui

import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.TextPaint
import android.text.TextUtils
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toArgb
import kotlin.math.cos
import kotlin.math.sin

/**
 * Deck artwork drawn on a plain android.graphics.Canvas, so the same code renders in the
 * Compose UI (via nativeCanvas) and in the live wallpaper.
 */
object DeckArt {
    const val CASSETTE_RATIO = 1.58f
    const val VU_RATIO = 5.6f

    /** Bold and regular typewriter lettering; App swaps in the bundled Courier Prime at start-up. */
    var mono: Typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
    var monoPlain: Typeface = Typeface.MONOSPACE
    /** Badge lettering (brand plate, side letter); App swaps in the bundled Barlow at start-up. */
    var sans: Typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
    var brandFace: Typeface = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD_ITALIC)

    /** Handwriting for the user's own label text; App swaps in the bundled pen font at start-up. */
    var hand: Typeface = Typeface.create("casual", Typeface.NORMAL)
    /** The user's label text typed (typewriter) instead of handwritten. Mirrors [com.dic2phone.Prefs.labelTyped]. */
    @Volatile var typedLabels = false

    private fun Color.a(alpha: Float) = copy(alpha = alpha).toArgb()
    private val Color.i get() = toArgb()

    /** Background gradient (+ synthwave grid). */
    fun background(c: Canvas, w: Float, h: Float, p: Palette) {
        val pt = Paint(Paint.ANTI_ALIAS_FLAG)
        pt.shader = LinearGradient(0f, 0f, 0f, h, p.bgTop.i, p.bgBottom.i, Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, w, h, pt)
        pt.shader = null
        val grid = p.grid ?: return
        // Perspective grid on the lower 40%
        val horizon = h * 0.6f
        pt.style = Paint.Style.STROKE
        pt.strokeWidth = 2f
        pt.color = grid.a(0.35f)
        c.drawLine(0f, horizon, w, horizon, pt)
        var y = 6f
        while (horizon + y < h) {
            c.drawLine(0f, horizon + y, w, horizon + y, pt)
            y *= 1.35f
        }
        val vx = w / 2
        for (i in -12..12) {
            c.drawLine(vx + i * w * 0.02f, horizon, vx + i * w * 0.35f, h, pt)
        }
        // Sun
        pt.style = Paint.Style.FILL
        pt.shader = LinearGradient(0f, horizon - w * .3f, 0f, horizon, 0xFFFFD319.toInt(), 0xFFFF2975.toInt(), Shader.TileMode.CLAMP)
        pt.alpha = 70
        c.save()
        c.clipRect(0f, 0f, w, horizon)
        c.drawCircle(vx, horizon, w * .3f, pt)
        c.restore()
    }

    /** Shrinks the text size (down to [min]) so [text] fits [maxW]; ellipsizes if it still doesn't. */
    private fun fit(tp: TextPaint, text: String, maxW: Float, max: Float, min: Float): String {
        tp.textSize = max
        val m = tp.measureText(text)
        if (m > maxW) tp.textSize = maxOf(min, max * maxW / m)
        return TextUtils.ellipsize(text, tp, maxW, TextUtils.TruncateAt.END).toString()
    }

    /** Pen colour for writing on [p]'s label: black fineliner on light labels, silver paint pen on dark ones. */
    private fun penInk(p: Palette): Int =
        if (p.label.luminance() > .4f) 0xFF15161C.toInt() else 0xFFE6E2D8.toInt()

    /**
     * Writes [text] by hand on a ruled line: pen font, the line slightly askew, every letter a
     * little off in size, height, tilt and ink. Seeded from the text so it doesn't jitter on redraw.
     */
    private fun scrawl(c: Canvas, p: Palette, text: String, x: Float, line: Float, maxW: Float, max: Float, min: Float) {
        if (typedLabels) return type(c, p, text, x, line, maxW, max * .62f, min * .68f)
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG)
        tp.typeface = hand; tp.color = penInk(p)
        val t = fit(tp, text, maxW * .97f, max, min)
        val size = tp.textSize
        val rnd = java.util.Random(t.hashCode().toLong() * 31 + 7)
        val base = line - size * .10f
        c.save()
        c.rotate(-1.6f + rnd.nextFloat() * 1.4f, x, base)
        var cx = x
        var i = 0
        while (i < t.length) {
            val n = Character.charCount(t.codePointAt(i))
            val g = t.substring(i, i + n)
            i += n
            tp.textSize = size
            val adv = tp.measureText(g)
            tp.textSize = size * (.93f + rnd.nextFloat() * .14f)
            tp.alpha = 205 + rnd.nextInt(51)
            val dy = (rnd.nextFloat() - .5f) * size * .08f
            c.save()
            c.rotate((rnd.nextFloat() - .5f) * 7f, cx + adv / 2, base)
            c.drawText(g, cx, base + dy, tp)
            c.restore()
            cx += adv
        }
        c.restore()
    }

    /**
     * Types [text] on the label like an old typewriter: straight line, but each letter struck a
     * little harder or softer and a hair above or below the line. Seeded from the text.
     */
    private fun type(c: Canvas, p: Palette, text: String, x: Float, line: Float, maxW: Float, max: Float, min: Float) {
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG)
        tp.typeface = monoPlain; tp.color = penInk(p)
        val t = fit(tp, text, maxW, max, min)
        val rnd = java.util.Random(t.hashCode().toLong() * 17 + 3)
        val base = line - tp.descent() * .6f
        var cx = x
        var i = 0
        while (i < t.length) {
            val n = Character.charCount(t.codePointAt(i))
            val g = t.substring(i, i + n)
            i += n
            val adv = tp.measureText(g)
            tp.alpha = 150 + rnd.nextInt(106)
            val dy = (rnd.nextFloat() - .5f) * tp.textSize * .07f
            c.drawText(g, cx, base + dy, tp)
            // a heavier strike sometimes doubles up the ink slightly
            if (rnd.nextInt(5) == 0) { tp.alpha = 60; c.drawText(g, cx + tp.textSize * .02f, base + dy, tp) }
            cx += adv
        }
    }

    /**
     * The deck's medium in a [CASSETTE_RATIO] box of width [w]: the cassette, or a MiniDisc
     * centred in the same box (so every layout works with either). [running] = recording/playing.
     */
    fun media(
        c: Canvas, w: Float, p: Palette, label: String, sub: String,
        angle: Float, progress: Float, running: Boolean, disc: Boolean, handwritten: Boolean = false,
    ) {
        if (!disc) return cassette(c, w, p, label, sub, angle, progress, handwritten = handwritten)
        val h = w / CASSETTE_RATIO
        val mh = h * .98f
        val mw = mh * MD_RATIO
        c.save()
        c.translate((w - mw) / 2, (h - mh) / 2)
        minidisc(c, mw, p, label, sub, angle * 3f, running, handwritten)
        c.restore()
    }

    /** MiniDisc cartridge proportions (68 x 72 mm). */
    const val MD_RATIO = 68f / 72f

    /**
     * MiniDisc at (0,0) with width [w]: label on top, metal shutter below. While [open] the
     * shutter is slid aside and the disc spins in the slot.
     */
    fun minidisc(
        c: Canvas, w: Float, p: Palette, label: String, sub: String, angle: Float, open: Boolean,
        handwritten: Boolean = false,
    ) {
        val h = w / MD_RATIO
        val pt = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = w * .04f
        val cut = w * .08f
        val body = Path().apply {
            moveTo(cut, 0f); lineTo(w - r, 0f); quadTo(w, 0f, w, r)
            lineTo(w, h - r); quadTo(w, h, w - r, h)
            lineTo(r, h); quadTo(0f, h, 0f, h - r)
            lineTo(0f, cut); close()
        }
        pt.shader = LinearGradient(0f, 0f, w, h, p.shell1.i, p.shell2.i, Shader.TileMode.CLAMP)
        c.drawPath(body, pt)
        pt.shader = LinearGradient(0f, 0f, 0f, h * .3f, Color.White.a(.10f), Color.White.a(0f), Shader.TileMode.CLAMP)
        c.drawPath(body, pt)
        pt.shader = null
        pt.style = Paint.Style.STROKE; pt.strokeWidth = w * .008f; pt.color = Color.White.a(.12f)
        c.drawPath(body, pt)
        pt.style = Paint.Style.FILL

        // Label
        val lx = w * .08f; val ly = h * .07f; val lw = w * .84f; val lh = h * .40f
        pt.color = p.label.i
        c.drawRoundRect(lx, ly, lx + lw, ly + lh, w * .02f, w * .02f, pt)
        val bandH = lh * .16f
        val bandTop = ly + lh - bandH - lh * .06f
        p.stripes.forEachIndexed { i, col ->
            pt.color = col.i
            c.drawRect(lx, bandTop + i * bandH / p.stripes.size, lx + lw, bandTop + (i + 1) * bandH / p.stripes.size + .5f, pt)
        }
        val textX = lx + lw * .06f
        val textW = lw * .88f
        val line1 = ly + lh * .40f
        val line2 = ly + lh * .66f
        pt.color = p.ink.a(.35f); pt.strokeWidth = 1.5f
        c.drawLine(textX, line1, textX + textW, line1, pt)
        c.drawLine(textX, line2, textX + textW, line2, pt)
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG)
        if (handwritten) scrawl(c, p, label, textX, line1, textW, h * .13f, h * .075f)
        else {
            tp.color = p.ink.i; tp.typeface = mono
            c.drawText(fit(tp, label, textW, h * .085f, h * .05f), textX, line1 - tp.descent() - 1f, tp)
        }
        tp.typeface = monoPlain; tp.color = p.ink.a(.8f)
        c.drawText(fit(tp, sub, textW, h * .05f, h * .038f), textX, line2 - tp.descent() - 1f, tp)
        // insertion arrow
        val ax = lx + lw * .5f; val ay = ly * .5f
        pt.color = Color.White.a(.35f)
        c.drawPath(Path().apply {
            moveTo(ax, ay - h * .018f); lineTo(ax + w * .03f, ay + h * .015f); lineTo(ax - w * .03f, ay + h * .015f); close()
        }, pt)

        // Shutter slot, and the disc behind it
        val slot = RectF(w * .08f, h * .53f, w * .76f, h * .93f)
        val slotPath = Path().apply { addRoundRect(slot, w * .015f, w * .015f, Path.Direction.CW) }
        pt.color = Color.Black.a(.55f)
        c.drawPath(slotPath, pt)
        if (open) {
            c.save(); c.clipPath(slotPath)
            val dcx = w * .5f; val dcy = h * .5f; val dr = w * .47f
            pt.color = p.window.i
            c.drawCircle(dcx, dcy, dr, pt)
            // iridescent data surface; turning the gradient makes the spin visible
            c.save(); c.rotate(angle, dcx, dcy)
            pt.shader = android.graphics.SweepGradient(
                dcx, dcy,
                intArrayOf(
                    0x40FFFFFF, 0x10FFFFFF, 0x3366CCFF, 0x10FFFFFF, 0x30FF66CC,
                    0x10FFFFFF, 0x38FFE066, 0x10FFFFFF, 0x40FFFFFF
                ), null
            )
            c.drawCircle(dcx, dcy, dr * .97f, pt)
            pt.shader = null
            c.restore()
            pt.style = Paint.Style.STROKE; pt.strokeWidth = w * .006f; pt.color = Color.White.a(.25f)
            c.drawCircle(dcx, dcy, dr * .97f, pt)
            c.drawCircle(dcx, dcy, dr * .40f, pt)
            pt.style = Paint.Style.FILL
            c.restore()
        }
        // The shutter: closed over the slot, or slid right (tucked under the body edge).
        c.save(); c.clipPath(body)
        val sx = if (open) slot.width() * .78f else 0f
        val sh = RectF(slot.left + sx - w * .01f, slot.top - h * .01f, slot.right + sx + w * .01f, slot.bottom + h * .01f)
        pt.shader = LinearGradient(0f, sh.top, 0f, sh.bottom,
            intArrayOf(0xFFE4E6E9.toInt(), 0xFFA9ADB3.toInt(), 0xFFCDD0D4.toInt(), 0xFF8C9096.toInt()), null, Shader.TileMode.CLAMP)
        c.drawRoundRect(sh, w * .015f, w * .015f, pt)
        pt.shader = null
        pt.color = Color.Black.a(.18f); pt.strokeWidth = h * .006f
        for (k in 1..3) {
            val gy = sh.top + sh.height() * (.2f + k * .08f)
            c.drawLine(sh.left + sh.width() * .08f, gy, sh.left + sh.width() * .5f, gy, pt)
        }
        pt.style = Paint.Style.STROKE; pt.strokeWidth = w * .005f; pt.color = Color.Black.a(.4f)
        c.drawRoundRect(sh, w * .015f, w * .015f, pt)
        pt.style = Paint.Style.FILL
        c.restore()

        // Write-protect tab + length
        pt.color = Color.Black.a(.5f)
        c.drawRoundRect(w * .82f, h * .56f, w * .91f, h * .64f, w * .01f, w * .01f, pt)
        pt.color = p.hub.a(.8f)
        c.drawRoundRect(w * .83f, h * .57f, w * .86f, h * .63f, w * .005f, w * .005f, pt)
        tp.typeface = mono; tp.textSize = h * .055f; tp.color = Color.White.a(.45f); tp.textAlign = Paint.Align.CENTER
        c.drawText("74", w * .865f, h * .80f, tp)
        tp.typeface = monoPlain; tp.textSize = h * .03f
        c.drawText("MIN", w * .865f, h * .85f, tp)
    }

    /** Cassette at (0,0) with width [w]. */
    fun cassette(
        c: Canvas, w: Float, p: Palette, label: String, sub: String,
        angle: Float, progress: Float, side: String = "A", handwritten: Boolean = false,
    ) {
        val h = w / CASSETTE_RATIO
        val pt = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = w * 0.035f

        // Shell
        pt.shader = LinearGradient(0f, 0f, 0f, h, p.shell1.i, p.shell2.i, Shader.TileMode.CLAMP)
        c.drawRoundRect(0f, 0f, w, h, r, r, pt)
        pt.shader = null
        pt.style = Paint.Style.STROKE; pt.strokeWidth = w * 0.006f; pt.color = Color.White.a(.08f)
        c.drawRoundRect(0f, 0f, w, h, r, r, pt)
        pt.style = Paint.Style.FILL

        // Label
        val lx = w * .07f; val ly = h * .07f; val lw = w * .86f; val lh = h * .64f
        pt.color = p.label.i
        c.drawRoundRect(lx, ly, lx + lw, ly + lh, w * .015f, w * .015f, pt)
        val bandTop = ly + lh * .40f
        val bandH = lh * .52f
        val n = p.stripes.size
        p.stripes.forEachIndexed { i, col ->
            pt.color = col.i
            c.drawRect(lx, bandTop + i * bandH / n, lx + lw, bandTop + (i + 1) * bandH / n + 0.5f, pt)
        }

        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG)
        tp.color = p.ink.i
        tp.typeface = sans
        tp.textSize = h * .16f
        c.drawText(side, lx + lw * .025f, ly + lh * .01f - tp.ascent(), tp)

        val textX = lx + lw * .13f
        val textW = lw * .83f
        val line1 = ly + lh * .22f
        val line2 = ly + lh * .36f
        pt.color = p.ink.a(.35f); pt.strokeWidth = 1.5f
        c.drawLine(textX, line1, textX + textW, line1, pt)
        c.drawLine(textX, line2, textX + textW, line2, pt)

        if (handwritten) scrawl(c, p, label, textX, line1, textW, h * .15f, h * .085f)
        else {
            tp.typeface = mono
            c.drawText(fit(tp, label, textW, h * .085f, h * .052f), textX, line1 - tp.descent() - 1f, tp)
        }
        tp.typeface = monoPlain; tp.textSize = h * .06f; tp.color = p.ink.a(.8f)
        c.drawText(TextUtils.ellipsize(sub, tp, textW, TextUtils.TruncateAt.END).toString(), textX, line2 - tp.descent() - 1f, tp)

        // Window + reels
        val wx = w * .25f; val wy = bandTop + bandH * .1f; val ww = w * .5f; val wh = bandH * .8f
        val win = RectF(wx, wy, wx + ww, wy + wh)
        val winPath = Path().apply { addRoundRect(win, wh * .25f, wh * .25f, Path.Direction.CW) }
        pt.color = p.window.i
        c.drawPath(winPath, pt)
        val cy = wy + wh / 2
        val c1x = wx + ww * .2f
        val c2x = wx + ww * .8f
        val minR = wh * .32f
        val maxR = wh * .95f
        val pr = progress.coerceIn(0f, 1f)
        c.save()
        c.clipPath(winPath)
        pt.color = p.pack.i
        c.drawCircle(c1x, cy, minR + (maxR - minR) * (1 - pr), pt)
        c.drawCircle(c2x, cy, minR + (maxR - minR) * pr, pt)
        pt.style = Paint.Style.STROKE; pt.strokeWidth = 2f; pt.color = Color.White.a(.06f)
        c.drawCircle(c1x, cy, minR + (maxR - minR) * (1 - pr), pt)
        c.drawCircle(c2x, cy, minR + (maxR - minR) * pr, pt)
        pt.style = Paint.Style.FILL
        c.restore()

        val hubR = wh * .28f
        for (cx in floatArrayOf(c1x, c2x)) {
            pt.color = p.hub.i
            c.drawCircle(cx, cy, hubR, pt)
            pt.color = p.window.i
            c.drawCircle(cx, cy, hubR * .62f, pt)
            pt.color = p.hub.i
            for (k in 0 until 6) {
                c.save()
                c.rotate(angle + k * 60f, cx, cy)
                c.drawRect(cx - hubR * .08f, cy - hubR * .62f, cx + hubR * .08f, cy - hubR * .40f, pt)
                c.restore()
            }
        }
        // Glare + outline
        c.save()
        c.clipPath(winPath)
        pt.color = Color.White.a(.10f); pt.strokeWidth = wh * .25f
        c.drawLine(wx + ww * .35f, wy - 4f, wx + ww * .2f, wy + wh + 4f, pt)
        c.restore()
        pt.style = Paint.Style.STROKE; pt.strokeWidth = 3f; pt.color = Color.Black.a(.6f)
        c.drawPath(winPath, pt)
        pt.style = Paint.Style.FILL

        // Bottom trapezoid, holes, screws
        val trap = Path().apply {
            moveTo(w * .2f, h); lineTo(w * .25f, h * .78f); lineTo(w * .75f, h * .78f); lineTo(w * .8f, h); close()
        }
        pt.color = Color.Black.a(.25f)
        c.drawPath(trap, pt)
        pt.color = Color.Black.i
        c.drawCircle(w * .35f, h * .9f, h * .025f, pt)
        c.drawCircle(w * .65f, h * .9f, h * .025f, pt)
        for ((sx, sy) in listOf(.035f to .055f, .965f to .055f, .035f to .945f, .965f to .945f, .5f to .88f)) {
            pt.color = 0xFF8A8A8A.toInt()
            c.drawCircle(w * sx, h * sy, w * .012f, pt)
            pt.color = 0xFF3A3A3A.toInt(); pt.strokeWidth = 2f
            c.drawLine(w * sx - w * .008f, h * sy, w * sx + w * .008f, h * sy, pt)
        }
    }

    /**
     * Linear VU meter at (0,0) with width [w]; needle 0..1. A slim backlit window with a
     * horizontal scale (-20 … 0 … +3, red past 0) and a pointer that slides left / right.
     */
    fun vu(c: Canvas, w: Float, p: Palette, needle: Float) {
        val h = w / VU_RATIO
        val pt = Paint(Paint.ANTI_ALIAS_FLAG)
        pt.color = 0xFF0E0C0A.toInt()
        c.drawRoundRect(0f, 0f, w, h, h * .16f, h * .16f, pt)
        val inset = h * .09f
        pt.shader = LinearGradient(0f, inset, 0f, h - inset, p.vu1.i, p.vu2.i, Shader.TileMode.CLAMP)
        c.drawRoundRect(inset, inset, w - inset, h - inset, h * .1f, h * .1f, pt)
        pt.shader = null

        c.save()
        c.clipRect(inset, inset, w - inset, h - inset)
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG)
        // "VU" printed on the left of the window, the scale across the rest.
        tp.typeface = mono; tp.color = p.vuInk.i; tp.textSize = h * .34f; tp.textAlign = Paint.Align.LEFT
        val vuX = inset + h * .22f
        c.drawText("VU", vuX, h / 2 - (tp.ascent() + tp.descent()) / 2, tp)
        val x0 = vuX + tp.measureText("VU") + h * .45f
        val x1 = w - inset - h * .35f
        val red = .8f                    // 0 dB
        fun x(f: Float) = x0 + (x1 - x0) * f
        val lineY = h * .56f
        pt.style = Paint.Style.STROKE; pt.strokeCap = Paint.Cap.BUTT
        pt.color = p.vuInk.i; pt.strokeWidth = h * .035f
        c.drawLine(x0, lineY, x(red), lineY, pt)
        pt.color = p.vuRed.i; pt.strokeWidth = h * .09f
        c.drawLine(x(red), lineY + h * .03f, x1, lineY + h * .03f, pt)
        tp.typeface = monoPlain; tp.textSize = h * .2f; tp.textAlign = Paint.Align.CENTER
        val labels = mapOf(0 to "-20", 2 to "-10", 4 to "-7", 6 to "-3", 8 to "0", 10 to "+3")
        for (i in 0..10) {
            val f = i / 10f
            val major = i % 2 == 0
            val hot = i >= 8
            pt.color = if (hot) p.vuRed.i else p.vuInk.i
            pt.strokeWidth = if (major) h * .035f else h * .025f
            c.drawLine(x(f), lineY, x(f), lineY + h * (if (major) .2f else .12f), pt)
            labels[i]?.let {
                tp.color = if (hot) p.vuRed.i else p.vuInk.i
                tp.typeface = if (hot) mono else monoPlain
                c.drawText(it, x(f), lineY - h * .1f, tp)
            }
        }
        // The pointer: a thin vertical wire riding left / right, with a soft shadow on the face.
        val nx = x(needle.coerceIn(0f, 1.05f))
        // It rides over the ticks only, under the numbers, so it never hides "-20" at rest.
        val top = lineY - h * .07f; val bot = h - inset - h * .06f
        pt.strokeCap = Paint.Cap.ROUND
        pt.color = Color.Black.a(.18f); pt.strokeWidth = h * .06f
        c.drawLine(nx + h * .05f, top + h * .04f, nx + h * .05f, bot, pt)
        pt.color = p.vuInk.i; pt.strokeWidth = h * .04f
        c.drawLine(nx, top, nx, bot, pt)
        pt.style = Paint.Style.FILL
        c.restore()
    }

    /** 3-digit counter, top-left at (0,0), digit height [dh]. Returns total width. */
    fun counter(c: Canvas, value: Int, dh: Float, p: Palette): Float {
        val digits = value.coerceIn(0, 999).toString().padStart(3, '0')
        val dw = dh * 0.72f
        val gap = dh * 0.08f
        val pad = dh * 0.1f
        val totalW = pad * 2 + digits.length * dw + (digits.length - 1) * gap
        val pt = Paint(Paint.ANTI_ALIAS_FLAG)
        pt.color = 0xFF000000.toInt()
        c.drawRoundRect(0f, 0f, totalW, dh + pad * 2, 8f, 8f, pt)
        pt.style = Paint.Style.STROKE; pt.strokeWidth = 4f; pt.color = p.key2.i
        c.drawRoundRect(0f, 0f, totalW, dh + pad * 2, 8f, 8f, pt)
        pt.style = Paint.Style.FILL
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG)
        tp.typeface = mono; tp.textSize = dh * .72f; tp.color = p.counterDigit.i; tp.textAlign = Paint.Align.CENTER
        digits.forEachIndexed { i, ch ->
            val x0 = pad + i * (dw + gap)
            pt.shader = LinearGradient(
                0f, pad, 0f, pad + dh,
                intArrayOf(p.counterBg.i, lighten(p.counterBg), p.counterBg.i), null, Shader.TileMode.CLAMP
            )
            c.drawRect(x0, pad, x0 + dw, pad + dh, pt)
            pt.shader = null
            c.drawText(ch.toString(), x0 + dw / 2, pad + dh / 2 - (tp.ascent() + tp.descent()) / 2, tp)
        }
        return totalW
    }

    /** Round LED centred at (cx, cy). */
    fun led(c: Canvas, cx: Float, cy: Float, r: Float, on: Boolean, p: Palette) {
        val pt = Paint(Paint.ANTI_ALIAS_FLAG)
        if (on) {
            pt.shader = android.graphics.RadialGradient(cx, cy, r * 2.2f, p.led.a(.55f), p.led.a(0f), Shader.TileMode.CLAMP)
            c.drawCircle(cx, cy, r * 2.2f, pt)
            pt.shader = android.graphics.RadialGradient(cx - r * .3f, cy - r * .3f, r * 1.2f, Color.White.a(.9f), p.led.i, Shader.TileMode.CLAMP)
        } else {
            pt.shader = android.graphics.RadialGradient(cx - r * .3f, cy - r * .3f, r * 1.2f, p.ledOff.i, Color.Black.a(.85f), Shader.TileMode.CLAMP)
        }
        c.drawCircle(cx, cy, r, pt)
        pt.shader = null
        pt.style = Paint.Style.STROKE; pt.strokeWidth = r * .15f; pt.color = Color.Black.i
        c.drawCircle(cx, cy, r, pt)
    }

    /** "DIC2PHONE" brand plate centred on [cx] with its top at [top]. Returns the height used. */
    fun brand(c: Canvas, cx: Float, top: Float, width: Float, p: Palette, disc: Boolean = false): Float {
        val tp = TextPaint(Paint.ANTI_ALIAS_FLAG)
        tp.typeface = brandFace
        tp.textSize = width * .13f
        tp.letterSpacing = .08f
        tp.textAlign = Paint.Align.CENTER
        val base = top - tp.ascent()
        tp.shader = LinearGradient(
            0f, top, 0f, base + tp.descent(),
            intArrayOf(p.brand1.i, p.brand2.i, p.brand1.i, p.brand2.i), null, Shader.TileMode.CLAMP
        )
        c.drawText("DIC2PHONE", cx, base, tp)
        val y = base + tp.descent() + width * .02f
        val sh = width * .012f
        val sw = width * .12f / p.stripes.size
        val pt = Paint()
        p.stripes.forEachIndexed { i, col ->
            pt.color = col.i
            c.drawRect(cx - width * .45f + i * sw, y, cx - width * .45f + (i + 1) * sw, y + sh, pt)
            c.drawRect(cx + width * .45f - (i + 1) * sw, y, cx + width * .45f - i * sw, y + sh, pt)
        }
        val sp = TextPaint(Paint.ANTI_ALIAS_FLAG)
        sp.typeface = monoPlain; sp.textSize = width * .032f; sp.color = p.dim.i; sp.textAlign = Paint.Align.CENTER
        c.drawText(if (disc) "STEREO MINIDISC RECORDER  DX-2" else "STEREO CASSETTE RECORDER  DX-2", cx, y + sh / 2 - (sp.ascent() + sp.descent()) / 2, sp)
        return y + sh * 2 - top
    }

    /** Rounded widget panel with a stripe band along the bottom edge. */
    fun panel(c: Canvas, w: Float, h: Float, p: Palette) {
        val r = h * .16f
        val pt = Paint(Paint.ANTI_ALIAS_FLAG)
        pt.shader = LinearGradient(0f, 0f, 0f, h, p.bgTop.i, p.bgBottom.i, Shader.TileMode.CLAMP)
        c.drawRoundRect(0f, 0f, w, h, r, r, pt)
        pt.shader = null
        val path = Path().apply { addRoundRect(RectF(0f, 0f, w, h), r, r, Path.Direction.CW) }
        c.save(); c.clipPath(path)
        val sh = h * .035f
        p.stripes.forEachIndexed { i, col ->
            pt.color = col.i
            c.drawRect(0f, h - (p.stripes.size - i) * sh, w, h - (p.stripes.size - i - 1) * sh, pt)
        }
        c.restore()
        pt.style = Paint.Style.STROKE; pt.strokeWidth = 2f; pt.color = Color.White.a(.12f)
        c.drawRoundRect(1f, 1f, w - 1f, h - 1f, r, r, pt)
    }

    fun lighten(col: Color, amt: Float = .18f): Int = Color(
        red = col.red + (1 - col.red) * amt, green = col.green + (1 - col.green) * amt,
        blue = col.blue + (1 - col.blue) * amt, alpha = col.alpha
    ).toArgb()
}
