package com.contractmind.docsign

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "docsign/file_open"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialFile" -> {
                    val filePath = getFilePathFromIntent(intent)
                    result.success(filePath)
                }
                "resolveContentUri" -> {
                    val uri = call.argument<String>("uri") ?: ""
                    val resolvedPath = copyContentToLocalFile(android.net.Uri.parse(uri))
                    result.success(resolvedPath)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        
        val filePath = getFilePathFromIntent(intent)
        if (filePath != null) {
            MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, CHANNEL)
                .invokeMethod("openFile", filePath)
        }
    }

    private fun getFilePathFromIntent(intent: Intent?): String? {
        if (intent?.data == null) return null
        val uri = intent.data!!
        return copyContentToLocalFile(uri)
    }

    private fun copyContentToLocalFile(uri: android.net.Uri): String? {
        try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val fileName = "docsign_${System.currentTimeMillis()}.pdf"
            val tempFile = File(cacheDir, fileName)
            
            FileOutputStream(tempFile).use { output ->
                inputStream.copyTo(output)
            }
            inputStream.close()
            
            return tempFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            return null
        }
    }
}