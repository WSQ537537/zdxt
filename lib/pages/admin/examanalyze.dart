import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:zdxtapp/utils/formula_renderer.dart'; // 🔥 新公式渲染器
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/ui_helpers.dart'; // 🔥 全局UI辅助工具

class Examanalyze extends StatefulWidget {
  const Examanalyze({super.key});

  @override
  State<Examanalyze> createState() => _ExamanalyzeState();
}

class _ExamanalyzeState extends State<Examanalyze> {
  final String baseUrl = Config.baseUrl;
  bool loading = true;
  List userList = [];

  bool showRejudgeModal = false;
  String newScore = "";
  Map<String, dynamic> currentRejudgeInfo = {};
  Map<String, dynamic>? currentQuestion;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => getStatisticsData());
  }

  // ====================== 接口获取统计数据 ======================
  Future<void> getStatisticsData() async {
    setState(() => loading = true);
    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"action": "getExamStatistics"}),
      );
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        List raw = data["data"]["userList"] ?? [];
        setState(() {
          userList = raw.map((u) {
            // ========== 修复：从 examList 取备注赋值给用户 ==========
            final userRemark = u['examList'] != null && u['examList'].isNotEmpty
                ? u['examList'][0]['remark'] ?? ''
                : '';

            return {
              ...u,
              "remark": userRemark, // 赋值备注
              "expand": false,
              "examList": (u["examList"] ?? []).map((e) {
                return {
                  ...e,
                  "expand": false,
                  "singleList": e["singleList"] ?? [],
                  "multiList": e["multiList"] ?? [],
                  "fillList": e["fillList"] ?? [],
                  "shortList": e["shortList"] ?? [],
                };
              }).toList()
            };
          }).toList();
        });
      }
    } catch (e) {
      // 错误处理
    } finally {
      setState(() => loading = false);
    }
  }

  // ====================== 展开用户 ======================
  void toggleUser(int index) {
    setState(() {
      userList[index]["expand"] = !userList[index]["expand"];
      if (userList[index]["expand"]) {
        for (var e in userList[index]["examList"]) {
          e["expand"] = false;
        }
      }
    });
  }

  // ====================== 展开试卷 ======================
  void toggleExam(int uIndex, int eIndex) {
    setState(() {
      bool isCurrentlyExpanded = userList[uIndex]["examList"][eIndex]["expand"];
      
      // 先收起所有用户的的所有试卷
      for (var user in userList) {
        if (user["examList"] != null) {
          for (var exam in user["examList"]) {
            exam["expand"] = false;
          }
        }
      }
      
      // 如果之前不是展开状态，则展开当前点击的试卷
      if (!isCurrentlyExpanded) {
        userList[uIndex]["examList"][eIndex]["expand"] = true;
      }
    });
  }

  // ====================== 答案转字母 ======================
  String getAnswerLetter(Map q, dynamic ans) {
    if (ans == null || q["options"] == null) return "未作答";
    int idx = q["options"].indexOf(ans);
    return idx >= 0 ? String.fromCharCode(65 + idx) : ans.toString();
  }

  String getMultiAnswerLetter(Map q, dynamic ans) {
    if (ans == null) return "未作答";
    List arr = [];
    if (ans is String) arr = ans.split(",");
    if (ans is List) arr = ans;
    return arr.map((a) => getAnswerLetter(q, a)).join("、");
  }

  // ====================== 时间格式化 ======================
  String fmtTime(String? t) {
    if (t == null || t.isEmpty) return "未知时间";
    try {
      DateTime d = DateTime.parse(t);
      return "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} "
          "${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return t;
    }
  }

  // ====================== 打开重判弹窗 ======================
  void openRejudge(int uIdx, int eIdx, Map q, String type, int idx) {
    setState(() {
      currentRejudgeInfo = {
        "uIdx": uIdx,
        "eIdx": eIdx,
        "qType": type,
        "qIdx": idx,
        "account": userList[uIdx]["account"],
        "examId": userList[uIdx]["examList"][eIdx]["examId"],
      };
      currentQuestion = q as Map<String, dynamic>;
      newScore = (q["userScore"] ?? 0).toString();
      showRejudgeModal = true;
    });
  }

  // ====================== 确认重判 ======================
  Future<void> confirmRejudge() async {
    if (currentQuestion == null) {
      ToastUtil.showError(context, "当前没有选中题目");
      return;
    }
    
    double score = double.tryParse(newScore) ?? -1;
    double max = double.parse(currentQuestion!["score"].toString());

    if (score < 0 || score > max) {
      ToastUtil.showError(context, "分数不合法");
      return;
    }

    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/x-www-form-urlencoded"},
        body: {
          "action": "rejudgeQuestion",
          "account": currentRejudgeInfo["account"],
          "examId": currentRejudgeInfo["examId"],
          "qType": currentRejudgeInfo["qType"],
          "qIndex": currentRejudgeInfo["qIdx"].toString(),
          "newScore": newScore,
        },
      );

      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        int u = currentRejudgeInfo["uIdx"];
        int e = currentRejudgeInfo["eIdx"];
        String t = currentRejudgeInfo["qType"];
        int i = currentRejudgeInfo["qIdx"];

        setState(() {
          userList[u]["examList"][e]["${t}List"][i]["userScore"] = score;
          calculateExamScore(u, e);
          showRejudgeModal = false;
        });

        if (mounted) {
          ToastUtil.showSuccess(context, "重判成功");
        }
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.showError(context, "重判失败");
      }
    }
  }

  // ====================== 重新计算总分 ======================
  void calculateExamScore(int uIdx, int eIdx) {
    var exam = userList[uIdx]["examList"][eIdx];

    double calc(List list) {
      double s = 0;
      for (var q in list) {
        s += double.tryParse(q["userScore"].toString()) ?? 0;
      }
      return s;
    }

    double s = calc(exam["singleList"]);
    double m = calc(exam["multiList"]);
    double f = calc(exam["fillList"]);
    double sh = calc(exam["shortList"]);

    exam["singleScore"] = s;
    exam["multiScore"] = m;
    exam["fillScore"] = f;
    exam["shortScore"] = sh;
    exam["totalScore"] = s + m + f + sh;
  }

  // ====================== 删除试卷记录 ======================
  Future<void> deleteExamRecord(int uIdx, int eIdx) async {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("删除后无法恢复"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("取消")),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              String account = userList[uIdx]["account"];
              String examId = userList[uIdx]["examList"][eIdx]["examId"];

              final res = await http.post(
                Uri.parse("$baseUrl/api/exam"),
                headers: {"Content-Type": "application/x-www-form-urlencoded"},
                body: {
                  "action": "deleteExamRecord",
                  "account": account,
                  "examId": examId,
                },
              );

              final data = jsonDecode(res.body);
              if (data["success"] == true) {
                setState(() {
                  userList[uIdx]["examList"].removeAt(eIdx);
                  if (userList[uIdx]["examList"].isEmpty) userList.removeAt(uIdx);
                });
                if (mounted) {
                  ToastUtil.showSuccess(context, "删除成功");
                }
              }
            },
            child: const Text("删除", style: TextStyle(color: UIHelpers.errorColor)),
          ),
        ],
      ),
    );
  }

  // ====================== 主界面 ======================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UIHelpers.bgColorLight,
      appBar: AppBar(
        title: const Text("试卷统计", style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true, // 🔥 核心修复：标题居中
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Stack(
        children: [
          loading
              ? const Center(child: CircularProgressIndicator())
              : userList.isEmpty
                  ? const Center(
                      child: Text("暂无答题记录", style: TextStyle(fontSize: 14, color: Colors.grey)))
                  : ListView.builder(
                      padding: EdgeInsets.only(
                          left: 12, right: 12, top: 12, bottom: MediaQuery.of(context).size.height * 0.35),
                      itemCount: userList.length,
                      itemBuilder: (c, uIndex) {
                        var user = userList[uIndex];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(UIHelpers.radiusLarge)),
                          child: Column(
                            children: [
                              // 用户头（备注已修复）
                              ListTile(
                                onTap: () => toggleUser(uIndex),
                                title: Text(
                                  "用户：${user["account"]}\n备注：${user["remark"] ?? "无"}",
                                  style: const TextStyle(fontSize: 14),
                                ),
                                trailing: Icon(user["expand"] ? Icons.expand_more : Icons.chevron_right),
                              ),

                              // 试卷列表
                              if (user["expand"])
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15),
                        child: user["examList"].isEmpty
                            ? const Text("该用户暂无答题记录")
                            : Column(
                          children: [
                            for (int eIndex = 0; eIndex < user["examList"].length; eIndex++)
                              buildExamItem(uIndex, eIndex),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          // 重判弹窗
          if (showRejudgeModal) buildRejudgeModal(),
        ],
      ),
    );
  }

  // ====================== 试卷项 ======================
  Widget buildExamItem(int uIndex, int eIndex) {
    var user = userList[uIndex];
    var exam = user["examList"][eIndex];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(UIHelpers.radiusMedium)),
      child: Column(
        children: [
          ListTile(
            onTap: () => toggleExam(uIndex, eIndex),
            title: Text(exam["examName"] ?? "未知试卷"),
            subtitle: Text("提交：${fmtTime(exam["submitTime"])}   得分：${exam["totalScore"] ?? 0} 分"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => deleteExamRecord(uIndex, eIndex),
                  child: const Text("删除", style: TextStyle(color: UIHelpers.errorColor)),
                ),
                Icon(exam["expand"] ? Icons.expand_more : Icons.chevron_right),
              ],
            ),
          ),

          // 试卷详情
          if (exam["expand"]) buildExamDetail(uIndex, eIndex, exam),
        ],
      ),
    );
  }

  // ====================== 试卷详情 ======================
  Widget buildExamDetail(int uIndex, int eIndex, Map exam) {
    num total = (exam["singleTotalScore"] ?? 0) +
        (exam["multiTotalScore"] ?? 0) +
        (exam["fillTotalScore"] ?? 0) +
        (exam["shortTotalScore"] ?? 0);

    return Container(
      padding: const EdgeInsets.all(10),
      color: const Color(0xFFF0F0F0),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width - 20, // 减去Container的padding
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 试卷头
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(UIHelpers.radiusLarge)),
                child: Column(
                  children: [
                    Text(exam["examName"] ?? "未知试卷", style: UIHelpers.titleMedium),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("提交:${fmtTime(exam["submitTime"])}"),
                        Text("得分:${exam["totalScore"] ?? 0} / $total"),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // 单选题
              if ((exam["singleList"] ?? []).isNotEmpty)
                buildQuestionSection("📝 单选题", exam["singleList"] ?? [], "single", uIndex, eIndex,
                    (exam["singleScore"] ?? 0).toDouble(), (exam["singleTotalScore"] ?? 0).toDouble()),

              const SizedBox(height: 10),

              // 多选题
              if ((exam["multiList"] ?? []).isNotEmpty)
                buildQuestionSection("☑️ 多选题", exam["multiList"] ?? [], "multi", uIndex, eIndex,
                    (exam["multiScore"] ?? 0).toDouble(), (exam["multiTotalScore"] ?? 0).toDouble()),

              const SizedBox(height: 10),

              // 填空题
              if ((exam["fillList"] ?? []).isNotEmpty)
                buildQuestionSection("✏️ 填空题", exam["fillList"] ?? [], "fill", uIndex, eIndex,
                    (exam["fillScore"] ?? 0).toDouble(), (exam["fillTotalScore"] ?? 0).toDouble()),

              const SizedBox(height: 10),

              // 简答题
              if ((exam["shortList"] ?? []).isNotEmpty)
                buildQuestionSection("📄 简答题", exam["shortList"] ?? [], "short", uIndex, eIndex,
                    (exam["shortScore"] ?? 0).toDouble(), (exam["shortTotalScore"] ?? 0).toDouble()),
            ],
          ),
        ), // 关闭 ConstrainedBox
      ),
    );
  }
  // ====================== 题型模块 ======================
  Widget buildQuestionSection(String title, List list, String type, int u, int e, double score, double total) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(UIHelpers.radiusLarge)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
            color: const Color(0xFFE8F3FF),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: UIHelpers.primaryColor, fontSize: 16)),
                Text("得分：$score / $total"),
              ],
            ),
          ),

          // 题目列表
          for (int i = 0; i < list.length; i++)
            buildQuestionItem(list[i], i, type, u, e),
        ],
      ),
    );
  }

  // ====================== 单题展示 ======================
  Widget buildQuestionItem(Map q, int index, String type, int u, int e) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0)))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：题号 + 重判 + 得分
          Row(
            children: [
              Text("第${index + 1}题"),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: () => openRejudge(u, e, q, type, index),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE8F3FF)),
                child: const Text("重判", style: TextStyle(color: UIHelpers.primaryColor, fontSize: 12)),
              ),
              const Spacer(),
              Text("得分：${q["userScore"] ?? 0} / ${q["score"] ?? 0}"),
            ],
          ),

          const SizedBox(height: 10),

          // 题目内容
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 100, // ✅ 添加宽度约束
              ),
              child: FormulaRenderer.renderMixedText(
                q["title"] ?? "无题目内容",
                style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
              ),
            ),
          ),

          // 选项
          if (q["options"] != null && q["options"].isNotEmpty)
            ...q["options"].asMap().entries.map((entry) {
              int j = entry.key;
              String opt = entry.value.toString();
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey[300]!), borderRadius: BorderRadius.circular(UIHelpers.radiusSmall)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${String.fromCharCode(65 + j)}. ", style: const TextStyle(fontSize: 14, color: Colors.black87)),
                    // 🔥 核心修复：使用 Flexible 替代 Expanded，确保正确换行
                    Flexible(
                      fit: FlexFit.loose,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width - 140, // 减去标签和边距
                          ),
                          child: FormulaRenderer.renderMixedText(
                            opt,
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                            // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),

          const SizedBox(height: 10),

          // 我的答案 / 标准答案
          Text("我的答案：${type == "multi" ? getMultiAnswerLetter(q, q["userAnswer"]) : getAnswerLetter(q, q["userAnswer"])}"),
          Text("标准答案：${type == "multi" ? getMultiAnswerLetter(q, q["standardAnswer"]) : getAnswerLetter(q, q["standardAnswer"])}"),

          const SizedBox(height: 10),

          // 解析
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width - 100, // ✅ 添加宽度约束
              ),
              child: FormulaRenderer.renderMixedText(
                "解析：${q["analysis"] ?? "暂无解析"}",
                style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.orange),
                // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
              ),
            ),
          ),
        ],
      ),
    );
  }


  // ====================== 重判弹窗 ======================
  Widget buildRejudgeModal() {
    return Stack(
      children: [
        ModalBarrier(color: Colors.black54, dismissible: true, onDismiss: () => setState(() => showRejudgeModal = false)),
        AlertDialog(
          title: const Text("修改本题得分"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(hintText: "请输入新得分"),
                onChanged: (v) => setState(() => newScore = v),
                controller: TextEditingController(text: newScore),
              ),
              const SizedBox(height: 10),
              Text("满分：${currentQuestion?["score"] ?? 0} 分"),
            ],
          ),
          actions: [
            TextButton(onPressed: () => setState(() => showRejudgeModal = false), child: const Text("取消")),
            TextButton(
              onPressed: confirmRejudge,
              style: TextButton.styleFrom(foregroundColor: UIHelpers.primaryColor),
              child: const Text("确定修改"),
            ),
          ],
        ),
      ],
    );
  }
}