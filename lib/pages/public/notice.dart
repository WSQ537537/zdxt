import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:photo_view/photo_view.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/common_video_player.dart';

class NoticePage extends StatefulWidget {
  const NoticePage({super.key});

  @override
  State<NoticePage> createState() => _NoticePageState();
}

class _NoticePageState extends State<NoticePage> {
  final String baseUrl = Config.baseUrl;
  List systemList = [];
  List departmentList = [];
  List myFeedbackList = [];

  String studentId = '';
  String studentRemark = '';
  String feedbackContent = '';
  String activeTab = 'send';

  bool showFeedbackModal = false;
  bool showDetailModal = false;
  bool showImagePreview = false;

  Map<String, dynamic> currentDetail = {};
  String previewImageUrl = '';

  @override
  void initState() {
    super.initState();
    getUserInfo();
    getNoticeList();
    getMyFeedbackList();
  }

  String cutText(String? str) {
    if (str == null || str.isEmpty) return '空通知';
    str = str.replaceAll(RegExp(r'\[image:[^\]]+\]'), '');
    str = str.replaceAll(RegExp(r'\[video:[^\]]+\]'), '');
    str = str.replaceAll('\n', '');
    if (str.length <= 5) return str;
    return '${str.substring(0, 5)}...';
  }

  String formatTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      DateTime date = DateTime.parse(timeStr);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timeStr;
    }
  }

  String renderContent(String? text) {
    if (text == null) return '';
    String html = text.replaceAllMapped(
      RegExp(r'\[image:([^\]]+)\]'),
          (m) => '<img src="${m.group(1)}" style="width:100%;max-width:100%;height:auto;display:block;margin:8px 0;border-radius:8px;" />',
    );
    html = html.replaceAllMapped(
      RegExp(r'\[video:([^\]]+)\]'),
          (m) => '<div class="video-container" data-src="${m.group(1)}">🎬 视频占位</div>',
    );
    return html.replaceAll('\n', '<br/>');
  }

  void getUserInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfo = prefs.getString('userInfo');
    
    debugPrint('📥 [用户信息] 原始数据: $userInfo');
    
    if (userInfo != null) {
      final user = jsonDecode(userInfo);
      debugPrint('📥 [用户信息] 解析结果: account=${user['account']}, remark=${user['remark']}');
      
      setState(() {
        studentId = user['account'] ?? '';
        studentRemark = user['remark'] ?? '';
      });
      
      debugPrint('✅ [用户信息] 设置完成: studentId="$studentId", studentRemark="$studentRemark"');
    } else {
      debugPrint('❌ [用户信息] 未找到 userInfo');
    }
  }

  Future<void> getNoticeList() async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/notice'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({"action": "list"}),
      );
      if (res.statusCode == 200) {
        var data = json.decode(res.body);
        if (data['success'] == true) {
          setState(() {
            systemList = data['data']['systemList'] ?? [];
            departmentList = data['data']['departmentList'] ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint('Get notice list error: $e');
    }
  }

  void openDetail(Map<String, dynamic> item) {
    setState(() {
      currentDetail = item;
      showDetailModal = true;
    });
  }

  void openImagePreview(String url) {
    setState(() {
      previewImageUrl = url;
      showImagePreview = true;
    });
  }

  void openFeedbackModal() {
    if (studentId.isEmpty) {
      ToastUtil.show(context, '请先登录');
      return;
    }
    getMyFeedbackList();
    setState(() {
      activeTab = 'send';
      showFeedbackModal = true;
    });
  }

  Future<void> submitFeedback() async {
    if (feedbackContent.trim().isEmpty) {
      ToastUtil.show(context, '请输入反馈内容');
      return;
    }
    
    // 🔥 调试：检查 studentId 是否为空
    debugPrint('📤 [提交反馈] studentId: "$studentId", studentRemark: "$studentRemark"');
    if (studentId.isEmpty) {
      debugPrint('❌ [提交反馈] 错误：studentId 为空，无法提交');
      ToastUtil.show(context, '用户信息未加载，请重试');
      return;
    }
    
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/notice'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          "action": "send",
          "type": "feedback",
          // 🔥 修复：保留原始换行符，不进行任何转换
          "content": feedbackContent,
          "studentId": studentId,
          "studentRemark": studentRemark,
          "status": "unhandled"
        }),
      );
      
      var data = json.decode(res.body);
      debugPrint('📥 [提交反馈] 响应: success=${data['success']}, message=${data['message']}');
      
      if (data['success'] == true) {
        if (mounted) {
          ToastUtil.show(context, '提交成功');
        }
        setState(() {
          feedbackContent = '';
          activeTab = 'record';
        });
        
        // 🔥 修复：延迟一下再加载列表，确保数据已入库
        await Future.delayed(Duration(milliseconds: 500));
        await getMyFeedbackList();
      } else {
        if (mounted) {
          ToastUtil.show(context, data['message'] ?? '提交失败');
        }
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.show(context, '网络错误，请稍后重试');
      }
      debugPrint('❌ [提交反馈] 异常: $e');
    }
  }

  Future<void> getMyFeedbackList() async {
    try {
      debugPrint('📥 [我的记录] 开始加载反馈列表, studentId: $studentId');
      
      final res = await http.post(
        Uri.parse('$baseUrl/api/notice'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({"action": "getFeedback", "studentId": studentId}),
      );
      
      final data = json.decode(res.body);
      debugPrint('📥 [我的记录] 响应数据: success=${data['success']}, data数量=${(data['data'] ?? []).length}');
      
      if (data['success'] == true) {
        setState(() {
          myFeedbackList = data['data'] ?? [];
        });
        debugPrint('✅ [我的记录] 加载成功，共 ${myFeedbackList.length} 条记录');
      } else {
        debugPrint('❌ [我的记录] 加载失败: ${data['message']}');
      }
    } catch (e) {
      debugPrint('❌ [我的记录] 加载异常: $e');
    }
  }

  // 🔥 新增：显示回复内容弹窗
  void _showReplyDialog(String replyContent) {
    // 🔥 修复：如果回复内容为空，显示提示信息
    final displayContent = replyContent.isEmpty ? '暂无回复内容' : replyContent;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("管理员回复"),
        content: SingleChildScrollView(
          child: Text(
            displayContent,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("关闭"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned(
            top: 15,
            left: 0,
            right: 0,
            bottom: 50, // 👈 固定距离底部 50
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "通知中心",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color.fromARGB(255, 255, 255, 255),
                        ),
                      ),
                      // 反馈按钮（带文字）
                      GestureDetector(
                        onTap: openFeedbackModal,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                "反馈",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.feedback_outlined,
                                color: Colors.white,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  // 系统通知和学习通知布局
                  Expanded(
                    child: Column(
                      children: [
                        // 系统通知（上边界不动，占用较少空间）
                        Expanded(
                          flex: 50,
                          child: _buildNoticeModule("系统通知", systemList),
                        ),
                        // 学习通知（下边界距离底部65单位，占用更多空间）
                        Expanded(
                          flex: 51,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildNoticeModule("学习通知", departmentList),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (showDetailModal) _buildDetailModal(),
          if (showImagePreview) _buildImagePreview(),
          if (showFeedbackModal) _buildFeedbackModal(),
        ],
      ),
    );
  }

  Widget _buildNoticeModule(String title, List list) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),  // 🔥 修复：统一上下左右内边距为12px，确保系统通知和学习通知的边界高度一致
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
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.black87),
          ),
          const Divider(height: 1, color: Colors.black12),
          const SizedBox(height: 8),
          Expanded(
            child: list.isEmpty
                ? const Center(child: Text("暂无数据", style: TextStyle(color: Colors.black54, fontSize: 14)))
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 4), // ✅ 列表底部留少量间距
                    itemCount: list.length,
                    itemBuilder: (_, i) => _buildNoticeItem(list[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeItem(Map<String, dynamic> item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cutText(item['content']), style: const TextStyle(fontSize: 14, color: Colors.black87)),
                const SizedBox(height: 6),
                Text(formatTime(item['createTime']), style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => openDetail(item),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2B7DFF)),
            child: const Text("查看详情", style: TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailModal() {
    return Stack(
      children: [
        ModalBarrier(color: Colors.black54, dismissible: true),
        Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("通知详情", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      onPressed: () => setState(() => showDetailModal = false),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Divider(),
                SizedBox(
                  height: 320,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: HtmlWidget(
                      renderContent(currentDetail['content'] ?? ''),
                      customWidgetBuilder: (element) {
                        if (element.localName == 'img') {
                          final src = element.attributes['src'];
                          if (src != null) {
                            return GestureDetector(
                              onTap: () => openImagePreview(src),
                              child: Image.network(src),
                            );
                          }
                        }
                        if (element.localName == 'div' && element.attributes['class'] == 'video-container') {
                          final videoUrl = element.attributes['data-src'];
                          if (videoUrl != null) {
                            return _buildVideoPlayer(videoUrl);
                          }
                        }
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(formatTime(currentDetail['createTime'])),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Stack(
      children: [
        ModalBarrier(color: Colors.black, dismissible: true),
        Center(
          child: PhotoView(
            imageProvider: NetworkImage(previewImageUrl),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),
        ),
      ],
    );
  }

  Widget _buildFeedbackModal() {
    return Stack(
      children: [
        ModalBarrier(color: Colors.black54, dismissible: true),
        Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => activeTab = "send"),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: activeTab == "send" ? const Color(0xFF2B7DFF) : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text("发送反馈", style: TextStyle(
                            color: activeTab == "send" ? const Color(0xFF2B7DFF) : Colors.grey,
                            fontWeight: activeTab == "send" ? FontWeight.bold : FontWeight.normal,
                            fontSize: 16
                          )),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => activeTab = "record"),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: activeTab == "record" ? const Color(0xFF2B7DFF) : Colors.transparent,
                                width: 2,
                              ),
                            ),
                          ),
                          child: Text("我的记录", style: TextStyle(
                            color: activeTab == "record" ? const Color(0xFF2B7DFF) : Colors.grey,
                            fontWeight: activeTab == "record" ? FontWeight.bold : FontWeight.normal,
                            fontSize: 16
                          )),
                        ),
                      ),
                    ),
                  ],
                ),

                if (activeTab == "send")
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        TextField(
                          onChanged: (v) => feedbackContent = v,
                          autofocus: false, // 🔥 修复：禁止自动聚焦
                          maxLines: null, // 🔥 修复：允许无限行
                          minLines: 5, // 🔥 修复：最小5行
                          keyboardType: TextInputType.multiline, // 🔥 修复：多行键盘类型
                          textInputAction: TextInputAction.newline, // 🔥 修复：回车换行
                          decoration: const InputDecoration(hintText: "请输入反馈内容"),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(child: ElevatedButton(onPressed: () => setState(() => showFeedbackModal = false), child: const Text("取消"))),
                            const SizedBox(width: 20),
                            Expanded(child: ElevatedButton(onPressed: submitFeedback, child: const Text("提交"))),
                          ],
                        ),
                      ],
                    ),
                  ),

                if (activeTab == "record")
                  Column(
                    children: [
                      SizedBox(
                        height: 320,
                        child: myFeedbackList.isEmpty
                            ? const Center(child: Text("暂无记录"))
                            : ListView.builder(
                          padding: EdgeInsets.only(bottom: MediaQuery.of(context).size.height * 0.1),
                          itemCount: myFeedbackList.length,
                          itemBuilder: (_, i) {
                            var item = myFeedbackList[i];
                            // 🔥 修复：只要状态是"已处理"就显示查看回复按钮，不管 replyContent 是否为空
                            final isHandled = item['status'] == 'handled' || item['status'] == '已处理';
                            final hasReply = item['replyContent'] != null && item['replyContent'].toString().isNotEmpty;
                            
                            // 🔥 调试：打印反馈记录数据
                            if (i == 0) {
                              debugPrint('📋 第一条反馈记录:');
                              debugPrint('  - status: ${item['status']}');
                              debugPrint('  - replyContent: ${item['replyContent']}');
                              debugPrint('  - isHandled: $isHandled');
                              debugPrint('  - hasReply: $hasReply');
                            }
                            
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
                                  // 🔥 第一排：日期 + 处理状态 + 查看回复按钮
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        formatTime(item['createTime']),
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: item['status'] == "unhandled" ? Colors.orange : Colors.green,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              item['status'] == "unhandled" ? "待处理" : "已处理",
                                              style: const TextStyle(color: Colors.white, fontSize: 12),
                                            ),
                                          ),
                                          // 🔥 修复：只要是已处理状态就显示查看回复按钮
                                          if (isHandled) ...[
                                            const SizedBox(width: 8),
                                            TextButton(
                                              onPressed: () => _showReplyDialog(item['replyContent'] ?? '暂无回复内容'),
                                              child: const Text("查看回复", style: TextStyle(fontSize: 12)),
                                            ),
                                          ],
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
                                ],
                              ),
                            );
                          },

                        ),
                      ),
                      // 🔥 新增：取消按钮
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => setState(() => showFeedbackModal = false),
                            child: const Text("取消"),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVideoPlayer(String videoUrl) {
    return CommonVideoPlayer(
      videoUrl: videoUrl,
      autoPlay: false,
      onVideoClosed: () {},
    );
  }
}