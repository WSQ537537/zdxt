import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/formula_renderer.dart';
import 'package:zdxtapp/utils/ui_helpers.dart';

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  bool loading = true;
  bool loadError = false;
  String loadErrorMsg = "";
  List<Map<String, dynamic>> userList = [];
  bool hasBoundStudents = false;
  final String baseUrl = Config.baseUrl;
  int _selectedUserIndex = 0;

  @override
  void initState() {
    super.initState();
    checkAndLoad();
  }

  Future<void> checkAndLoad() async {
    try {
      setState(() => loading = true);
      final prefs = await SharedPreferences.getInstance();
      final userInfo = prefs.getString("userInfo");
      if (userInfo == null) {
        setState(() => loading = false);
        return;
      }
      final parentAccount = jsonDecode(userInfo)["account"] ?? "";

      final res = await http.post(
        Uri.parse("$baseUrl/api/user"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "getParentBoundStudents",
          "parentAccount": parentAccount
        }),
      );

      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        setState(() {
          hasBoundStudents = (data["data"] as List).isNotEmpty;
        });
        if (!hasBoundStudents) {
          setState(() => loading = false);
        } else {
          await getPaperList();
        }
      } else {
        setState(() => loading = false);
      }
    } catch (e) {
      debugPrint('❌ checkAndLoad 异常: $e');
      setState(() => loading = false);
    }
  }

  Future<void> getPaperList() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userInfoStr = prefs.getString("userInfo");
      if (userInfoStr == null) {
        setState(() => loading = false);
        return;
      }
      final parentAccount = jsonDecode(userInfoStr)["account"] ?? "";

      final res = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "getParentExamStatistics",
          "parentAccount": parentAccount
        }),
      );

      final data = jsonDecode(res.body);
      setState(() {
        if (data["success"] == true) {
          final rawList = data["data"]?["userList"] ?? [];
          userList = List<Map<String, dynamic>>.from(rawList).map((user) {
            final remark = user["remark"] != null && (user["remark"] as String).isNotEmpty
                ? user["remark"]
                : "无";
            return {
              ...user,
              "remark": remark,
              "examList": List<Map<String, dynamic>>.from(user["examList"] ?? []),
            };
          }).toList();
          _selectedUserIndex = 0;
          loadError = false;
        } else {
          userList = [];
          loadError = true;
          loadErrorMsg = data["msg"] ?? "加载失败";
        }
        loading = false;
      });
    } catch (e) {
      debugPrint('❌ getPaperList 异常: $e');
      setState(() {
        loading = false;
        loadError = true;
        loadErrorMsg = e.toString();
      });
    }
  }

  String fmtTime(String? t) {
    if (t == null || t.isEmpty) return "未知时间";
    try {
      final parsed = DateTime.parse(t);
      final cst = parsed.isUtc ? parsed.add(const Duration(hours: 8)) : parsed;
      return "${cst.year}-${cst.month.toString().padLeft(2,'0')}-${cst.day.toString().padLeft(2,'0')} ${cst.hour.toString().padLeft(2,'0')}:${cst.minute.toString().padLeft(2,'0')}";
    } catch (_) {
      return t;
    }
  }

  String getAnswerLetter(Map q, ans) {
    final opts = List<String>.from(q["options"] ?? []);
    if (ans == null) return "";
    int idx = opts.indexWhere((o) => o == ans);
    if (idx >= 0) return String.fromCharCode(65 + idx);
    return ans.toString();
  }

  String getMultiAnswerLetter(Map q, ans) {
    if (ans == null) return "";
    List arr = ans is List ? ans : ans.toString().split(",");
    return arr.map((a) => getAnswerLetter(q, a)).join("、");
  }

  void _showExamDetail(int examIndex) {
    final exam = userList[_selectedUserIndex]["examList"][examIndex];
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(ctx).size.height * 0.85,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      exam["examName"] ?? "试卷详情",
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, color: Colors.black54),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F7FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        "提交时间：${fmtTime(exam["submitTime"])}    得分：${exam["totalScore"] ?? 0}",
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                    ),
                    if (exam["singleList"].isNotEmpty)
                      buildQuestionSection("单选题", exam["singleList"], true),
                    if (exam["multiList"].isNotEmpty)
                      buildQuestionSection("多选题", exam["multiList"], false),
                    if (exam["fillList"].isNotEmpty)
                      buildQuestionSection("填空题", exam["fillList"], null),
                    if (exam["shortList"].isNotEmpty)
                      buildQuestionSection("简答题", exam["shortList"], null),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : loadError
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(loadErrorMsg, style: const TextStyle(color: Colors.black54, fontSize: 14)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: getPaperList,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text("重新加载"),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1890FF)),
                      ),
                    ],
                  ),
                )
              : !hasBoundStudents
                  ? const Center(child: Text("暂无绑定学生，请前往我的-设置页面绑定", style: TextStyle(color: Color.fromARGB(179, 0, 0, 0))))
                  : userList.isEmpty
                      ? const Center(child: Text("暂无答题记录", style: TextStyle(color: Color.fromARGB(179, 0, 68, 255))))
                      : RefreshIndicator(
                          onRefresh: () async => getPaperList(),
                          color: Colors.blue,
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: _buildBigCard(context),
                          ),
                        ),
    );
  }

  Widget _buildBigCard(BuildContext context) {
    const cardTop = 40.0;
    const bottomPadding = 56.0;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: cardTop,
        bottom: bottomPadding,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            _buildStudentSelector(),
            const Divider(height: 1, color: Color(0xFFE0E0E0)),
            Expanded(child: _buildExamList()),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentSelector() {
    return Container(
      height: 56,
      color: const Color(0xFFFAFAFA),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: userList.length,
        itemBuilder: (ctx, i) {
          final user = userList[i];
          final isSelected = i == _selectedUserIndex;
          return GestureDetector(
            onTap: () => setState(() => _selectedUserIndex = i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF1890FF) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected ? const Color(0xFF1890FF) : Colors.grey.shade300,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: const Color(0xFF1890FF).withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 1))]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    user["account"] ?? "",
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    "(${user["remark"]})",
                    style: TextStyle(
                      color: isSelected ? Colors.white70 : Colors.black54,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExamList() {
    final user = userList[_selectedUserIndex];
    final examList = List<dynamic>.from(user["examList"] ?? []);

    if (examList.isEmpty) {
      return const Center(child: Text("该学生暂无答题记录", style: TextStyle(color: Colors.black54)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: examList.length,
      itemBuilder: (ctx, i) {
        final exam = examList[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            title: Text(
              exam["examName"] ?? "试卷",
              style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                "提交：${fmtTime(exam["submitTime"])}  |  得分：${exam["totalScore"] ?? 0}",
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1890FF).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                "查看",
                style: TextStyle(color: Color(0xFF1890FF), fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            onTap: () => _showExamDetail(i),
          ),
        );
      },
    );
  }

  Widget buildQuestionSection(String title, List list, bool? isSingle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F5F5),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(title, style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500)),
        ),
        for (int i = 0; i < list.length; i++)
          buildQuestion(list[i], i + 1, isSingle),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget buildQuestion(Map q, int num, bool? isSingle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("第 $num 题", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              Text("得分：${q["userScore"] ?? 0}/${q["score"] ?? 0}", style: TextStyle(color: UIHelpers.warningColor)),
            ],
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: FormulaRenderer.renderMixedText(
                  q["title"] ?? "无题目",
                  style: const TextStyle(color: Colors.black87, fontSize: 14, height: 1.5),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          if (isSingle != null && q["options"] != null)
            for (int j = 0; j < q["options"].length; j++)
              buildOption(q["options"][j], j, q, isSingle),
          const SizedBox(height: 6),
          Text("我的答案：${isSingle == true ? getAnswerLetter(q, q["userAnswer"]) : (isSingle == false ? getMultiAnswerLetter(q, q["userAnswer"]) : q["userAnswer"] ?? "未作答")}", style: const TextStyle(color: Colors.black54)),
          Text("标准答案：${isSingle == true ? getAnswerLetter(q, q["standardAnswer"]) : (isSingle == false ? getMultiAnswerLetter(q, q["standardAnswer"]) : q["standardAnswer"] ?? "无")}", style: TextStyle(color: UIHelpers.successColor)),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                child: FormulaRenderer.renderMixedText(
                  "解析：${q["analysis"] ?? "暂无解析"}",
                  style: const TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget buildOption(String opt, int j, Map q, bool isSingle) {
    bool isUser = false;
    bool isStd = false;
    final letter = String.fromCharCode(65 + j);

    if (isSingle) {
      isUser = q["userAnswer"] == opt || q["userAnswer"] == letter;
      isStd = q["standardAnswer"] == opt || q["standardAnswer"] == letter;
    } else {
      isUser = (q["userAnswer"] ?? "").toString().contains(letter);
      isStd = (q["standardAnswer"] ?? "").toString().contains(letter);
    }

    Color bg = Colors.transparent;
    if (isUser) bg = UIHelpers.warningColor.withValues(alpha: 0.15);
    if (isStd) bg = UIHelpers.successColor.withValues(alpha: 0.15);
    if (isUser && isStd) bg = const Color(0xFF20C997).withValues(alpha: 0.15);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$letter. ", style: const TextStyle(color: Colors.black87, fontSize: 13)),
          Flexible(
            fit: FlexFit.loose,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                  child: FormulaRenderer.renderMixedText(
                    opt,
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
