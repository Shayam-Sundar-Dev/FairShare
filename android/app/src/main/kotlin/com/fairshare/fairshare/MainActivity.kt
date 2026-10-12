package com.fairshare.fairshare

import android.app.Activity
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.fairshare.fairshare/upi"
    private val UPI_PAYMENT_REQUEST_CODE = 9999
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "launchUpiPayment" -> {
                    val upiUriString = call.argument<String>("uri")
                    val packageName = call.argument<String>("package")
                    if (upiUriString == null) {
                        result.error("INVALID_URI", "UPI URI cannot be null", null)
                        return@setMethodCallHandler
                    }

                    try {
                        val uri = Uri.parse(upiUriString)
                        val intent = Intent(Intent.ACTION_VIEW, uri)
                        if (!packageName.isNullOrEmpty()) {
                            intent.setPackage(packageName)
                        }
                        pendingResult = result
                        startActivityForResult(intent, UPI_PAYMENT_REQUEST_CODE)
                    } catch (e: Exception) {
                        pendingResult = null
                        result.error("LAUNCH_FAILED", e.localizedMessage, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == UPI_PAYMENT_REQUEST_CODE) {
            val resultMap = HashMap<String, Any?>()
            resultMap["resultCode"] = resultCode

            var isSuccess = false
            var statusStr = "UNKNOWN"

            // 1. Direct "Status" extra returned by Google Pay
            val directStatus = data?.getStringExtra("Status")
                ?: data?.getStringExtra("status")
                ?: data?.getStringExtra("STATUS")

            // 2. Query string in "response" or "tezResponse" or dataString
            val responseString = data?.getStringExtra("response")
                ?: data?.getStringExtra("tezResponse")
                ?: data?.dataString
                ?: ""
            resultMap["rawResponse"] = responseString

            val params = HashMap<String, String>()
            if (responseString.isNotEmpty()) {
                val pairs = responseString.split("&")
                for (pair in pairs) {
                    val parts = pair.split("=")
                    if (parts.size >= 2) {
                        val key = parts[0].trim()
                        val value = parts[1].trim()
                        params[key.lowercase()] = value
                    }
                }
            }
            resultMap["params"] = params

            val parsedStatus = params["status"]

            if (!directStatus.isNullOrEmpty()) {
                statusStr = directStatus.uppercase()
                if (statusStr == "SUCCESS") {
                    isSuccess = true
                }
            } else if (!parsedStatus.isNullOrEmpty()) {
                statusStr = parsedStatus.uppercase()
                if (statusStr == "SUCCESS") {
                    isSuccess = true
                }
            } else if (resultCode == Activity.RESULT_OK) {
                statusStr = "SUCCESS"
                isSuccess = true
            } else if (resultCode == Activity.RESULT_CANCELED) {
                statusStr = "CANCELLED"
            }

            resultMap["status"] = statusStr
            resultMap["isSuccess"] = isSuccess

            pendingResult?.success(resultMap)
            pendingResult = null
        }
    }
}
