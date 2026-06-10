import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/upload_progress.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart' hide ImageSource;
import '../../widgets/common_video_player.dart';

class NoticePage extends StatefulWidget {
  const NoticePage({super.key});

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  final String baseUrl = Config.baseUrl;
  int currentTab = 1;
  int subTab = 1;
  String noticeType = "system";

  final TextEditingController _contentController = TextEditingController();
  List<dynamic> mediaList = [];
  int cursorPos = 0;

  List<dynamic> systemList = [];
  List<dynamic> departmentList = [];
  List<dynamic> feedbackList = [];
  bool isRequesting = false;

  bool showEditModal = false;
  final TextEditingController _editController = TextEditingController();
  List<dynamic> editMediaList = [];
  String? currentEditId;
  int editCursorPos = 0;

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (currentTab == 2) {
        subTab == 1 ? getNoticeList() : getFeedbackList();
      }
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _editController.dispose();
    super.dispose();
  }

  String cleanContent(String content) {
    // 处理图片标签
    content = content.replaceAllMapped(
      RegExp(r'\[image:(https?://[^\s\]]+)\]'),
      (match) => '<img src="${match.group(1)}" style="max-width:100%;height:auto;">',
    );
    // 处理视频标签
    content = content.replaceAllMapped(
      RegExp(r'\[video:(https?://[^\s\]]+)\]'),
      (match) => '<video src="${match.group(1)}" controls style="max-width:100%;height:auto;margin:8px 0;"></video>',
    );
    // 清理残留的标签标记
    content = content.replaceAll(RegExp(r'\[(image|video):[^\]]*\]'), '');
    content = content.replaceAll('\n', '<br>');
    return content;
  }

  List<String> extractImageUrls(String content) {
    final reg = RegExp(r'https?://[^\s<>"]+\.(jpg|jpeg|png|gif|webp)');
    return reg.allMatches(content).map((m) => m.group(0)!).toList();
  }

  String formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return "";
    try {
      DateTime d = DateTime.parse(timeStr);
      return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} "
          "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return timeStr;
    }
  }

  Widget _buildEditVideoPlayer(String videoUrl) {
    return CommonVideoPlayer(
      videoUrl: videoUrl,
      videoType: 1, // 🔥 Notice页面所有视频都是本地类型
      autoPlay: false, // 通知页面不自动播放
    );
  }

  Future<Map<String, dynamic>> uploadFile(String path, String type, {bool showProgress = true}) async {
    final uploadId = 'notice_${type}_${DateTime.now().millisecondsSinceEpoch}';
    final fileName = type == 'image' ? '图片' : '视频';
    
    try {
      // ✅ 开始上传，显示进度对话框（仅在需要时）
      UploadProgressManager.startUpload(uploadId, fileName);
      if (showProgress) {
        showUploadProgress(context, uploadId);
      }
      
      // ✅ 使用 Dio 进行真实上传，支持进度回调
      final result = await UploadProgressManager.uploadFileWithProgress(
        url: "$baseUrl/api/notice",
        filePath: path,
        fieldName: 'file',
        uploadId: uploadId,
        fields: {
          'action': 'upload',
          'type': type,
        },
        onProgress: (progress) {
          // ✅ 实时更新真实进度
          UploadProgressManager.updateProgress(uploadId, progress);
        },
      );
      
      if (result['success'] == true) {
        final data = result['data'];
        if (data['success'] == true) {
          UploadProgressManager.uploadSuccess(uploadId);
          return {
            "success": true,
            "url": data['url'] != null ? "$baseUrl${data['url']}" : null
          };
        } else {
          UploadProgressManager.uploadFailed(uploadId, data['message'] ?? "服务器返回失败");
          return {"success": false};
        }
      } else {
        UploadProgressManager.uploadFailed(uploadId, result['error'] ?? "上传失败");
        return {"success": false};
      }
    } catch (e) {
      UploadProgressManager.uploadFailed(uploadId, e.toString());
      return {"success": false};
    } finally {
      // 统一在 finally 中关闭进度对话框，避免遗漏
      if (showProgress && mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> insertMedia(String type) async {
    try {
      XFile? file;
      if (type == "image") {
        file = await _picker.pickImage(source: ImageSource.gallery);
      } else {
        file = await _picker.pickVideo(source: ImageSource.gallery);
      }
      if (file == null) return;

      setState(() => isRequesting = true);
      // 🔥 修复：主界面上传时显示进度弹窗
      final up = await uploadFile(file.path, type, showProgress: true);
      setState(() => isRequesting = false);

      if (up['success'] == true) {
        String url = up['url'];
        String tag = type == 'video' ? '[video:$url]' : '[image:$url]';
        final text = _contentController.text;
        _contentController.text = text.substring(0, cursorPos) + tag + text.substring(cursorPos);
        setState(() {
          mediaList.add({"type": type, "url": url});
        });
      }
    } catch (e) {
      setState(() => isRequesting = false);
    }
  }

  Future<void> insertEditMedia(String type) async {
    try {
      XFile? file;
      if (type == "image") {
        file = await _picker.pickImage(source: ImageSource.gallery);
      } else {
        file = await _picker.pickVideo(source: ImageSource.gallery);
      }
      if (file == null) return;

      // 🔥 修复：编辑弹窗中上传时不显示进度弹窗，避免冲突
      final up = await uploadFile(file.path, type, showProgress: false);
      if (up['success'] == true) {
        String url = up['url'];
        String tag = type == 'video' ? '[video:$url]' : '[image:$url]';
        final text = _editController.text;
        _editController.text = text.substring(0, editCursorPos) + tag + text.substring(editCursorPos);
        setState(() {
          editMediaList.add({"type": type, "url": url});
        });
      }
    } catch (e) {
      // Intentionally empty - error handling done via return value check or ignored for non-critical errors
    }
  }

  Future<void> removeMedia(int index) async {
    final m = mediaList[index];
    String tag = m['type'] == 'image' ? '[image:${m['url']}]' : '[video:${m['url']}]';
    _contentController.text = _contentController.text.replaceAll(tag, "");
    setState(() => mediaList.removeAt(index));

    // 确保在异步操作中使用context前检查mounted状态
    if (!mounted) return;
    
    await http.post(
      Uri.parse("$baseUrl/api/notice"),
      body: jsonEncode({"action": "deleteMediaFile", "url": m['url']}),
      headers: {"Content-Type": "application/json"},
    );
  }

  void removeEditMedia(int index) async {
    final m = editMediaList[index];
    String tag = m['type'] == 'image' ? '[image:${m['url']}]' : '[video:${m['url']}]';
    _editController.text = _editController.text.replaceAll(tag, "");
    setState(() => editMediaList.removeAt(index));

    // 确保在异步操作中使用context前检查mounted状态
    if (mounted) {
      await http.post(
        Uri.parse("$baseUrl/api/notice"),
        body: jsonEncode({"action": "deleteMediaFile", "url": m['url']}),
        headers: {"Content-Type": "application/json"},
      );
    }
  }

  Future<void> sendNotice() async {
    setState(() => isRequesting = true);
    try {
      await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "send",
          "type": noticeType,
          "content": _contentController.text,
          "mediaList": mediaList,
        }),
      );
      _contentController.clear();
      setState(() {
        mediaList.clear();
        isRequesting = false;
      });
      if (mounted) {
        ToastUtil.show(context, "发送成功");
      }
    } catch (e) {
      setState(() => isRequesting = false);
    }
  }

  Future<void> getNoticeList() async {
    if (isRequesting) return;
    setState(() => isRequesting = true);
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/notice"),
        body: jsonEncode({"action": "list"}),
        headers: {"Content-Type": "application/json"},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          systemList = data['data']['systemList'] ?? [];
          departmentList = data['data']['departmentList'] ?? [];
        });
      }
    } finally {
      setState(() => isRequesting = false);
    }
  }

  Future<void> getFeedbackList() async {
    setState(() => isRequesting = true);
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/notice"),
        body: jsonEncode({"action": "adminList"}),
        headers: {"Content-Type": "application/json"},
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => feedbackList = data['data'] ?? []);
      }
    } finally {
      setState(() => isRequesting = false);
    }
  }

  Future<void> deleteNotice(dynamic id) async {
    // 🔥 新增：二次确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("删除后无法恢复，确定要删除这条公告吗？"),
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

    await http.post(
      Uri.parse("$baseUrl/api/notice"),
      body: jsonEncode({"action": "delete", "id": id}),
      headers: {"Content-Type": "application/json"},
    );
    getNoticeList();
  }

  Future<void> handleFeedback(dynamic id) async {
    // 🔥 新增：显示输入回复内容的弹窗
    final replyController = TextEditingController();
    
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("处理反馈"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("请输入回复内容（支持换行）", style: TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
              controller: replyController,
              autofocus: false, // 🔥 修复：禁止自动聚焦，避免光标异常
              maxLines: 5,
              minLines: 3, // 🔥 新增：最小行数
              keyboardType: TextInputType.multiline, // 🔥 新增：多行键盘类型
              textInputAction: TextInputAction.newline, // 🔥 新增：回车换行
              decoration: const InputDecoration(
                hintText: "输入回复内容...",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              replyController.dispose(); // 🔥 修复：释放控制器
              Navigator.pop(ctx, null);
            },
            child: const Text("取消"),
          ),
          ElevatedButton(
            onPressed: () {
              final replyContent = replyController.text; // 🔥 修复：保留原始格式，不 trim
              replyController.dispose(); // 🔥 修复：释放控制器
              Navigator.pop(ctx, {
                'replyContent': replyContent,
              });
            },
            child: const Text("确认处理"),
          ),
        ],
      ),
    );

    if (result == null) return;

    final replyContent = result['replyContent'] as String? ?? '';

    await http.post(
      Uri.parse("$baseUrl/api/notice"),
      body: jsonEncode({
        "action": "handle",
        "_id": id,
        "replyContent": replyContent,
      }),
      headers: {"Content-Type": "application/json"},
    );
    getFeedbackList();
  }

  Future<void> deleteFeedback(dynamic id) async {
    // 🔥 新增：二次确认弹窗
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("删除后无法恢复，确定要删除这条反馈吗？"),
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

    await http.post(
      Uri.parse("$baseUrl/api/notice"),
      body: jsonEncode({"action": "delete", "id": id}),
      headers: {"Content-Type": "application/json"},
    );
    getFeedbackList();
  }

  void openEditModal(dynamic item) {
    setState(() {
      currentEditId = item['id'] ?? item['_id'];
      _editController.text = item['content'] ?? "";
      editMediaList = List.from(item['mediaList'] ?? []);
      showEditModal = true;
    });
  }

  void closeEditModal() {
    setState(() {
      showEditModal = false;
      _editController.clear();
      editMediaList.clear();
      currentEditId = null;
    });
  }

  Future<void> saveEditNotice() async {
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/notice"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "update",
          "id": currentEditId,
          "content": _editController.text,
          "mediaList": editMediaList,
        }),
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          closeEditModal();
          getNoticeList();
          if (mounted) {
            ToastUtil.show(context, "修改成功");
          }
        } else {
          if (mounted) {
            ToastUtil.show(context, "修改失败: ${data['message'] ?? '未知错误'}");
          }
        }
      } else {
        if (mounted) {
          ToastUtil.show(context, "网络请求失败");
        }
      }
    } catch (e) {
      debugPrint("Save edit notice error: $e");
      if (mounted) {
        ToastUtil.show(context, "发生错误，请重试");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  child: Row(
                    children: [
                      _buildTabItem("发布通知", 1),
                      _buildTabItem("记录反馈", 2),
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: currentTab - 1,
                    children: [
                      _buildPublishPage(),
                      _buildHandlePage(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (showEditModal) _buildEditModal(),
        ],
      ),
    );
  }

  Widget _buildTabItem(String text, int idx) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => currentTab = idx);
          if (idx == 2) {
            subTab == 1 ? getNoticeList() : getFeedbackList();
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: currentTab == idx
                ? const Border(bottom: BorderSide(color: Color(0xFF007AFF), width: 2))
                : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              color: currentTab == idx ? const Color(0xFF007AFF) : Colors.black87,
              fontWeight: currentTab == idx ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPublishPage() {
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardHeight = constraints.maxHeight - 70;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxCardHeight),
            child: Container(
              padding: const EdgeInsets.all(16),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _buildTypeItem("系统通知", "system"),
                      const SizedBox(width: 12),
                      _buildTypeItem("学习通知", "department"),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(child: _buildMediaBtn("📷 插入图片", "image")),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMediaBtn("🎬 插入视频", "video")),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 固定高度输入框，内容超出时内部滚动
                  SizedBox(
                    height: 200, // 固定高度
                    child: TextField(
                      controller: _contentController,
                      autofocus: false,
                      maxLines: null, // 允许无限行数
                      expands: true, // 填充整个容器高度
                      textAlignVertical: TextAlignVertical.top, // 文本从顶部开始，光标在左上角
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      scrollPadding: EdgeInsets.only(bottom: viewInsetsBottom + 20),
                      decoration: const InputDecoration(
                        hintText: "请输入通知内容，支持换行。点击插入图片/视频按钮，会在光标处添加标记",
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                      ),
                      onChanged: (v) {
                        cursorPos = _contentController.selection.baseOffset;
                        setState(() {});
                      },
                      onTap: () {
                        cursorPos = _contentController.selection.baseOffset;
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text("已输入：${_contentController.text.length} 字"),
                  ),
                  // 媒体列表区域（独立布局，不再与输入框共用Expanded）
                  if (mediaList.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      height: 150, // 固定高度
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("已添加媒体：", style: TextStyle(color: Colors.black87)),
                          const SizedBox(height: 8),
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: mediaList.length,
                              itemBuilder: (ctx, i) {
                                final item = mediaList[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.85),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.08),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    children: [
                                      item['type'] == "image"
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: Image.network(item['url'], width: 60, height: 60, fit: BoxFit.cover),
                                            )
                                          : Container(
                                              width: 60,
                                              height: 60,
                                              decoration: BoxDecoration(
                                                color: Colors.black12,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: const Icon(Icons.play_arrow),
                                            ),
                                      const SizedBox(width: 12),
                                      Text(item['type'] == "image" ? "图片" : "视频", style: const TextStyle(color: Colors.black87)),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: () => removeMedia(i),
                                        child: const Text("删除", style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isRequesting ? null : sendNotice,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF007AFF),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        isRequesting ? "发送中..." : "发送通知",
                        style: const TextStyle(color: Colors.black87, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTypeItem(String text, String type) {
    return GestureDetector(
      onTap: () => setState(() => noticeType = type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: noticeType == type ? const Color(0xFF007AFF) : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          text,
          style: TextStyle(color: noticeType == type ? Colors.white : Colors.black87),
        ),
      ),
    );
  }

  Widget _buildMediaBtn(String text, String type) {
    return ElevatedButton(
      onPressed: () => insertMedia(type),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.85),
        elevation: 2,
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF007AFF))),
    );
  }

  Widget _buildHandlePage() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          margin: const EdgeInsets.symmetric(horizontal: 12),
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
          child: Row(
            children: [
              _buildSubTabItem("通知记录", 1),
              _buildSubTabItem("反馈处理", 2),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: IndexedStack(
            index: subTab - 1,
            children: [
              _buildNoticeListPage(),
              _buildFeedbackPage(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSubTabItem(String text, int idx) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() => subTab = idx);
          idx == 1 ? getNoticeList() : getFeedbackList();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: subTab == idx
                ? const Border(bottom: BorderSide(color: Color(0xFF007AFF), width: 2))
                : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              color: subTab == idx ? const Color(0xFF007AFF) : Colors.black87,
              fontWeight: subTab == idx ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoticeListPage() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          // 系统通知
          SizedBox(
            height: 260, // 下移10单位
            child: _buildNoticeList("系统通知", systemList),
          ),

          // 中间间距
          const SizedBox(height: 4),

          // 学习通知（自动占满剩下高度，底部保持70单位间距）
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 65),
              child: _buildNoticeList("学习通知", departmentList),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeList(String title, List<dynamic> list) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF007AFF),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  "${list.length}",
                  style: const TextStyle(color: Colors.black87, fontSize: 12),
                ),
              ),
            ],
          ),
          const Divider(height: 1, color: Colors.white30),
          // 内容独立滚动，填满区
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text("暂无数据"))
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.35),
                    shrinkWrap: false,
                    itemCount: list.length,
                    itemBuilder: (ctx, i) => _buildNoticeItem(list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeItem(dynamic item) {
    String content = item['content'] ?? '';
    String html = cleanContent(content);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HtmlWidget(
                  html,
                  textStyle: const TextStyle(fontSize: 14, height: 1.5),
                  customWidgetBuilder: (element) {
                    // 处理视频标签
                    if (element.localName == 'video') {
                      final src = element.attributes['src'];
                      if (src != null) {
                        return _buildEditVideoPlayer(src);
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                Text(
                  formatTime(item['createTime']),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            children: [
              TextButton(
                onPressed: () => deleteNotice(item['id'] ?? item['_id']),
                child: const Text("删除", style: TextStyle(color: Colors.red)),
              ),
              TextButton(
                onPressed: () => openEditModal(item),
                child: const Text("更改"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🔥 问题3：全部删除反馈
  Future<void> deleteAllFeedback() async {
    if (feedbackList.isEmpty) {
      ToastUtil.show(context, "暂无反馈可删除");
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除全部"),
        content: Text("确定要删除所有 ${feedbackList.length} 条反馈吗？删除后无法恢复。",
            style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("全部删除", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => isRequesting = true);
    try {
      // 获取所有反馈ID并批量删除
      final ids = feedbackList.map((item) => item['_id']).toList();
      await http.post(
        Uri.parse("$baseUrl/api/notice"),
        body: jsonEncode({"action": "deleteAll", "ids": ids}),
        headers: {"Content-Type": "application/json"},
      );
      setState(() {
        feedbackList.clear();
        isRequesting = false;
      });
      if (mounted) {
        ToastUtil.show(context, "已删除全部反馈");
      }
    } catch (e) {
      setState(() => isRequesting = false);
      if (mounted) {
        ToastUtil.showError(context, "删除失败: $e");
      }
    }
  }

  Widget _buildFeedbackPage() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("用户反馈处理", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (feedbackList.isNotEmpty)
                  TextButton.icon(
                    onPressed: deleteAllFeedback,
                    icon: const Icon(Icons.delete_sweep, size: 16),
                    label: const Text("全部删除", style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: isRequesting
                ? const Center(child: CircularProgressIndicator())
                : feedbackList.isEmpty
                ? const Center(child: Text("暂无反馈"))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 70),
                    itemCount: feedbackList.length,
                    itemBuilder: (ctx, i) {
                  var item = feedbackList[i];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 🔥 第一排：账号备注 + 处理按钮 + 删除按钮
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "账号: ${item['studentId']}",
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                  ),
                                  Text(
                                    "备注: ${item['studentRemark'] ?? '无'}",
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: item['status'] == "handled" ? Colors.green : null,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                  onPressed: item['status'] == "handled"
                                      ? null
                                      : () => handleFeedback(item['_id']),
                                  child: Text(
                                    item['status'] == "handled" ? "已处理" : "处理",
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: () => deleteFeedback(item['_id']),
                                  child: const Text("删除", style: TextStyle(color: Colors.red, fontSize: 12)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // 🔥 第二排开始：按原格式显示内容（支持换行）
                        Text(
                          item['content'] ?? '',
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 4),
                        // 🔥 右下角显示时间日期
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            formatTime(item['createTime']),
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditModal() {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;
    return Stack(
      children: [
        ModalBarrier(color: Colors.black54, dismissible: true, onDismiss: closeEditModal),
        // 使用 Positioned 固定弹窗位置，不受键盘唤起影响
        Positioned(
          left: 8,
          right: 8,
          top: screenHeight * 0.08,
          bottom: screenHeight * 0.08,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: screenWidth - 16,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // 标题栏
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Color(0xFFEEEEEE), width: 1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "编辑通知",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        GestureDetector(
                          onTap: closeEditModal,
                          child: const Icon(Icons.close, color: Colors.grey, size: 24),
                        ),
                      ],
                    ),
                  ),
                  // 内容区域
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Column(
                        children: [
                          // 媒体按钮
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => insertEditMedia("image"),
                                  icon: const Icon(Icons.image, size: 18),
                                  label: const Text("图片"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF0F7FF),
                                    foregroundColor: const Color(0xFF007AFF),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => insertEditMedia("video"),
                                  icon: const Icon(Icons.video_library, size: 18),
                                  label: const Text("视频"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFFF0F5),
                                    foregroundColor: const Color(0xFFFF6B9D),
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 输入框 - 限制最大高度并允许内部滚动
                          Container(
                            constraints: BoxConstraints(
                              maxHeight: screenHeight * 0.22,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8F9FA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE9ECEF)),
                            ),
                            child: TextField(
                              controller: _editController,
                              autofocus: false,
                              maxLines: null,
                              minLines: 5,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              decoration: const InputDecoration(
                                hintText: "请输入通知内容...",
                                border: InputBorder.none,
                                contentPadding: EdgeInsets.all(12),
                              ),
                              onChanged: (v) {
                                editCursorPos = _editController.selection.baseOffset;
                              },
                              onTap: () {
                                editCursorPos = _editController.selection.baseOffset;
                              },
                            ),
                          ),
                          const SizedBox(height: 12),

                          // 媒体列表标题
                          Row(
                            children: [
                              const Icon(Icons.attachment, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              const Text(
                                "已添加媒体",
                                style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(width: 4),
                              if (editMediaList.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF007AFF),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    "${editMediaList.length}",
                                    style: const TextStyle(color: Colors.white, fontSize: 11),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),

                          // 媒体列表
                          Expanded(
                            child: editMediaList.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.perm_media_outlined, size: 40, color: Colors.grey[300]),
                                        const SizedBox(height: 8),
                                        Text("暂无媒体文件", style: TextStyle(color: Colors.grey[400], fontSize: 13)),
                                      ],
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    shrinkWrap: false,
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    itemCount: editMediaList.length,
                                    itemBuilder: (ctx, i) {
                                      dynamic m = editMediaList[i];
                                      return Container(
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF8F9FA),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: const Color(0xFFE9ECEF)),
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          leading: m['type'] == "image"
                                              ? ClipRRect(
                                                  borderRadius: BorderRadius.circular(6),
                                                  child: Image.network(m['url'], width: 44, height: 44, fit: BoxFit.cover),
                                                )
                                              : Container(
                                                  width: 44,
                                                  height: 44,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFFFF0F5),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Icon(Icons.play_circle_outline, color: Color(0xFFFF6B9D), size: 24),
                                                ),
                                          title: Text(
                                            m['type'] == "image" ? "图片 ${i + 1}" : "视频 ${i + 1}",
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                          trailing: IconButton(
                                            onPressed: () => removeEditMedia(i),
                                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                            splashRadius: 20,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 底部按钮栏
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Color(0xFFEEEEEE), width: 1),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: closeEditModal,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.grey[700],
                              side: BorderSide(color: Colors.grey[300]!),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text("取消", style: TextStyle(fontSize: 15)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: saveEditNotice,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF007AFF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text("保存", style: TextStyle(fontSize: 15)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}