package com.advancedownloader.flutter_download_manager

import android.os.Environment
import com.chaquo.python.Python
import com.chaquo.python.PyObject
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Python Bridge Plugin (v2 — fnb_bridge 统一调度)
 *
 * Dart 侧 DownloadEngine 调用的方法：
 *  - isAvailable / getStatus / callBridge / pauseTask / resumeTask / getDownloadPath
 *
 * callBridge 走 fnb_bridge.call(function, json_args) 统一协议，
 * Python 侧自动探测 native(tkd/xhs) / legacy 后端。
 */
class PythonBridgePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var isPythonReady = false
    private var bridge: PyObject? = null
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.advancedownloader/python_bridge")
        channel.setMethodCallHandler(this)
        try {
            if (!Python.isStarted()) {
                Python.start()
            }
            val py = Python.getInstance()
            bridge = py.getModule("fnb_bridge")
            isPythonReady = bridge != null
        } catch (e: Exception) {
            isPythonReady = false
            println("[PythonBridge] Failed to start Python: ${e.message}")
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isPythonReady)

            "getStatus" -> {
                if (isPythonReady) {
                    executor.execute {
                        try {
                            val r = bridge!!.callAttr("status").toString()
                            result.success(jsonToMap(JSONObject(r)))
                        } catch (e: Exception) {
                            result.success(mapOf("available" to false, "error" to e.message))
                        }
                    }
                } else {
                    result.success(mapOf("available" to false, "error" to "Python not initialized"))
                }
            }

            "callBridge" -> {
                // Dart: {'function': String, 'args': Map}
                val function = call.argument<String>("function")
                    ?: return result.error("INVALID_ARGS", "function required", null)
                @Suppress("UNCHECKED_CAST")
                val args = call.argument<Map<String, Any?>>("args") ?: emptyMap()
                if (!isPythonReady) {
                    return result.error("PYTHON_NOT_READY", "Python bridge unavailable", null)
                }
                executor.execute {
                    try {
                        val argsJson = JSONObject(mapOfNonNull(args)).toString()
                        val r = bridge!!.callAttr("call", function, argsJson).toString()
                        result.success(jsonToMap(JSONObject(r)))
                    } catch (e: Exception) {
                        result.error("PYTHON_ERROR", e.message, e.stackTraceToString())
                    }
                }
            }

            "pauseTask" -> {
                val taskId = call.argument<String>("task_id") ?: ""
                if (isPythonReady) executor.execute {
                    try {
                        bridge!!.callAttr("pause_task", taskId)
                    } catch (_: Exception) {}
                }
                result.success(true)
            }

            "resumeTask" -> {
                val taskId = call.argument<String>("task_id") ?: ""
                if (isPythonReady) executor.execute {
                    try {
                        bridge!!.callAttr("resume_task", taskId)
                    } catch (_: Exception) {}
                }
                result.success(true)
            }

            "callPython" -> {
                // 兼容旧入口: {'module','function','args': List}
                val moduleName = call.argument<String>("module")
                val funcName = call.argument<String>("function")
                val args = call.argument<List<Any>>("args") ?: emptyList()
                if (moduleName == null || funcName == null) {
                    return result.error("INVALID_ARGS", "module and function are required", null)
                }
                executor.execute {
                    try {
                        val py = Python.getInstance()
                        val module = py.getModule(moduleName)
                        val pyArgs = args.map { arg: Any? ->
                            when (arg) {
                                is String -> arg
                                is Int -> arg
                                is Long -> arg
                                is Double -> arg
                                is Boolean -> arg
                                else -> arg.toString()
                            }
                        }.toTypedArray()
                        val pyResult = module.callAttr(funcName, *pyArgs)
                        val resultStr = pyResult?.toString() ?: ""
                        if (resultStr.startsWith("{") || resultStr.startsWith("[")) {
                            try {
                                result.success(jsonToMap(JSONObject(resultStr)))
                            } catch (_: Exception) {
                                try {
                                    result.success(jsonArrayToList(JSONArray(resultStr)))
                                } catch (_: Exception) {
                                    result.success(resultStr)
                                }
                            }
                        } else {
                            result.success(resultStr)
                        }
                    } catch (e: Exception) {
                        result.error("PYTHON_ERROR", e.message, e.stackTraceToString())
                    }
                }
            }

            "getDownloadPath" -> {
                val dir = File(
                    Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                    "DyDownload"
                )
                dir.mkdirs()
                result.success(dir.absolutePath)
            }

            else -> result.notImplemented()
        }
    }

    /** 过滤 null 值（org.json 不接受 null map value） */
    private fun mapOfNonNull(map: Map<String, Any?>): Map<String, Any> {
        val out = LinkedHashMap<String, Any>()
        for ((k, v) in map) if (v != null) out[k] = v
        return out
    }

    private fun jsonToMap(json: JSONObject): Map<String, Any?> {
        val map = mutableMapOf<String, Any?>()
        for (key in json.keys()) {
            val value = json.get(key)
            map[key] = when (value) {
                is JSONObject -> jsonToMap(value)
                is JSONArray -> jsonArrayToList(value)
                is Boolean -> value
                is Int -> value
                is Long -> value
                is Double -> value
                JSONObject.NULL -> null
                else -> value.toString()
            }
        }
        return map
    }

    private fun jsonArrayToList(jsonArray: JSONArray): List<Any?> {
        val list = mutableListOf<Any?>()
        for (i in 0 until jsonArray.length()) {
            val value = jsonArray.get(i)
            list.add(
                when (value) {
                    is JSONObject -> jsonToMap(value)
                    is JSONArray -> jsonArrayToList(value)
                    is Boolean -> value
                    is Int -> value
                    is Long -> value
                    is Double -> value
                    JSONObject.NULL -> null
                    else -> value.toString()
                }
            )
        }
        return list
    }
}
