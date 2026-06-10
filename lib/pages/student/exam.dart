import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/pages/public/doexam.dart';
import 'package:zdxtapp/pages/public/examdetail.dart';

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  List<dynamic> paperList = [];
  bool loading = true;
  String account = "";
  final String baseUrl = Config.baseUrl;
  
  // ✅ 新增：滚动控制相关变量
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);  // ✅ 添加滚动监听
    _loadData();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);  // ✅ 移除监听
    _scrollController.dispose();
    super.dispose();
  }

  // ✅ 滚动监听
  void _onScroll() {
    // 目前不需要根据滚动位置改变透明度
  }

  // 🔥 新增：分割考试时间字符串，获取开始或结束时间
  String splitExamTime(String? timeStr, int type) {
    if (timeStr == null || timeStr.isEmpty) return '';
    
    List<String> parts = [];
    
    // 优先尝试中文"至"
    if (timeStr.contains('至')) {
      parts = timeStr.split('至');
    }
    // 其次尝试" - "（空格+短横线+空格）
    else if (timeStr.contains(' - ')) {
      parts = timeStr.split(' - ');
    }
    // 再尝试"-"（无空格）
    else if (timeStr.contains('-') && !timeStr.contains(' - ')) {
      final match = RegExp(r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s*-\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})').firstMatch(timeStr);
      if (match != null) {
        parts = [match.group(1)!, match.group(2)!];
      }
    }
    // 最后尝试"~"
    else if (timeStr.contains('~')) {
      parts = timeStr.split('~');
    }
    
    if (parts.isEmpty) return '';
    
    if (type == 0) return parts[0].trim();
    if (type == 1 && parts.length > 1) return parts[1].trim();
    return '';
  }

  Future<void> _loadData() async {
    await _getAccount();
    await _getPaperList();
    setState(() => loading = false);
  }

  Future<void> _getAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfo = prefs.getString("userInfo");
    if (userInfo != null) {
      final map = jsonDecode(userInfo);
      account = map["account"] ?? "";
    }
  }

  Future<void> _getPaperList() async {
    debugPrint('📥 [学生端] 开始获取试卷列表...');
    
    try {
      // 🔥 终极优化：只调用一个接口获取带状态的试卷列表
      final res = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "action": "getUserExamList",
          "account": account.trim(),
          "page": "1",
          "limit": "20",
        },
      );
      
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        List<dynamic> list = data["list"] ?? [];
        debugPrint('✅ [学生端] 网络请求成功，带状态的试卷数据数量: ${list.length}');
        
        // 🔥 直接使用后端返回的isDone字段，无需任何前端匹配逻辑
        
        debugPrint('🔄 [学生端] 准备更新paperList，新数据数量: ${list.length}');
        
        setState(() {
          paperList = list;
        });
        
        debugPrint('✅ [学生端] paperList已更新，当前数量: ${paperList.length}');
      } else {
        debugPrint('❌ [学生端] 网络请求失败: ${data["msg"]}');
      }
    } catch (e) {
      debugPrint("❌ [学生端] 获取试卷列表失败: $e");
    }
  }

  Future<void> handlePaperBtn(dynamic examId, bool isDone) async {
    // 显示加载对话框
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // 等待一下确保对话框显示，或者直接执行逻辑
      await Future.delayed(const Duration(milliseconds: 50));
      
      if (!mounted) return;
      Navigator.pop(context);

      if (isDone) {
        // 跳转到试卷详情页面
        if (mounted) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ExamDetail(
                paperId: examId.toString(),
                account: account,
              ),
            ),
          );
        }
      } else {
        if (!mounted) return;
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DoExamPage(paperId: examId.toString())),
        );
        if (result == true && mounted) {
          await _loadData();
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  String getStatusText(Map paper) {
    final timeStr = paper["examTime"];
    final start = splitExamTime(timeStr, 0);
    final end = splitExamTime(timeStr, 1);
    
    if (start.isEmpty || end.isEmpty) return "未设置";
    
    final now = DateTime.now();
    final startTime = DateTime.tryParse(start);
    final endTime = DateTime.tryParse(end);
    
    if (startTime == null || endTime == null) return "未设置";
    
    if (now.isBefore(startTime)) return "未开始";
    if (now.isAfter(endTime)) return "已结束";
    return "答题已开放";
  }

  Color getStatusColor(String status) {
    if (status == "未开始") return Colors.grey;
    if (status == "答题已开放") return Colors.green;
    return Colors.red;
  }

  // 🔥 新增：获取按钮文字（与管理员端逻辑一致）
  String getButtonText(Map paper, bool isDone) {
    final status = getStatusText(paper);
    
    if (status == '未开始') {
      return '未开始';  // 未开始时显示"未开始"
    } else if (status == '答题已开放') {
      return isDone ? '试卷详情' : '开始答题';
    } else {
      // 已结束
      return isDone ? '试卷详情' : '已结束';
    }
  }

  // 🔥 新增：获取按钮颜色（与管理员端逻辑一致）
  Color? getButtonColor(Map paper, bool isDone) {
    final status = getStatusText(paper);
    
    if (status == '未开始') {
      // 未开始：灰色
      return Colors.grey.withValues(alpha: 0.5);
    } else if (status == '答题已开放') {
      // 进行中：有记录绿色，无记录蓝色
      return isDone ? Colors.green : const Color(0xFF1890FF);
    } else {
      // 已结束：有记录绿色，无记录灰色
      return isDone ? Colors.green : Colors.grey.withValues(alpha: 0.5);
    }
  }

  bool canStartExam(Map paper) {
    final status = getStatusText(paper);
    final isDone = paper['isDone'] ?? false;
    
    // 🔥 核心修复：已结束但有答题记录的试卷，允许查看详情
    if (status == "已结束" && isDone) {
      return true;  // 允许点击查看详情
    }
    
    // 只有"答题已开放"状态可以开始答题
    return status == "答题已开放";
  }

  String formatTime(int? sec) {
    if (sec == null || sec <= 0) return '0分钟';
    int m = sec ~/ 60;
    int s = sec % 60;
    return s == 0 ? '$m分钟' : '$m分$s秒';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ✅ 固定标题：左上角「试卷」，字体稍放大
          Positioned(
            top: 20,
            left: 16,
            child: const Text(
              "试卷中心",
              style: TextStyle(
                fontSize: 18,  // ✅ 字体从 16 放大到 18
                color: Colors.white,
                fontWeight: FontWeight.w600,  // ✅ 加粗
              ),
            ),
          ),
          
          // ✅ 可滚动内容区域（添加渐隐效果）
          Positioned(
            top: 56,
            left: 0,
            right: 0,
            bottom: 0,
            child: ShaderMask(
              shaderCallback: (bounds) {
                return LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [
                    0.0,    // 🔥 顶部完全透明
                    0.02,   // 🔥 极小渐变区域（只在滚动超出边界时生效）
                    0.92,   // 底部渐隐开始（距离底部60px）
                    1.0     // 底部结束（完全透明）
                  ],
                  colors: [
                    Colors.black.withValues(alpha: 0.0),  // 完全透明（隐藏）
                    Colors.black.withValues(alpha: 1.0),  // 完全不透明（显示）
                    Colors.black.withValues(alpha: 1.0),  // 完全不透明（显示）
                    Colors.black.withValues(alpha: 0.0),  // 完全透明（隐藏）
                  ],
                ).createShader(bounds);
              },
              blendMode: BlendMode.dstIn,
              child: RefreshIndicator(
                onRefresh: _loadData,
                color: Colors.white,
                child: ListView(
                  controller: _scrollController,  // ✅ 绑定滚动控制器
                  padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 75),  // 🔥 底部预留75px空间，确保最后一个卡片有足够间距
                  children: [
                      // ✅ 移除原来的标题 Text，改为固定标题
                      
                      if (loading)
                        const Center(child: CircularProgressIndicator(color: Colors.white)),

                      if (!loading && paperList.isEmpty)
                        const Center(
                          child: Text("暂无试卷", style: TextStyle(color: Colors.white70, fontSize: 14)),
                        ),

                      // ✅ 直接渲染试卷列表，移除内部多余的 ListView，解决嵌套滚动问题
                      ...paperList.map((paper) {
                        final status = getStatusText(paper);
                        // 🔥 修复：正确调用splitExamTime函数，分别获取开始和结束时间
                        final startTime = splitExamTime(paper["examTime"] ?? "", 0);
                        final endTime = splitExamTime(paper["examTime"] ?? "", 1);
                        bool canStart = canStartExam(paper);
                        bool disabled = !canStart;
                        // 🔥 使用后端返回的 isDone 字段
                        bool isDone = paper['isDone'] ?? false;
                        
                        // 🔥 新增：使用与管理员端一致的按钮文字和颜色逻辑
                        String buttonText = getButtonText(paper, isDone);
                        Color? buttonColor = getButtonColor(paper, isDone);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
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
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 🔥 第一行：试卷名称 + 状态标签
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      paper['examName'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF333333),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: getStatusColor(status),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      status,
                                      style: const TextStyle(color: Colors.white, fontSize: 10),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              
                              // 🔥 第二行：科目 + 类型（同一行，参考管理员端）
                              Row(
                                children: [
                                  Expanded(
                                    child: Text('科目：${paper['subject'] ?? ''}', 
                                      style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text('类型：${paper['status'] ?? '自由'}',
                                      style: const TextStyle(color: Colors.orange, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 4),

                              // 🔥 第三行：时间信息（左）+ 按钮（右），参考管理员端布局
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('开始：$startTime', 
                                          style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                                        const SizedBox(height: 2),
                                        Text('结束：$endTime', 
                                          style: const TextStyle(color: Color(0xFF666666), fontSize: 12)),
                                        if (paper['timingType'] != null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            paper['timingType'] == 'totalTime'
                                                ? '总计时：${formatTime(paper['totalTime'])}'
                                                : '每题计时',
                                            style: const TextStyle(color: Color(0xFF666666), fontSize: 12),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // 🔥 按钮和时间同行
                                  ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: buttonColor,
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    onPressed: disabled
                                        ? null
                                        : () async {
                                            // 🔥 传递 isDone 状态
                                            await handlePaperBtn(paper['examId'], isDone);
                                          },
                                    child: Text(
                                      buttonText,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                  ],  // ✅ 关闭 ListView 的 children
                ),  // ✅ 关闭 ListView
              ),  // ✅ 关闭 RefreshIndicator
            ),  // ✅ 关闭 ShaderMask
          ),  // ✅ 关闭 Positioned
        ],  // ✅ 关闭 Stack children
      ),  // ✅ 关闭 Stack
    );  // ✅ 关闭 Scaffold
  }
}