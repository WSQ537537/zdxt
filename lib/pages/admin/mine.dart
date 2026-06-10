import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/upload_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/pages/admin/usermanage.dart';
import 'package:zdxtapp/pages/public/update.dart';
import 'package:zdxtapp/pages/admin/signmanage.dart';
import 'package:url_launcher/url_launcher.dart';

class MinePage extends StatefulWidget {
  const MinePage({super.key});

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  final String serverDomain = Config.baseUrl;
  final String clientVersion = "1.0.0";

  Map<String, dynamic> originalVersion = {};
  Map<String, dynamic> versionData = {'version': '', 'url': '', 'updateInfo': ''};
  bool showVersionModal = false;

  bool showBgManageModal = false;
  late String bgImageUrl;

  final picker = ImagePicker();

  late TextEditingController _versionCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _updateInfoCtrl;

  @override
  void initState() {
    super.initState();
    bgImageUrl = "$serverDomain/bg/background.png";

    _versionCtrl = TextEditingController();
    _urlCtrl = TextEditingController();
    _updateInfoCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _versionCtrl.dispose();
    _urlCtrl.dispose();
    _updateInfoCtrl.dispose();
    super.dispose();
  }

  // ====================== 背景图 ======================
  void openBgManage() {
    setState(() {
      showBgManageModal = true;
    });
  }

  Future<void> chooseAndUploadBg() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final uploadId = 'bg_image_${DateTime.now().millisecondsSinceEpoch}';
    
