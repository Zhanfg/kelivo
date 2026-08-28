package com.psyche.moss_local_tts

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MossLocalTtsPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var channel: MethodChannel
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile private var engine: MossOnnxEngine? = null
    @Volatile private var engineModelRoot: String? = null
    @Volatile private var engineCpuThreads: Int = 0
    private var cacheDir: File? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        cacheDir = binding.applicationContext.cacheDir
        channel = MethodChannel(binding.binaryMessenger, "com.psyche.kelivo/moss_local_tts")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.execute { closeEngine() }
        executor.shutdown()
        cacheDir = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(true)
            "unload" -> executor.execute {
                closeEngine()
                mainHandler.post { result.success(null) }
            }
            "synthesize" -> synthesize(call, result)
            else -> result.notImplemented()
        }
    }

    private fun synthesize(call: MethodCall, result: MethodChannel.Result) {
        val modelRoot = call.argument<String>("modelRoot")?.trim().orEmpty()
        val rawTokenIds = call.argument<List<Number>>("textTokenIds")
        val voice = call.argument<String>("voice")?.trim().takeUnless { it.isNullOrEmpty() } ?: "Junhao"
        val cpuThreads = (call.argument<Number>("cpuThreads")?.toInt() ?: 2).coerceAtLeast(1)
        val maxFrames = (call.argument<Number>("maxFrames")?.toInt() ?: 375).coerceAtLeast(1)
        val seed = call.argument<Number>("seed")?.toLong() ?: System.nanoTime()

        if (modelRoot.isEmpty()) {
            result.error("invalid_args", "Missing modelRoot", null)
            return
        }
        if (rawTokenIds.isNullOrEmpty()) {
            result.error("invalid_args", "textTokenIds must not be empty", null)
            return
        }
        val outputRoot = cacheDir
        if (outputRoot == null) {
            result.error("not_ready", "Plugin cache directory is unavailable", null)
            return
        }
        val textTokenIds = IntArray(rawTokenIds.size) { index -> rawTokenIds[index].toInt() }

        executor.execute {
            try {
                val localEngine = engineFor(File(modelRoot), outputRoot, cpuThreads)
                val outputFile = File(
                    outputRoot,
                    "kelivo_moss_tts_${System.currentTimeMillis()}_${Thread.currentThread().id}.wav",
                )
                val synthesis = localEngine.synthesize(
                    textTokenIds = textTokenIds,
                    outputFile = outputFile,
                    voice = voice,
                    maxFrames = maxFrames,
                    seed = seed,
                )
                val payload = mapOf(
                    "outputPath" to synthesis.outputFile.absolutePath,
                    "generatedFrames" to synthesis.generatedFrames,
                    "sampleRate" to synthesis.sampleRate,
                    "durationMs" to synthesis.durationMs,
                    "elapsedMs" to synthesis.elapsedMs,
                )
                mainHandler.post { result.success(payload) }
            } catch (error: Throwable) {
                mainHandler.post {
                    result.error("synthesis_failed", error.message ?: error.javaClass.simpleName, null)
                }
            }
        }
    }

    @Synchronized
    private fun engineFor(modelRoot: File, outputDir: File, cpuThreads: Int): MossOnnxEngine {
        val canonicalRoot = modelRoot.canonicalPath
        val existing = engine
        if (existing != null && engineModelRoot == canonicalRoot && engineCpuThreads == cpuThreads) {
            return existing
        }
        closeEngine()
        return MossOnnxEngine(
            modelRoot = File(canonicalRoot),
            outputDir = outputDir,
            cpuThreads = cpuThreads,
        ).also {
            engine = it
            engineModelRoot = canonicalRoot
            engineCpuThreads = cpuThreads
        }
    }

    @Synchronized
    private fun closeEngine() {
        try {
            engine?.close()
        } catch (_: Throwable) {
        }
        engine = null
        engineModelRoot = null
        engineCpuThreads = 0
    }
}
