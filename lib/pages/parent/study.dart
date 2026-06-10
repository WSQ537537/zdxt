import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  final List<String> weekList = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  List userProgressList = [];
  bool progressLoading = true;
  int expandedUser = -1;
  Map<int, int> expandedWeek = {};
  bool hasBoundStudents = false;
  final String baseUrl = Config.baseUrl;

  // 添加方法：获取本周的起始索引（0表示周一）
  int getCurrentWeekDayIndex() {
    final now = DateTime.now();
    // Dart中weekday: 1=Monday, 7=Sunday
    return now.weekday - 1;
  }

  @override
  void initState() {
    super.initState();
    checkAndLoad();
  }

  Future<void> checkAndLoad() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfo = prefs.getString("userInfo");
    if (userInfo == null) {
      setState(() => progressLoading = false);
      return;
    }
    final parentAccount = jsonDecode(userInfo)["account"] ?? "";

    try {
      final bindRes = await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "getParentBoundStudents",
          "parentAccount": parentAccount
        }),
      );
      final bindData = jsonDecode(bindRes.body);
      if (bindData["success"] == true) {
        setState(() {
          hasBoundStudents = (bindData["data"] as List).isNotEmpty;
        });
        if (hasBoundStudents) {
          await searchProgress();
        }
      }
    } catch (e) {
      setState(() => progressLoading = false);
    }
  }

  Future<void> searchProgress() async {
    setState(() => progressLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoStr = prefs.getString("userInfo");
      if (userInfoStr == null) {
        setState(() => progressLoading = false);
        return;
      }
      
      final userInfo = jsonDecode(userInfoStr);
      final parentAccount = userInfo["account"] ?? "";

      final res = await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'searchProgress',
          'parentAccount': parentAccount,
        }),
      );
      
      final data = jsonDecode(res.body);
      
      if (data['success'] == true) {
        final rawData = data['data'];
        
        if (rawData is List) {
          setState(() => userProgressList = rawData);
        } else {
          setState(() => userProgressList = []);
        }
      } else {
        debugPrint('❌ Parent端查询失败: ${data['msg'] ?? data['message']}');
        setState(() => userProgressList = []);
      }
    } catch (e) {
      debugPrint('❌ Parent端查询异常: $e');
      setState(() => userProgressList = []);
    } finally {
      setState(() => progressLoading = false);
    }
  }

  void toggleUserWeek(int idx) {
    setState(() {
      if (expandedUser == idx) {
        expandedUser = -1;
      } else {
        expandedUser = idx;
        expandedWeek.clear();
      }
    });
  }

  void toggleWeekDetail(int userIdx, int weekIdx) {
    setState(() {
      if (expandedWeek[userIdx] == weekIdx) {
        expandedWeek[userIdx] = -1;
      } else {
        expandedWeek[userIdx] = weekIdx;
      }
    });
  }

  String getProgressWidth(Map day, String sub) {
    final learned = int.parse(day[sub].toString());
    final target = int.parse(day["${sub}Target"].toString());
    if (target <= 0) return "0%";
    final p = (learned / target * 100).clamp(0, 100);
    return "${p.round()}%";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (progressLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    if (!hasBoundStudents) {
      return const Center(
        child: Text("暂无绑定学生，请前往我的-设置页面绑定", style: TextStyle(color: Colors.black54, fontSize: 14)),
      );
    }
    if (userProgressList.isEmpty) {
      return const Center(
        child: Text("暂无学习数据", style: TextStyle(color: Colors.black54, fontSize: 14)),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 40, bottom: 20),
      children: [
        for (int i = 0; i < userProgressList.length; i++)
          _buildUserItem(i),
      ],
    );
  }

  Widget _buildUserItem(int userIdx) {
    final user = userProgressList[userIdx];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
        children: [
          ListTile(
            onTap: () => toggleUserWeek(userIdx),
            title: Text("账号：${user["name"] ?? "未命名"}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
            subtitle: Text("备注：${user["phone"] ?? "无"}", style: const TextStyle(color: Colors.black54)),
            trailing: Icon(expandedUser == userIdx ? Icons.expand_more : Icons.chevron_right, color: Colors.black54),
          ),
          if (expandedUser == userIdx)
            _buildWeekList(userIdx, user),
        ],
      ),
    );
  }

  Widget _buildWeekList(int userIdx, Map user) {
    final weekData = user["weekData"];
    if (weekData == null || weekData is! List || weekData.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        child: Text("暂无本周学习数据", style: TextStyle(color: Colors.black54)),
      );
    }

    // 只显示本周的数据：从周一开始到当前日期（包含今天）
    final currentDayIndex = getCurrentWeekDayIndex(); // 0=周一, 1=周二, ..., 6=周日
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Column(
        children: [
          for (int w = 0; w <= currentDayIndex && w < weekList.length && w < weekData.length; w++)
            _buildWeekItem(userIdx, w, weekData[w]),
          // 如果还没有到周末，可以显示剩余天数的占位符（可选）
          if (currentDayIndex < 6)
            ...List.generate(6 - currentDayIndex, (index) {
              final futureDayIndex = currentDayIndex + 1 + index;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
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
                child: ListTile(
                  title: Text(weekList[futureDayIndex], style: const TextStyle(color: Colors.black87)),
                  subtitle: const Text("尚未开始", style: TextStyle(color: Colors.black54, fontStyle: FontStyle.italic)),
                  trailing: Icon(Icons.chevron_right, color: Colors.black54),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildWeekItem(int uIdx, int wIdx, dynamic dayData) {
    // 防御性编程：确保 dayData 是 Map，否则初始化为空 Map
    final Map day = dayData is Map ? dayData : {};

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
        children: [
          ListTile(
            onTap: () => toggleWeekDetail(uIdx, wIdx),
            title: Text(weekList[wIdx], style: const TextStyle(color: Colors.black87)),
            trailing: Icon(expandedWeek[uIdx] == wIdx ? Icons.expand_more : Icons.chevron_right, color: Colors.black54),
          ),
          if (expandedWeek[uIdx] == wIdx)
            _buildSubjects(day),
        ],
      ),
    );
  }

  Widget _buildSubjects(Map day) {
    return Padding(
      padding: const EdgeInsets.all(15),
      child: Column(
        children: [
          _subject("语文", day, "yw"),
          _subject("数学", day, "sx"),
          _subject("英语", day, "en"),
          _subject("其他", day, "ot"),
        ],
      ),
    );
  }

  Widget _subject(String name, Map day, String sub) {
    // 安全获取数值，兼容后端可能返回的字符串或数字类型
    final learnedVal = day[sub];
    final targetVal = day["${sub}Target"];

    final int learned = learnedVal is num ? learnedVal.toInt() : (int.tryParse(learnedVal?.toString() ?? '0') ?? 0);
    final int target = targetVal is num ? targetVal.toInt() : (int.tryParse(targetVal?.toString() ?? '0') ?? 0);
    
    final double progressValue = target > 0 ? (learned / target).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(15),
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
          Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 4),
          Text("已学：$learned 分钟 | 要求：$target 分钟", style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progressValue,
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF4F9BFF)),
            borderRadius: BorderRadius.circular(8),
          ),
        ],
      ),
    );
  }
}