    try {
      // 开始上传，显示进度对话框
      UploadProgressManager.startUpload(uploadId, '背景图片');
      if (!mounted) return;
      showUploadProgress(context, uploadId);
      
      // 模拟进度更新
      double progress = 0.0;
      final progressTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
        if (progress < 0.9) {
          progress += 0.1;
          UploadProgressManager.updateProgress(uploadId, progress);
        }
      });

      await http.post(
        Uri.parse('$serverDomain/api/deleteBg'),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
      );

      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverDomain/api/setBg'),
      );
      request.files.add(await http.MultipartFile.fromPath('file', picked.path));
      
      final response = await request.send();
      
      progressTimer.cancel();
      
      if (response.statusCode == 200) {
        UploadProgressManager.uploadSuccess(uploadId);
        if (!mounted) return;
        setState(() {
          bgImageUrl = "$serverDomain/bg/background.png?t=${DateTime.now().millisecondsSinceEpoch}";
        });
      } else {
        UploadProgressManager.uploadFailed(uploadId, "上传失败");
      }
    } catch (e) {
      UploadProgressManager.uploadFailed(uploadId, e.toString());
    } finally {
      // 确保上传结束后关闭进度对话框
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> deleteBgImage() async {
    // 🔥 新增：二次确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("确定要删除背景图片吗？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await http.post(
        Uri.parse('$serverDomain/api/deleteBg'),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
      );
      setState(() {
        bgImageUrl = "$serverDomain/bg/background.png?t=${DateTime.now().millisecondsSinceEpoch}";
      });
    } catch (e) {
      // 忽略错误
    }
  }

  // ====================== 版本更新 ======================
  Future<void> openSetUpdate() async {
    try {
      final response = await http.post(
        Uri.parse('$serverDomain/api/version'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "get"}),
      );

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final resData = data['data'] ?? {};
        originalVersion = resData;
        versionData = Map.from(resData);

        _versionCtrl.text = versionData['version'] ?? '';
        _urlCtrl.text = versionData['url'] ?? '';
        _updateInfoCtrl.text = versionData['updateInfo'] ?? '';
      }
    } catch (e) {
      debugPrint('获取版本信息失败: $e');
    }

    setState(() {
      showVersionModal = true;
    });
  }

  Future<void> saveVersionConfig() async {
    if (_versionCtrl.text.isEmpty || _urlCtrl.text.isEmpty) {
      ToastUtil.show(context, "版本号和链接不能为空");
      return;
    }

    try {
      await http.post(
        Uri.parse('$serverDomain/api/version'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "set",
          "version": _versionCtrl.text,
          "url": _urlCtrl.text,
          "updateInfo": _updateInfoCtrl.text,
        }),
      );

      if (mounted) {
        ToastUtil.show(context, "保存成功");
      }
      setState(() {
        showVersionModal = false;
      });
    } catch (e) {
      if (mounted) {
        ToastUtil.show(context, "保存失败");
      }
    }
  }

  // ====================== 检查更新 ======================
  void checkUpdate() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UpdatePage()),
    );
  }

  // ====================== 退出登录 ======================
  void logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  // 🔥 新增：打开官网
  void _openWebsite() async {
    final url = Uri.parse('https://wsq537537.github.io/zdxt');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ToastUtil.show(context, "无法打开官网");
      }
    }
  }

  // ====================== 主界面 ======================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 60),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 20),
                // ✅ 新增：课程资源按钮
                _buildBtn("课程资源", Colors.white, () {
                  Navigator.pushNamed(context, '/public/browser');
                }),
                _buildBtn("用户管理", Colors.white, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const UserManagePage()),
                  );
                }),
                _buildBtn("设置版本更新", Colors.white, openSetUpdate),
                _buildBtn("检查版本更新", Colors.white, checkUpdate),
                _buildBtn("设置背景图", Colors.white, openBgManage),
                _buildBtn("签到点名管理", Colors.white, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SignManagePage()),
                  );
                }),
                _buildBtn("🌐 官网", Colors.white, _openWebsite),
                _buildBtn("退出登录", Colors.white, logout),
              ],
            ),
          ),

          if (showVersionModal) _buildVersionModal(),
          if (showBgManageModal) _buildBgModal(),
        ],
      ),
    );
  }

  Widget _buildBtn(String text, Color color, VoidCallback onTap) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          padding: const EdgeInsets.symmetric(vertical: 20),
        ),
        onPressed: onTap,
        child: Text(text, style: const TextStyle(fontSize: 16, color: Color(0xFF333333))),
      ),
    );
  }

  Widget _fullScreenModal({required Widget child}) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black54,
          dismissible: true,
          onDismiss: () => setState(() {
            showVersionModal = false;
            showBgManageModal = false;
          }),
        ),
        Center(child: child),
      ],
    );
  }

  Widget _buildVersionModal() {
    return _fullScreenModal(
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
        title: const Text("设置版本更新"),
        content: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _versionCtrl,
                autofocus: false, // 🔥 修复：禁止自动聚焦
                decoration: const InputDecoration(labelText: "版本号", hintText: "例如1.0.1"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlCtrl,
                autofocus: false, // 🔥 修复：禁止自动聚焦
                decoration: const InputDecoration(labelText: "下载链接", hintText: "http://xxx.com/download.apk"),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _updateInfoCtrl,
                autofocus: false, // 🔥 修复：禁止自动聚焦
                maxLines: null, // 🔥 修复：允许无限行
                minLines: 3, // 🔥 修复：最小3行
                keyboardType: TextInputType.multiline, // 🔥 修复：多行键盘类型
                textInputAction: TextInputAction.newline, // 🔥 修复：回车换行
                decoration: const InputDecoration(labelText: "更新信息"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => setState(() => showVersionModal = false), child: const Text("取消")),
          TextButton(onPressed: saveVersionConfig, child: const Text("保存")),
        ],
      ),
    );
  }

  Widget _buildBgModal() {
    return _fullScreenModal(
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(36)),
        title: const Text("背景图管理"),
        content: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("当前已导入背景："),
              const SizedBox(height: 12),
              // 固定高度显示区域，背景图原比例适配
              Container(
                width: double.infinity,
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    bgImageUrl,
                    fit: BoxFit.contain, // 原比例缩放，完整显示在区域内
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(child: Text("暂无已导入的背景图"));
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: deleteBgImage,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text("删除当前背景"),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: chooseAndUploadBg,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                child: const Text("上传新背景图"),
              ),
            ],
          ),
        ),
        actions: [TextButton(onPressed: () => setState(() => showBgManageModal = false), child: const Text("关闭"))],
      ),
    );
  }
}