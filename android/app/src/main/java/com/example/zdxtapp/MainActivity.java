package com.example.zdxtapp;

import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import androidx.core.content.FileProvider;
import java.io.File;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "com.zdxt.app/file_manager";

    @Override
    public void configureFlutterEngine(FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
            .setMethodCallHandler((call, result) -> {
                if (call.method.equals("openFileLocation")) {
                    String filePath = call.argument("filePath");
                    if (filePath != null && !filePath.isEmpty()) {
                        boolean success = openFileLocation(filePath);
                        result.success(success);
                    } else {
                        result.error("INVALID_PATH", "文件路径不能为空", null);
                    }
                } else {
                    result.notImplemented();
                }
            });
    }

    private boolean openFileLocation(String filePath) {
        try {
            File file = new File(filePath);
            File directory = file.getParentFile();
            
            if (directory == null || !directory.exists()) {
                return false;
            }

            // 🔥 Android 7.0+ 使用 FileProvider 获取 content:// URI
            Uri uri;
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                // 使用 FileProvider 生成 content:// URI
                String authority = getPackageName() + ".fileprovider";
                uri = FileProvider.getUriForFile(this, authority, directory);
            } else {
                // Android 6.0 及以下使用 file:// URI
                uri = Uri.fromFile(directory);
            }

            // 🔥 创建打开目录的 Intent
            Intent intent = new Intent(Intent.ACTION_VIEW);
            intent.setDataAndType(uri, "resource/folder");
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            
            startActivity(intent);
            return true;
        } catch (Exception e) {
            e.printStackTrace();
            return false;
        }
    }
}
