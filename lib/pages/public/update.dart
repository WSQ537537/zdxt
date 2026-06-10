import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart'; // 添加权限处理包
import 'package:device_info_plus/device_info_plus.dart'; // 添加设备信息包
import 'package:zdxtapp/config.dart';
import 'package:package_info_plus/package_info_plus.dart';

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});

  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

class _UpdatePageState extends State<UpdatePage> {
  final String baseUrl = Config.baseUrl;
  String? clientVersion; 

  String latestVersion = "";
  String downloadUrl = "";
  String updateInfo = "";
  bool hasNewVersion = false;

  // 🔥 新增：加载状态
  bool isLoading = true;

  bool isDownloading = false;
  bool isDownloaded = false;
  double progress = 0;
  
  // 🔥 新增：下载文件路径
  String? downloadedFilePath;

  @override
  void initState() {
    super.initState();
    checkUpdateNow();
  }

  Future<void> checkUpdateNow() async {
    setState(() {
      isLoading = true;
    });

    // 读取APP真实版本
    PackageInfo pkg = await PackageInfo.fromPlatform();
    clientVersion = pkg.version;

    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/version"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "get"}),
      );
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        final d = data["data"];
        setState(() {
          latestVersion = d["version"] ?? "";
          downloadUrl = d["url"] ?? "";
          updateInfo = d["updateInfo"] ?? "";
          hasNewVersion = compareVersion(clientVersion ?? "0.0.0", latestVersion) < 0;
          isLoading = false;
        });
      } else {
        setState(() {
          hasNewVersion = false;
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        hasNewVersion = false;
        isLoading = false;
      });
    }
  }

  // 版本对比
  int compareVersion(String v1, String v2) {
    List a = v1.split(".").map(int.parse).toList();
    List b = v2.split(".").map(int.parse).toList();
    int len = a.length > b.length ? a.length : b.length;
    for (int i = 0; i < len; i++) {
      int n1 = i < a.length ? a[i] : 0;
      int n2 = i < b.length ? b[i] : 0;
      if (n1 > n2) return 1;
      if (n1 < n2) return -1;
    }
    return 0;
  }

  // 下载 / 安装
  void handleAction() async {
    if (isDownloading) return;
    
    if (isDownloaded && downloadedFilePath != null) {
      // 🔥 调用系统安装 APK
      await installApk(downloadedFilePath!);
    } else {
      // 开始下载
      await startDownload();
    }
  }

  // 🔥 真实下载 APK 文件（使用 Dio）
  Future<void> startDownload() async {
    if (downloadUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('下载地址无效')),
      );
      return;
    }

    setState(() {
      isDownloading = true;
      progress = 0;
      isDownloaded = false;
      downloadedFilePath = null;
    });

    try {
      // 获取临时目录
      final Directory tempDir = await getTemporaryDirectory();
      final String filePath = '${tempDir.path}/app_update_${DateTime.now().millisecondsSinceEpoch}.apk';

      // 创建 Dio 实例
      final Dio dio = Dio();
      
      // 下载文件，带进度回调
      await dio.download(
        downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              progress = (received / total * 100).clamp(0.0, 100.0);
            });
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: false,
          receiveTimeout: const Duration(minutes: 5), // 5分钟超时
        ),
      );

      // 下载完成
      setState(() {
        isDownloading = false;
        isDownloaded = true;
        progress = 100;
        downloadedFilePath = filePath;
      });

      // 提示用户
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('下载完成，点击"立即安装"进行安装')),
        );
      }
    } catch (e) {
      setState(() {
        isDownloading = false;
        progress = 0;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  // 🔥 调用系统安装 APK（带权限检查）
  Future<void> installApk(String filePath) async {
    try {
      // 🔥 Android 8.0+ 需要检查未知来源应用安装权限
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        if (androidInfo.version.sdkInt >= 26) { // Android 8.0+
          // 检查是否已有安装权限
          bool hasInstallPermission = await _checkInstallPermission();
          if (!hasInstallPermission) {
            // 显示权限请求对话框
            await showInstallPermissionDialog();
            return;
          }
        }
      }
      
      // 执行安装
      final result = await OpenFile.open(filePath);
      
      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('安装失败: ${result.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('安装异常: $e')),
        );
      }
    }
  }

  // 🔥 检查安装权限（Android 特定）
  Future<bool> _checkInstallPermission() async {
    if (!Platform.isAndroid) return true;
    
    try {
      // 使用 Android 特定的权限检查
      final status = await Permission.requestInstallPackages.status;
      return status == PermissionStatus.granted;
    } catch (e) {
      // 如果权限检查失败，假设没有权限
      return false;
    }
  }

  // 🔥 显示安装权限请求对话框
  Future<void> showInstallPermissionDialog() async {
    if (!mounted) return;
    
    final shouldShowManualPermissionTip = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('需要安装权限'),
          content: const Text('为了安装新版本应用，需要允许从未知来源安装应用。请在下一页中开启"允许来自此来源的应用"权限。'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop(true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              child: const Text('去开启', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    
    if (shouldShowManualPermissionTip == true) {
      // 请求安装未知应用权限
      final result = await Permission.requestInstallPackages.request();
      if (result == PermissionStatus.granted && downloadedFilePath != null) {
        // 权限已授予，重新尝试安装
        await installApk(downloadedFilePath!);
      } else if (result == PermissionStatus.denied) {
        // 权限被拒绝，提示用户手动开启
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请在设置中手动开启安装权限')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xff0f172a), Color(0xff1e293b), Color(0xff334155)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 30),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 🔥 加载中：显示加载动画
                if (isLoading)
                  const Column(
                    children: [
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: CircularProgressIndicator(
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 4,
                        ),
                      ),
                      SizedBox(height: 20),
                      Text("正在检查更新...", style: TextStyle(fontSize: 16, color: Colors.white70)),
                    ],
                  ),

                // 🔥 加载完成后显示内容
                if (!isLoading) ...[
                  // 有新版本
                  if (hasNewVersion)
                    const Column(
                      children: [
                        Text("🔄 发现新版本", style: TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.bold)),
                        SizedBox(height: 20),
                      ],
                    ),

                  // 无新版本
                  if (!hasNewVersion)
                    const Column(
                      children: [
                        Text("暂无更新，请静待更新通知", style: TextStyle(fontSize: 16, color: Colors.white70)),
                        SizedBox(height: 30),
                      ],
                    ),

                  // 版本信息
                  if (hasNewVersion)
                    Column(
                      children: [
                        Text("当前版本：$clientVersion", style: const TextStyle(color: Colors.white70)),
                        Text("最新版本：$latestVersion", style: const TextStyle(color: Colors.white70)),
                        const SizedBox(height: 15),
                      ],
                    ),

                  // 更新内容
                  if (hasNewVersion && updateInfo.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(15)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("更新内容", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          Text(updateInfo, style: const TextStyle(color: Colors.white70)),
                        ],
                      ),
                    ),

                  const SizedBox(height: 20),

                  // 下载按钮
                  if (hasNewVersion)
                    ElevatedButton(
                      onPressed: isDownloading ? null : handleAction,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDownloading ? Colors.grey : (isDownloaded ? Colors.green : Colors.blue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 40),
                      ),
                      child: Text(
                        isDownloading
                            ? "正在下载..."
                            : (isDownloaded ? "立即安装" : "立即下载更新"),
                        style: const TextStyle(fontSize: 16, color: Colors.white),
                      ),
                    ),

                  const SizedBox(height: 15),

                  // 进度条
                  if (isDownloading)
                    Column(
                      children: [
                        LinearProgressIndicator(value: progress / 100, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.blue)),
                        const SizedBox(height: 8),
                        Text("${progress.toInt()}%", style: const TextStyle(color: Colors.white70)),
                      ],
                    ),

                  const SizedBox(height: 20),

                  // 🔥 手动检查更新按钮：仅在没有新版本时显示
                  if (!hasNewVersion)
                    TextButton(
                      onPressed: checkUpdateNow,
                      child: const Text("检查更新", style: TextStyle(color: Colors.white70)),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}