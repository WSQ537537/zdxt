import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import '../../utils/date_utils.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  final List<String> weekList = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  List userProgressList = [];
  bool progressLoading = true;
  bool hasStartedLoading = false;
  int expandedUser = -1;
  Map<int, int> expandedWeek = {};
  bool hasBoundStudents = false;
  final String baseUrl = Config.baseUrl;

  // 🔥 任务时间范围选择
  List<dynamic> taskTimeRanges = [];
  String? selectedRangeId;
  List<dynamic> rangeWeeks = [];
  String? selectedWeekStr;

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
      setState(() => hasStartedLoading = true);
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
        final students = bindData["data"] as List;
        setState(() => hasBoundStudents = students.isNotEmpty);
        if (hasBoundStudents) {
          // 🔥 不调用 searchProgress 在这里：由 loadTimeRanges 内部负责触发
          await loadTimeRanges();
          // 🔥 searchProgress 由 loadRangeWeeks 内的 setState 回调负责触发
          // 不在这里设置 progressLoading=false，让 searchProgress 的 finally 块负责
        } else {
          // 无绑定学生时，立即关闭 loading
          setState(() => progressLoading = false);
        }
      } else {
        setState(() => progressLoading = false);
      }
    } catch (e) {
      debugPrint('❌ checkAndLoad 异常: $e');
      setState(() => progressLoading = false);
    }
  }

  /// 加载任务时间范围列表
  Future<void> loadTimeRanges() async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getTimeRanges'}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final ranges = data['data'] as List? ?? [];
        setState(() => taskTimeRanges = ranges);

        // 自动选择当前时间所在的范围；若无匹配则保留 null，避免从已过期范围加载数据
        if (selectedRangeId == null && ranges.isNotEmpty) {
          final todayStr =
              '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}';
          String? matchedId;
          for (final r in ranges) {
            if (todayStr.compareTo(r['startDate'] ?? '') >= 0 &&
                todayStr.compareTo(r['endDate'] ?? '') <= 0) {
              matchedId = r['_id'];
              break;
            }
          }
          // ✅ 必须包裹在 setState 中，否则 DropdownButton value=null 会显示空白
          setState(() => selectedRangeId = matchedId);
          // 加载选中范围的周列表（在 selectedRangeId 更新后）
          if (matchedId != null) {
            await loadRangeWeeks(matchedId);
          } else {
            // 无匹配范围时，直接搜索当前周数据
            await searchProgress();
          }
        } else if (selectedRangeId != null) {
          await loadRangeWeeks(selectedRangeId!);
        }
      }
    } catch (e) {
      debugPrint('❌ loadTimeRanges异常: $e');
    }
  }

  /// 加载选定范围的所有周
  Future<void> loadRangeWeeks(String rangeId) async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getRangeWeeks', 'rangeId': rangeId}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final weeks = data['data'] as List? ?? [];
        // 默认选中当前周：优先精确匹配当前 ISO 周字符串
        String? defaultWeekStr;
        if (weeks.isNotEmpty) {
          final currentWeekStr = getIsoWeekStr(DateTime.now());
          for (final w in weeks) {
            if (w['weekStr'] == currentWeekStr) {
              defaultWeekStr = w['weekStr'] as String?;
              break;
            }
          }
          // 如果当前周不在范围内，找最近的过去周
          if (defaultWeekStr == null) {
            final todayStr = DateTime.now().toIso8601String().split('T')[0];
            for (final w in weeks) {
              final ws = w['weekStr'] as String?;
              if (ws != null) {
                final mondayStr = isoWeekToMonday(ws);
                if (mondayStr != null && mondayStr.compareTo(todayStr) <= 0) {
                  defaultWeekStr = ws;
                }
              }
            }
          }
          defaultWeekStr ??= weeks[0]['weekStr'] as String?;
        }
        setState(() {
          rangeWeeks = weeks;
          selectedWeekStr = defaultWeekStr;
          // 🔥 每次范围切换都重新搜索（无 hasLoadedOnce 守卫）
          if (defaultWeekStr != null) {
            searchProgress();
          }
        });
      }
    } catch (e) {
      debugPrint('❌ loadRangeWeeks异常: $e');
    }
  }

  Future<void> searchProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoStr = prefs.getString("userInfo");
      if (userInfoStr == null) {
        setState(() => progressLoading = false);
        return;
      }
      setState(() => progressLoading = true);

      final userInfo = jsonDecode(userInfoStr);
      final parentAccount = userInfo["account"] ?? "";

      // 查找当前选中的时间范围
      String? startDate;
      String? endDate;
      String? rangeId;
      if (selectedRangeId != null && taskTimeRanges.isNotEmpty) {
        for (final r in taskTimeRanges) {
          if (r['_id'] == selectedRangeId) {
            startDate = r['startDate'];
            endDate = r['endDate'];
            rangeId = r['_id'];
            break;
          }
        }
      }

      final res = await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'searchProgress',
          'parentAccount': parentAccount,
          'startDate': startDate,
          'endDate': endDate,
          'rangeId': rangeId,
          'weekStr': selectedWeekStr,
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
    // 如果还没开始加载，显示加载状态
    if (!hasStartedLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
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

    return SizedBox.expand(
      child: Column(
        children: [
          // 🔥 筛选栏：时间范围 + 周选择
          _buildFilterBar(),
          const SizedBox(height: 12),
          Expanded(
            child: userProgressList.isEmpty
                ? const Center(child: Text("暂无学习数据", style: TextStyle(color: Colors.black54)))
                : RefreshIndicator(
                    onRefresh: () async => searchProgress(),
                    color: Colors.blue,
                    child: ListView(
                      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 20),
                      children: [
                        for (int i = 0; i < userProgressList.length; i++)
                          _buildUserItem(i),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    // 时间范围下拉选项
    final rangeItems = taskTimeRanges.map((r) {
      final label = '${r['name'] ?? '未命名'} (${r['startDate']} ~ ${r['endDate']})';
      return DropdownMenuItem<String>(
        value: r['_id'] as String,
        child: Text(label, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
      );
    }).toList();

    // 周下拉选项
    final weekItems = rangeWeeks.map((w) {
      final weekStr = w['weekStr'] as String?;
      final weekLabel = w['weekLabel'] as String? ?? weekStr ?? '';
      return DropdownMenuItem<String>(
        value: weekStr,
        child: Text(weekLabel, style: const TextStyle(fontSize: 13)),
      );
    }).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // 时间范围选择器
          Expanded(
            flex: 3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              child: taskTimeRanges.isEmpty
                  ? const Text('请先配置时间范围', style: TextStyle(fontSize: 13, color: Colors.grey))
                  : DropdownButton<String>(
                      value: selectedRangeId,
                      isExpanded: true,
                      underline: const SizedBox(),
                      icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                      items: rangeItems,
                      onChanged: (v) async {
                        if (v != null && v != selectedRangeId) {
                          setState(() => selectedRangeId = v);
                          // 🔥 loadRangeWeeks 内部会通过 setState 回调自动触发 searchProgress
                          // 不在这里额外调用 searchProgress，避免用旧 week 查一次再重建
                          await loadRangeWeeks(v);
                        }
                      },
                    ),
            ),
          ),
          const SizedBox(width: 8),
          // 周选择器（有范围后才显示）
          if (selectedRangeId != null && rangeWeeks.isNotEmpty)
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<String>(
                  value: selectedWeekStr,
                  isExpanded: true,
                  underline: const SizedBox(),
                  icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                  items: weekItems,
                  onChanged: (v) async {
                    if (v != null && v != selectedWeekStr) {
                      setState(() => selectedWeekStr = v);
                      await searchProgress();
                    }
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUserItem(int userIdx) {
    final user = userProgressList[userIdx];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
            subtitle: Text("备注：${user["phone"] != null && (user["phone"] as String).isNotEmpty ? user["phone"] : "无"}", style: const TextStyle(color: Colors.black54)),
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

    // 基于选中周的实际日期判断显示天数
    final currentDayIndex = getCurrentWeekDayIndex(); // 0=周一, ..., 6=周日
    int displayDayCount = 7;
    bool isFutureWeek = false;

    if (selectedWeekStr != null && rangeWeeks.isNotEmpty) {
      final weekInfo = rangeWeeks.firstWhere(
        (w) => w['weekStr'] == selectedWeekStr,
        orElse: () => <String, dynamic>{},
      );
      final mondayDate = weekInfo['mondayDate'] as String? ?? '';
      final sundayDate = weekInfo['sundayDate'] as String? ?? '';
      if (mondayDate.isNotEmpty && sundayDate.isNotEmpty) {
        final today = DateTime.now();
        final todayStr =
            '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        if (todayStr.compareTo(mondayDate) >= 0 && todayStr.compareTo(sundayDate) <= 0) {
          displayDayCount = currentDayIndex + 1;
        } else if (todayStr.compareTo(sundayDate) > 0) {
          displayDayCount = 7;
        } else {
          isFutureWeek = true;
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Column(
        children: [
          for (int w = 0; w < displayDayCount && w < weekList.length && w < weekData.length; w++)
            _buildWeekItem(userIdx, w, weekData[w]),
          if (!isFutureWeek && displayDayCount < 7)
            ...List.generate(7 - displayDayCount, (index) {
              final futureDayIndex = displayDayCount + index;
              if (futureDayIndex >= weekList.length) return const SizedBox.shrink();
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
      margin: const EdgeInsets.only(bottom: 16),
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
