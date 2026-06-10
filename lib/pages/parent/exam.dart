import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/formula_renderer.dart'; // 🔥 新公式渲染器
import 'package:zdxtapp/utils/ui_helpers.dart'; // 🔥 全局UI辅助工具

class ExamPage extends StatefulWidget {
  const ExamPage({super.key});

  @override
  State<ExamPage> createState() => _ExamPageState();
}

class _ExamPageState extends State<ExamPage> {
  bool loading = true;
  List<Map<String, dynamic>> userList = [];
  bool hasBoundStudents = false;
  final String baseUrl = Config.baseUrl;

  @override
  void initState() {
    super.initState();
    checkAndLoad();
  }

  Future<void> checkAndLoad() async {
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
      if (hasBoundStudents) {
        getPaperList();
      } else {
        setState(() => loading = false);
      }
    }
  }

  Future<void> getPaperList() async {
    final prefs = await SharedPreferences.getInstance();
    final parentAccount = jsonDecode(prefs.getString("userInfo")!)["account"] ?? "";

    final res = await http.post(
      Uri.parse("$baseUrl/api/exam"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "action": "getParentExamStatistics",
        "parentAccount": parentAccount
      }),
    );

    final data = jsonDecode(res.body);
    if (data["success"] == true) {
      setState(() {
        userList = List<Map<String, dynamic>>.from(data["data"]["userList"] ?? []).map((user) {
          final remark = (user["examList"] != null && user["examList"].isNotEmpty)
              ? user["examList"][0]["remark"] ?? "无"
              : "无";

          return {
            ...user,
            "remark": remark,
            "expand": false,
            "examList": List<Map<String, dynamic>>.from(user["examList"] ?? []).map((e) {
              return {
                ...e,
                "expand": false,
                "singleList": e["singleList"] ?? [],
                "multiList": e["multiList"] ?? [],
                "fillList": e["fillList"] ?? [],
                "shortList": e["shortList"] ?? [],
              };
            }).toList(),
          };
        }).toList();
        loading = false;
      });
    }
  }

  void toggleUser(int i) {
    // 🔥 修复：创建新的列表副本，确保 Flutter 检测到变化
    setState(() {
      final newList = List<Map<String, dynamic>>.from(userList.map((user) => Map<String, dynamic>.from(user)));
      
      // 先收起所有用户
      for (int j = 0; j < newList.length; j++) {
        if (j != i) {
          newList[j]["expand"] = false;
        }
      }
      
      // 切换当前用户的展开状态
      newList[i]["expand"] = !newList[i]["expand"];
      
      userList = newList;
    });
  }

  void toggleExam(int u, int e) {
    // 🔥 修复：创建新的列表和嵌套列表副本，确保 Flutter 检测到变化
    setState(() {
      final newList = List<Map<String, dynamic>>.from(userList.map((user) {
        final newUser = Map<String, dynamic>.from(user);
        if (user["examList"] is List) {
          newUser["examList"] = List<Map<String, dynamic>>.from(
            (user["examList"] as List).map((exam) => Map<String, dynamic>.from(exam))
          );
        }
        return newUser;
      }));
      
      final exams = newList[u]["examList"] as List<Map<String, dynamic>>;
      
      // 先收起该用户下的所有试卷
      for (int j = 0; j < exams.length; j++) {
        if (j != e) {
          exams[j]["expand"] = false;
        }
      }
      
      // 切换当前试卷的展开状态
      exams[e]["expand"] = !exams[e]["expand"];
      
      userList = newList;
    });
  }

  String fmtTime(String? t) {
    if (t == null || t.isEmpty) return "未知时间";
    try {
      final d = DateTime.parse(t);
      return "${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')} ${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}";
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : !hasBoundStudents
              ? const Center(child: Text("暂无绑定学生，请前往我的-设置页面绑定", style: TextStyle(color: Color.fromARGB(179, 0, 0, 0))))
              : userList.isEmpty
                  ? const Center(child: Text("暂无答题记录", style: TextStyle(color: Color.fromARGB(179, 0, 68, 255))))
                  : ListView(
                      padding: const EdgeInsets.only(left: 16, right: 16, top: 40, bottom: 20),
                      children: [
                        for (int i = 0; i < userList.length; i++) buildUserCard(i),
                      ],
                    ),
    );
  }

  Widget buildUserCard(int i) {
    final user = userList[i];
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
            onTap: () => toggleUser(i),
            title: Text("账号：${user["account"]}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
            subtitle: Text("备注：${user["remark"]}", style: const TextStyle(color: Colors.black54)),
            trailing: Icon(user["expand"] ? Icons.expand_more : Icons.chevron_right, color: Colors.black54),
          ),
          if (user["expand"])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  if (user["examList"].isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text("该学生暂无答题记录", style: TextStyle(color: Colors.black54)),
                    ),
                  for (int j = 0; j < user["examList"].length; j++)
                    buildExamItem(i, j),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget buildExamItem(int u, int e) {
    final exam = userList[u]["examList"][e];
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
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
            onTap: () => toggleExam(u, e),
            title: Text(exam["examName"] ?? "试卷", style: const TextStyle(color: Colors.black87)),
            subtitle: Text("提交：${fmtTime(exam["submitTime"])} | 得分：${exam["totalScore"] ?? 0}", style: const TextStyle(color: Colors.black54)),
            trailing: Icon(exam["expand"] ? Icons.expand_more : Icons.chevron_right, color: Colors.black54),
          ),
        ),
        if (exam["expand"])
          Container(
            height: 400, // 🔥 修复：设置固定高度容器
            padding: const EdgeInsets.all(12),
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
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(), // 🔥 确保可以滚动
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 🔥 直接展示题目，不再重复显示试卷名称、提交时间、得分

                  // 单选题
                  if (exam["singleList"].isNotEmpty)
                    buildQuestionSection("📝 单选题", exam["singleList"], true),

                  // 多选题
                  if (exam["multiList"].isNotEmpty)
                    buildQuestionSection("📌 多选题", exam["multiList"], false),

                  // 填空题
                  if (exam["fillList"].isNotEmpty)
                    buildQuestionSection("✍️ 填空题", exam["fillList"], null),

                  // 简答题
                  if (exam["shortList"].isNotEmpty)
                    buildQuestionSection("📖 简答题", exam["shortList"], null),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget buildQuestionSection(String title, List list, bool? isSingle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          child: Text(title, style: const TextStyle(color: Colors.black87, fontSize: 15, fontWeight: FontWeight.w500)),
        ),
        const SizedBox(height: 8),
        for (int i = 0; i < list.length; i++)
          buildQuestion(list[i], i + 1, isSingle),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget buildQuestion(Map q, int num, bool? isSingle) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 8),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("第$num 题", style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              Text("得分：${q["userScore"] ?? 0}/${q["score"] ?? 0}", style: TextStyle(color: UIHelpers.warningColor)),
            ],
          ),
          const SizedBox(height: 6),
          // ✅ 题目内容支持数学公式（直接使用原始文本）
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                ),
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
          // ✅ 解析内容支持数学公式（直接使用原始文本）
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                ),
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
    if (isUser) bg = UIHelpers.warningColor.withValues(alpha: 0.2);
    if (isStd) bg = UIHelpers.successColor.withValues(alpha: 0.2);
    if (isUser && isStd) bg = const Color(0xFF20C997).withValues(alpha: 0.2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: Colors.white30),
        borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$letter. ", style: const TextStyle(color: Colors.black87)),
          // 🔥 核心修复：使用 Flexible + LayoutBuilder + ConstrainedBox 确保正确换行
          Flexible(
            fit: FlexFit.loose,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth,
                  ),
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