import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 🔥 添加 FilteringTextInputFormatter
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async'; // 🔥 添加 Timer
import 'dart:io'; // 🔥 添加 File
import 'package:image_picker/image_picker.dart'; // 🔥 添加 ImagePicker
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart'; // 🔥 添加 ToastUtil
import 'package:zdxtapp/utils/upload_progress.dart'; // 🔥 添加 UploadProgressManager
import 'package:zdxtapp/utils/formula_renderer.dart'; // 🔥 新公式渲染器
import 'package:zdxtapp/utils/ui_helpers.dart'; // 🔥 全局UI辅助工具

class ExamManage extends StatefulWidget {
  const ExamManage({super.key});

  @override
  State<ExamManage> createState() => _ExamManageState();
}

class _ExamManageState extends State<ExamManage> {
  final String baseUrl = Config.baseUrl;
  bool loading = false;
  bool isRequesting = false;
  List<dynamic> paperList = [];
  List<dynamic> examList = [];
  String expandId = '';
  String settingExamId = '';
  String loadingPaperId = ''; // 🔥 新增：当前正在加载题目详情的试卷ID

  final List<String> subjectList = ['语文', '数学', '英语', '其他'];
  final List<String> examStatusList = ['自由', '强制'];
  final List<String> timeUnits = ['秒', '分'];

  late Map<String, dynamic> editForm;

  String uploadExamId = '';
  int uploadQuestionIndex = -1;
  String uploadImgBase64 = '';
  final ImagePicker _picker = ImagePicker();

  // 统一管理控制器，避免内存泄漏
  late TextEditingController startYearController;
  late TextEditingController startMonthController;
  late TextEditingController startDayController;
  late TextEditingController startHourController;
  late TextEditingController startMinuteController;
  late TextEditingController startSecondController;

  late TextEditingController endYearController;
  late TextEditingController endMonthController;
  late TextEditingController endDayController;
  late TextEditingController endHourController;
  late TextEditingController endMinuteController;
  late TextEditingController endSecondController;
  
  // 🔥 新增：为表单字段添加持久的 Controller，避免每次重建导致光标丢失
  late TextEditingController paperNameController;
  late TextEditingController totalTimeController;

  // 🔥 新增：辅助函数，根据后端秒数确定时间单位
  int _determineTimeUnitIndex(int seconds) {
    // 如果秒数大于等于60秒且能被60整除，则使用分钟单位，否则使用秒单位
    if (seconds >= 60 && seconds % 60 == 0) {
      return 1; // 分钟
    } else {
      return 0; // 秒
    }
  }

  // 🔥 新增：根据时间单位返回显示值
  num _getTimeDisplayValue(int seconds, int unitIndex) {
    if (unitIndex == 1) { // 分钟
      return seconds / 60;
    } else { // 秒
      return seconds;
    }
  }

  @override
  void initState() {
    super.initState();

    // 初始化控制器（修复：统一管理，不再放在 Map 里）
    startYearController = TextEditingController();
    startMonthController = TextEditingController();
    startDayController = TextEditingController();
    startHourController = TextEditingController();
    startMinuteController = TextEditingController();
    startSecondController = TextEditingController();

    endYearController = TextEditingController();
    endMonthController = TextEditingController();
    endDayController = TextEditingController();
    endHourController = TextEditingController();
    endMinuteController = TextEditingController();
    endSecondController = TextEditingController();
    
    // 🔥 初始化表单字段 Controller
    paperNameController = TextEditingController();
    totalTimeController = TextEditingController();

    editForm = {
      "examId": "",
      "paperName": "",
      "originalPaperName": "",
      "subjectIndex": 0,
      "examStatusIndex": 0,
      "startTimeText": "",
      "endTimeText": "",
      "timeType": "per",
      "totalTime": 0,
      "originalTotalTime": 0,
      "totalTimeUnitIndex": 1,
      "questionTypes": [
        {
          "type": "single",
          "label": "单选题",
          "score": 0,
          "originalScore": 0,
          "time": 0,
          "originalTime": 0,
          "timeUnitIndex": 1,
          "scoreController": TextEditingController(), // 🔥 添加分数 Controller
          "timeController": TextEditingController(),  // 🔥 添加时间 Controller
        },
        {
          "type": "multi",
          "label": "多选题",
          "score": 0,
          "originalScore": 0,
          "time": 0,
          "originalTime": 0,
          "timeUnitIndex": 1,
          "scoreController": TextEditingController(),
          "timeController": TextEditingController(),
        },
        {
          "type": "fill",
          "label": "填空题",
          "score": 0,
          "originalScore": 0,
          "time": 0,
          "originalTime": 0,
          "timeUnitIndex": 1,
          "scoreController": TextEditingController(),
          "timeController": TextEditingController(),
        },
        {
          "type": "short",
          "label": "简答题",
          "score": 0,
          "originalScore": 0,
          "time": 0,
          "originalTime": 0,
          "timeUnitIndex": 1,
          "scoreController": TextEditingController(),
          "timeController": TextEditingController(),
        },
      ],
      "originalQuestions": []
    };
    fetchAllPaperData();
  }

  @override
  void dispose() {
    // 安全释放所有控制器
    startYearController.dispose();
    startMonthController.dispose();
    startDayController.dispose();
    startHourController.dispose();
    startMinuteController.dispose();
    startSecondController.dispose();

    endYearController.dispose();
    endMonthController.dispose();
    endDayController.dispose();
    endHourController.dispose();
    endMinuteController.dispose();
    endSecondController.dispose();
    
    // 🔥 释放表单字段 Controller
    paperNameController.dispose();
    totalTimeController.dispose();
    
    // 🔥 释放题型 Controller
    for (var qt in editForm["questionTypes"]) {
      (qt["scoreController"] as TextEditingController).dispose();
      (qt["timeController"] as TextEditingController).dispose();
    }

    super.dispose();
  }

  String formatTime(int sec) {
    int m = sec ~/ 60;
    int s = sec % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  List<String> splitExamTime(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return ["", ""];
    
    // 🔥 修复：支持多种分隔符（中文"至"、英文" - "、短横线"-"、波浪号"~"）
    String normalized = timeStr;
    
    // 优先尝试中文"至"
    if (normalized.contains('至')) {
      List<String> parts = normalized.split('至');
      String s = parts[0].trim();
      String e = parts.length > 1 ? parts[1].trim() : "";
      return [s, e];
    }
    
    // 尝试英文" - "（前后有空格）
    if (normalized.contains(' - ')) {
      List<String> parts = normalized.split(' - ');
      String s = parts[0].trim();
      String e = parts.length > 1 ? parts[1].trim() : "";
      return [s, e];
    }
    
    // 尝试短横线"-"（需要区分日期中的横杠和时间分隔符）
    // 格式示例：2024-01-15 10:00:00-2024-01-16 10:00:00
    final regex = RegExp(r'(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})\s*[-~]\s*(\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2})');
    final match = regex.firstMatch(normalized);
    if (match != null) {
      return [match.group(1)!.trim(), match.group(2)!.trim()];
    }
    
    // 如果都不匹配，返回原字符串和空字符串
    return [normalized.trim(), ""];
  }

  String getQuestionTypeText(String type) {
    const map = {
      "single": "单选题",
      "multi": "多选题",
      "fill": "填空题",
      "short": "简答题"
    };
    return map[type] ?? "未知";
  }

  Future<void> fetchAllPaperData() async {
    setState(() => loading = true);
    try {
      final resp = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "getExamList",
          "page": 1,
          "limit": 50
        }),
      ).timeout(const Duration(seconds: 15));
      var data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data["success"] == true) {
        setState(() {
          paperList = (data["list"] as List).asMap().entries.map((e) {
            var item = e.value;
            item["index"] = e.key;
            return item;
          }).toList();
        });
      }
    } catch (e) {
      debugPrint("获取试卷列表失败: $e");
    }
    setState(() {
      loading = false;
    });
  }

  Future<void> getExamList() async {
    if (isRequesting) return;

    setState(() {
      isRequesting = true;
    });

    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "list",
        }),
      );

      var data = jsonDecode(res.body);
      if (data["success"] == true) {
        setState(() {
          examList = data["data"] ?? [];
          isRequesting = false;
        });
      } else {
        setState(() {
          isRequesting = false;
        });
        if (mounted) {
          ToastUtil.showError(context, data["message"]);
        }
      }
    } catch (e) {
      setState(() {
        isRequesting = false;
      });
      if (mounted) {
        ToastUtil.showError(context, "网络请求失败");
      }
    }
  }

  String pad2(int n) => n.toString().padLeft(2, '0');

  Future<void> _showTimePickerDialog(bool isStartTime) async {
    final yearController = TextEditingController(
      text: isStartTime ? startYearController.text : endYearController.text
    );
    final monthController = TextEditingController(
      text: isStartTime ? startMonthController.text : endMonthController.text
    );
    final dayController = TextEditingController(
      text: isStartTime ? startDayController.text : endDayController.text
    );
    final hourController = TextEditingController(
      text: isStartTime ? startHourController.text : endHourController.text
    );
    final minuteController = TextEditingController(
      text: isStartTime ? startMinuteController.text : endMinuteController.text
    );
    final secondController = TextEditingController(
      text: isStartTime ? startSecondController.text : endSecondController.text
    );

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isStartTime ? '选择开始时间' : '选择结束时间'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请分别输入年、月、日、时、分、秒', style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(flex: 4, child: _dialogTimeField('年', yearController, 4)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _dialogTimeField('月', monthController, 2)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _dialogTimeField('日', dayController, 2)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(flex: 2, child: _dialogTimeField('时', hourController, 2)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _dialogTimeField('分', minuteController, 2)),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: _dialogTimeField('秒', secondController, 2)),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_validateAndUpdateTime(
                isStartTime,
                yearController,
                monthController,
                dayController,
                hourController,
                minuteController,
                secondController,
              )) {
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              backgroundColor: UIHelpers.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    yearController.dispose();
    monthController.dispose();
    dayController.dispose();
    hourController.dispose();
    minuteController.dispose();
    secondController.dispose();
  }

  Widget _dialogTimeField(String unit, TextEditingController controller, int maxLength) {
    return TextField(
      controller: controller,
      maxLength: maxLength,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        counterText: '',
        hintText: unit,
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(UIHelpers.radiusSmall)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      ),
      style: const TextStyle(fontSize: 14),
      textAlign: TextAlign.center,
    );
  }

  bool _validateAndUpdateTime(
    bool isStartTime,
    TextEditingController yearCtrl,
    TextEditingController monthCtrl,
    TextEditingController dayCtrl,
    TextEditingController hourCtrl,
    TextEditingController minCtrl,
    TextEditingController secCtrl,
  ) {
    try {
      final year = int.parse(yearCtrl.text);
      final month = int.parse(monthCtrl.text);
      final day = int.parse(dayCtrl.text);
      final hour = int.parse(hourCtrl.text);
      final minute = int.parse(minCtrl.text);
      final second = int.parse(secCtrl.text);

      DateTime(year, month, day, hour, minute, second);

      setState(() {
        if (isStartTime) {
          startYearController.text = year.toString();
          startMonthController.text = pad2(month);
          startDayController.text = pad2(day);
          startHourController.text = pad2(hour);
          startMinuteController.text = pad2(minute);
          startSecondController.text = pad2(second);

          final dateTime = DateTime(year, month, day, hour, minute, second);
          editForm["startTimeText"] = '${dateTime.year}-${pad2(dateTime.month)}-${pad2(dateTime.day)} ${pad2(dateTime.hour)}:${pad2(dateTime.minute)}:${pad2(dateTime.second)}';
        } else {
          endYearController.text = year.toString();
          endMonthController.text = pad2(month);
          endDayController.text = pad2(day);
          endHourController.text = pad2(hour);
          endMinuteController.text = pad2(minute);
          endSecondController.text = pad2(second);

          final dateTime = DateTime(year, month, day, hour, minute, second);
          editForm["endTimeText"] = '${dateTime.year}-${pad2(dateTime.month)}-${pad2(dateTime.day)} ${pad2(dateTime.hour)}:${pad2(dateTime.minute)}:${pad2(dateTime.second)}';
        }
      });

      return true;
    } catch (e) {
      showToast('时间格式不正确，请检查输入');
      return false;
    }
  }

  Future<void> togglePaperDetail(String examId) async {
    if (expandId == examId) {
      setState(() {
        expandId = "";
        settingExamId = "";
        loadingPaperId = "";
      });
      return;
    }
    // 🔥 设置加载状态
    setState(() {
      loadingPaperId = examId;
    });
    try {
      final resp = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "getExamById",
          "examId": examId
        }),
      ).timeout(const Duration(seconds: 10));
      var data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data["success"] == true) {
        var target = paperList.firstWhere((p) => p["examId"] == examId, orElse: () => null);
        if (target != null) {
          Map<String, dynamic> scoreMap = {};
          if (data["data"]["perTypeTime"] != null) {
            for (var item in data["data"]["perTypeTime"]) {
              if (item["type"] != null) scoreMap[item["type"]] = item["score"] ?? 0;
            }
          }
          List qs = (data["data"]["questions"] ?? []).map((q) {
            q["score"] = scoreMap[q["type"]] ?? q["score"] ?? 0;
            return q;
          }).toList();
          setState(() => target["questions"] = qs);
        }
      }
    } catch (e) {
      debugPrint("获取试卷详情失败: $e");
    }

    setState(() {
      settingExamId = "";
      expandId = examId;
      loadingPaperId = ""; // 🔥 清除加载状态
    });
  }

  Future<void> toggleSettingPanel(Map<String, dynamic> paper) async {
    if (settingExamId == paper["examId"]) {
      setState(() => settingExamId = "");
      return;
    }
    setState(() {
      expandId = "";
      settingExamId = paper["examId"]!;
    });

    num totalTimeVal = 0;
    int totalTimeUnitIndex = 1; // 默认为"分钟"，方便用户编辑
    
    if (paper["timingType"] == "totalTime" && paper["totalTime"] != null) {
      int backendSeconds = paper["totalTime"];
      // 统一转换为分钟显示，保留小数或者取整视需求而定，这里取整或保留一位小数可能更好，但原代码使用 num
      // 为了兼容原有逻辑并修复单位问题，我们假设后端存储的是秒，前端编辑倾向于分钟
      // 如果正好是分钟的整数倍，直接显示分钟数
      if (backendSeconds % 60 == 0) {
        totalTimeVal = backendSeconds ~/ 60;
      } else {
        // 如果不是整数分钟，可以选择保留小数或强制转为秒。
        // 鉴于 UI 标签是“总时长（分钟）”，且通常考试时间为整数分钟，
        // 这里我们依然尝试以分钟为单位，但如果非整除，可能需要用户重新调整。
        // 为了简单修复 bug，我们优先显示分钟。
        totalTimeVal = backendSeconds / 60;
      }
      totalTimeUnitIndex = 1; // 标记为分钟单位
    }

    List originalQuestions = [];
    List questionTypesData = []; // 🔥 新增：用于存储题型数据
    try {
      final resp = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "getExamById",
          "examId": paper["examId"]
        }),
      ).timeout(const Duration(seconds: 10));
      var data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data["success"] == true) {
        originalQuestions = data["data"]["questions"] ?? [];
        // 🔥 核心修复：后端返回的 perTypeTime 可能为空数组或null
        // 当 perTypeTime 为空时，使用默认值（分数0，时间30秒）
        var pt = data["data"]["perTypeTime"];
        if (pt == null || pt is! List) {
          pt = [];
        }
        Map<String, dynamic> sm = {}, tm = {};
        Map<String, dynamic> fallbackScore = {}, fallbackTime = {};

        for (var q in originalQuestions) {
          if (q is Map && q["type"] != null) {
            final typeKey = q["type"].toString();
            if (!fallbackScore.containsKey(typeKey) && q["score"] != null) {
              final scoreValue = q["score"];
              fallbackScore[typeKey] = scoreValue is num ? scoreValue.toInt() : int.tryParse(scoreValue.toString()) ?? 0;
            }
            if (!fallbackTime.containsKey(typeKey) && q["questionTime"] != null) {
              final timeValue = q["questionTime"];
              fallbackTime[typeKey] = timeValue is num ? timeValue.toInt() : int.tryParse(timeValue.toString()) ?? 30;
            } else if (!fallbackTime.containsKey(typeKey) && q["time"] != null) {
              final timeValue = q["time"];
              fallbackTime[typeKey] = timeValue is num ? timeValue.toInt() : int.tryParse(timeValue.toString()) ?? 30;
            }
          }
        }

        if (data["data"]["questionTypeScores"] is Map) {
          (data["data"]["questionTypeScores"] as Map).forEach((key, value) {
            sm[key.toString()] = value;
          });
        }
        if (data["data"]["questionTypeTimes"] is Map) {
          (data["data"]["questionTypeTimes"] as Map).forEach((key, value) {
            tm[key.toString()] = value;
          });
        }

        for (var i in pt) {
          if (i is Map && i["type"] != null) {
            final typeKey = i["type"].toString();
            sm[typeKey] = i["score"] ?? sm[typeKey] ?? 0;
            tm[typeKey] = i["time"] ?? tm[typeKey] ?? 30;
          }
        }
        
        // 🔥 辅助函数：安全获取整数值
        int getScore(dynamic value) {
          if (value == null) return 0;
          if (value is int) return value;
          if (value is double) return value.toInt();
          if (value is String) return int.tryParse(value) ?? 0;
          return 0;
        }

        int resolveScore(String type) {
          if (sm.containsKey(type)) return getScore(sm[type]);
          return fallbackScore[type] ?? 0;
        }

        int resolveTime(String type) {
          if (tm.containsKey(type)) return getScore(tm[type]);
          return fallbackTime[type] ?? 30;
        }
        
        questionTypesData = [
          {
            "type": "single",
            "label": "单选题",
            "score": resolveScore("single"),
            "originalScore": resolveScore("single"),
            "time": resolveTime("single"),
            "originalTime": resolveTime("single"),
            "timeUnitIndex": _determineTimeUnitIndex(resolveTime("single")),
            "scoreController": TextEditingController(text: resolveScore("single").toString()),
            "timeController": TextEditingController(text: _getTimeDisplayValue(resolveTime("single"), _determineTimeUnitIndex(resolveTime("single"))).toString()),
          },
          {
            "type": "multi",
            "label": "多选题",
            "score": resolveScore("multi"),
            "originalScore": resolveScore("multi"),
            "time": resolveTime("multi"),
            "originalTime": resolveTime("multi"),
            "timeUnitIndex": _determineTimeUnitIndex(resolveTime("multi")),
            "scoreController": TextEditingController(text: resolveScore("multi").toString()),
            "timeController": TextEditingController(text: _getTimeDisplayValue(resolveTime("multi"), _determineTimeUnitIndex(resolveTime("multi"))).toString()),
          },
          {
            "type": "fill",
            "label": "填空题",
            "score": resolveScore("fill"),
            "originalScore": resolveScore("fill"),
            "time": resolveTime("fill"),
            "originalTime": resolveTime("fill"),
            "timeUnitIndex": _determineTimeUnitIndex(resolveTime("fill")),
            "scoreController": TextEditingController(text: resolveScore("fill").toString()),
            "timeController": TextEditingController(text: _getTimeDisplayValue(resolveTime("fill"), _determineTimeUnitIndex(resolveTime("fill"))).toString()),
          },
          {
            "type": "short",
            "label": "简答题",
            "score": resolveScore("short"),
            "originalScore": resolveScore("short"),
            "time": resolveTime("short"),
            "originalTime": resolveTime("short"),
            "timeUnitIndex": _determineTimeUnitIndex(resolveTime("short")),
            "scoreController": TextEditingController(text: resolveScore("short").toString()),
            "timeController": TextEditingController(text: _getTimeDisplayValue(resolveTime("short"), _determineTimeUnitIndex(resolveTime("short"))).toString()),
          },
        ];
        
        // 🔥 调试：打印生成的Controller文本
        for (var qt in questionTypesData) {
          debugPrint('[toggleSettingPanel] ${qt["label"]}: score="${(qt["scoreController"] as TextEditingController).text}", time="${(qt["timeController"] as TextEditingController).text}"');
        }
      }
    } catch (e) {
      debugPrint("获取试卷详情(设置面板)失败: $e");
    }

    var times = splitExamTime(paper["examTime"]);

    DateTime? startDateTime;
    DateTime? endDateTime;

    if (times[0].isNotEmpty) {
      try {
        startDateTime = DateTime.parse(times[0]);
      } catch (e) {
        startDateTime = DateTime.now();
      }
    } else {
      startDateTime = DateTime.now();
    }

    if (times[1].isNotEmpty) {
      try {
        endDateTime = DateTime.parse(times[1]);
      } catch (e) {
        endDateTime = DateTime.now().add(const Duration(hours: 24));
      }
    } else {
      endDateTime = DateTime.now().add(const Duration(hours: 24));
    }

    setState(() {
      editForm["examId"] = paper["examId"]!;
      editForm["paperName"] = paper["examName"]!;
      editForm["originalPaperName"] = paper["examName"]!;
      editForm["subjectIndex"] = subjectList.contains(paper["subject"])
          ? subjectList.indexOf(paper["subject"])
          : 0;
      editForm["examStatusIndex"] = examStatusList.contains(paper["status"])
          ? examStatusList.indexOf(paper["status"])
          : 0;
      editForm["startTimeText"] = times[0];
      editForm["endTimeText"] = times[1];

      // 🔥 同步更新表单字段 Controller
      paperNameController.text = paper["examName"]!;
      totalTimeController.text = totalTimeVal.toString();

      // 赋值时间控制器
      startYearController.text = startDateTime!.year.toString();
      startMonthController.text = pad2(startDateTime.month);
      startDayController.text = pad2(startDateTime.day);
      startHourController.text = pad2(startDateTime.hour);
      startMinuteController.text = pad2(startDateTime.minute);
      startSecondController.text = pad2(startDateTime.second);

      endYearController.text = endDateTime!.year.toString();
      endMonthController.text = pad2(endDateTime.month);
      endDayController.text = pad2(endDateTime.day);
      endHourController.text = pad2(endDateTime.hour);
      endMinuteController.text = pad2(endDateTime.minute);
      endSecondController.text = pad2(endDateTime.second);

      editForm["timeType"] = paper["timingType"] == "totalTime" ? "total" : "per";
      editForm["totalTime"] = totalTimeVal;
      editForm["originalTotalTime"] = totalTimeVal;
      editForm["totalTimeUnitIndex"] = totalTimeUnitIndex;  // 使用实际的时间单位索引
      editForm["originalQuestions"] = originalQuestions;
      
      // 🔥 问题修复：将题型数据更新到editForm中（在同一个setState中）
      if (questionTypesData.isNotEmpty) {
        editForm["questionTypes"] = questionTypesData;
      }
    });
  }

  Future<void> saveExamSetting() async {
    if (editForm["paperName"].isEmpty) {
      showToast("试卷名不能为空");
      return;
    }
    if (editForm["startTimeText"].isEmpty || editForm["endTimeText"].isEmpty) {
      showToast("时间不能为空");
      return;
    }

    List pt = [];
    for (var it in editForm["questionTypes"]) {
      Map<String, dynamic> m = {
        "type": it["type"],
        "score": it["score"] ?? 0,  // 🔥 核心修复：始终提交分数，无论是否变化
      };
      
      // 只有在分题计时模式下才提交时间
      if (editForm["timeType"] == "per") {
        // 获取用户输入的时间值
        num timeValue = it["time"] as num;
        // 根据用户选择的单位进行转换：如果是分钟则乘以60转换为秒存储，如果是秒则直接使用
        int timeInSeconds = (timeValue * (it["timeUnitIndex"] == 1 ? 60 : 1)).toInt();
        m["time"] = timeInSeconds;
      }
      
      pt.add(m);
    }

    List uq = [];
    for (var q in editForm["originalQuestions"]) {
      var cp = Map.of(q);
      for (var t in pt) {
        if (t["type"] == q["type"]) {
          if (t["score"] != null) cp["score"] = t["score"];
          if (t["time"] != null) cp["questionTime"] = t["time"];
        }
      }
      uq.add(cp);
    }

    try {
      final resp = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "updateExam",
          "examId": editForm["examId"],
          "examName": editForm["paperName"],
          "subject": subjectList[editForm["subjectIndex"]],
          "examTime": "${editForm["startTimeText"]}至${editForm["endTimeText"]}",
          "status": examStatusList[editForm["examStatusIndex"]],
          "timingType": editForm["timeType"] == "total" ? "totalTime" : "perQuestionTime",
          "totalTime": editForm["timeType"] == "total"
              ? (editForm["totalTime"] * (editForm["totalTimeUnitIndex"] == 1 ? 60 : 1)).toInt()
              : 0,
          "perTypeTime": pt,
          "questions": uq
        }),
      ).timeout(const Duration(seconds: 15));
      var data = jsonDecode(utf8.decode(resp.bodyBytes));
      if (data["success"] == true) {
        showToast("保存成功");
        setState(() => settingExamId = "");
        fetchAllPaperData();
      } else {
        showToast(data["msg"] ?? "保存失败");
      }
    } catch (e) {
      showToast("保存失败");
    }
  }

  Future<void> deletePaper(Map<String, dynamic> paper) async {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("确认删除"),
        content: Text("确定删除【${paper["examName"]}】？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6)),
            child: const Text("取消")),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              try {
                final resp = await http.post(
                  Uri.parse("$baseUrl/api/exam"),
                  headers: {"Content-Type": "application/json"},
                  body: jsonEncode({
                    "action": "deleteExam",
                    "examId": paper["examId"]
                  }),
                ).timeout(const Duration(seconds: 10));
                var data = jsonDecode(utf8.decode(resp.bodyBytes));
                if (data["success"] == true) {
                  showToast("删除成功");
                  fetchAllPaperData();
                } else {
                  showToast("删除失败");
                }
              } catch (e) {
                showToast("删除失败");
              }
            },
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              foregroundColor: UIHelpers.errorColor,
            ),
            child: const Text("确定", style: TextStyle(color: UIHelpers.errorColor)),
          ),
        ],
      ),
    );
  }

  void openImgUploadPanel(String examId, int idx) {
    setState(() {
      uploadExamId = examId;
      uploadQuestionIndex = idx;
      uploadImgBase64 = "";
    });

    // 🔥 核心修复：使用ValueNotifier实现对话框与外部状态同步
    final previewNotifier = ValueNotifier<String>("");

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text("上传题目图片"),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              // 🔥 即时预览区域 - 使用ValueListenableBuilder监听变化
              ValueListenableBuilder<String>(
                valueListenable: previewNotifier,
                builder: (context, previewImage, _) {
                  if (previewImage.isNotEmpty) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        border: Border.all(color: UIHelpers.primaryColor.withValues(alpha: 0.3), width: 1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(
                          _base64ToUint8List(previewImage),
                          height: 200,
                          width: double.infinity,
                          fit: BoxFit.contain,
                          errorBuilder: (a, b, c) => Container(
                            height: 200,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: Colors.grey[200],
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                SizedBox(height: 8),
                                Text("图片预览失败", style: TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  } else {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        border: Border.all(color: Colors.grey.withValues(alpha: 0.3), width: 1, style: BorderStyle.solid),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.image, size: 48, color: Colors.grey),
                          SizedBox(height: 8),
                          Text("暂无图片，请先选择", style: TextStyle(fontSize: 13, color: Colors.grey)),
                        ],
                      ),
                    );
                  }
                },
              ),

              // 🔥 优化后的按钮组
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.photo_library, size: 18),
                      label: const Text("选择图片"),
                      onPressed: () async {
                        await chooseImage(onImageSelected: () {
                          // 🔥 核心修复：更新ValueNotifier触发预览
                          previewNotifier.value = uploadImgBase64;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UIHelpers.primaryColor.withValues(alpha: 0.15),
                        foregroundColor: UIHelpers.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.camera_alt, size: 18),
                      label: const Text("拍照"),
                      onPressed: () async {
                        await chooseImageFromCamera(onImageSelected: () {
                          // 🔥 核心修复：更新ValueNotifier触发预览
                          previewNotifier.value = uploadImgBase64;
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UIHelpers.primaryColor.withValues(alpha: 0.15),
                        foregroundColor: UIHelpers.primaryColor,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // 🔥 确认上传按钮
              ValueListenableBuilder<String>(
                valueListenable: previewNotifier,
                builder: (context, previewImage, _) {
                  return SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: previewImage.isEmpty
                          ? const Icon(Icons.cloud_upload, size: 18)
                          : const Icon(Icons.check_circle, size: 18),
                      label: Text(previewImage.isEmpty ? "请先选择图片" : "确认上传"),
                      onPressed: previewImage.isEmpty ? null : () {
                        Navigator.pop(ctx);
                        uploadImage();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: UIHelpers.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  );
                },
              ),
            ]),
            actions: [
              TextButton(
                onPressed: () {
                  previewNotifier.dispose();
                  Navigator.pop(ctx);
                },
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                child: const Text("取消"),
              ),
            ],
          );
        },
      ),
    );
  }

  // 🔥 辅助函数：将base64字符串转换为Uint8List用于Image.memory
  Uint8List _base64ToUint8List(String base64String) {
    // 移除data:image前缀
    String pureBase64 = base64String;
    if (base64String.contains(',')) {
      pureBase64 = base64String.split(',').last;
    }
    return base64Decode(pureBase64);
  }

  Future<void> chooseImage({VoidCallback? onImageSelected}) async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (image == null) return;

      List<int> imageBytes = await File(image.path).readAsBytes();
      String base64Image = base64Encode(imageBytes);

      setState(() {
        uploadImgBase64 = "data:image/jpeg;base64,$base64Image";
      });

      if (onImageSelected != null) {
        onImageSelected();
      }

      showToast("选择图片成功");
    } catch (e) {
      showToast("图片选择失败");
    }
  }

  Future<void> chooseImageFromCamera({VoidCallback? onImageSelected}) async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (image == null) return;

      List<int> imageBytes = await File(image.path).readAsBytes();
      String base64Image = base64Encode(imageBytes);

      setState(() {
        uploadImgBase64 = "data:image/jpeg;base64,$base64Image";
      });

      if (onImageSelected != null) {
        onImageSelected();
      }

      showToast("拍照成功");
    } catch (e) {
      showToast("拍照失败");
    }
  }

  Future<void> uploadImage() async {
    if (uploadImgBase64.isEmpty) {
      showToast("请先选择图片");
      return;
    }

    final uploadId = 'exam_image_${DateTime.now().millisecondsSinceEpoch}';

    try {
      UploadProgressManager.startUpload(uploadId, '题目图片');
      showUploadProgress(context, uploadId);

      double progress = 0.0;
      bool uploadCompleted = false;
      final progressTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
        if (!uploadCompleted && progress < 0.9) {
          progress += 0.1;
          UploadProgressManager.updateProgress(uploadId, progress);
        }
      });

      final uploadRes = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "uploadQuestionImage",
          "base64Data": uploadImgBase64
        }),
      ).timeout(const Duration(seconds: 20));

      uploadCompleted = true;
      progressTimer.cancel();
      UploadProgressManager.updateProgress(uploadId, 0.95);

      var uploadData = jsonDecode(utf8.decode(uploadRes.bodyBytes));
      if (!uploadData["success"]) {
        UploadProgressManager.uploadFailed(uploadId, "服务器返回失败");
        if (mounted) ToastUtil.show(context, "图片上传失败");
        if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
        return;
      }

      String imgUrl = uploadData["imgUrl"];

      final bindRes = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "bindImageToQuestion",
          "examId": uploadExamId,
          "questionIndex": uploadQuestionIndex,
          "imgUrl": imgUrl
        }),
      );

      var bindData = jsonDecode(utf8.decode(bindRes.bodyBytes));
      if (bindData["success"] == true) {
        UploadProgressManager.updateProgress(uploadId, 1.0);
        UploadProgressManager.uploadSuccess(uploadId);
        if (mounted) ToastUtil.show(context, "图片添加成功");
      } else {
        UploadProgressManager.uploadFailed(uploadId, "绑定失败");
        if (mounted) ToastUtil.show(context, "绑定失败");
      }
    } catch (e) {
      UploadProgressManager.uploadFailed(uploadId, e.toString());
      if (mounted) ToastUtil.show(context, "上传异常");
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
      await togglePaperDetail(uploadExamId);
    }
  }

  Future<void> _deleteQuestionImage(String examId, int questionIndex, String imgUrl) async {
    bool confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("确认删除"),
        content: const Text("确定要删除这道题的图片吗？"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("取消", style: TextStyle(fontSize: 13)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("删除", style: TextStyle(color: Colors.red, fontSize: 13)),
          ),
        ],
      ),
    );

    if (!confirm) return;

    try {
      final res = await http.post(
        Uri.parse("$baseUrl/api/exam"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "action": "deleteQuestionImage",
          "examId": examId,
          "questionIndex": questionIndex,
          "imgUrl": imgUrl,
        }),
      );

      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        showToast("图片删除成功");
        await togglePaperDetail(examId);
      } else {
        showToast(data["msg"] ?? "删除失败");
      }
    } catch (e) {
      showToast("删除异常：$e");
    }
  }

  void showToast(String msg) {
    if (mounted) ToastUtil.show(context, msg);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: UIHelpers.bgColorLight,
      appBar: AppBar(
        title: const Text("试卷管理", style: TextStyle(fontWeight: FontWeight.w600)),
        centerTitle: true, // 🔥 核心修复：标题居中
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : paperList.isEmpty
              ? const Center(
                  child: Text("暂无试卷数据", style: TextStyle(fontSize: 14, color: Colors.grey)))
              : ListView.builder(
                  padding: EdgeInsets.only(
                      left: 12, right: 12, top: 12, bottom: MediaQuery.of(context).size.height * 0.3),
                  itemCount: paperList.length,
                  itemBuilder: (c, i) => _paperItem(paperList[i]),
                ),
    );
  }

  Widget _paperItem(Map<String, dynamic> paper) {
    bool ex = expandId == paper["examId"];
    bool st = settingExamId == paper["examId"];
    var ts = splitExamTime(paper["examTime"]);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
          boxShadow: [BoxShadow(color: Colors.grey.withValues(alpha: 0.05), blurRadius: 6)]),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth,
                      ),
                      child: Text(paper["examName"] ?? "",
                          style: UIHelpers.titleMedium.copyWith(fontWeight: FontWeight.w600)),
                    );
                  },
                ),
              ),
              Row(
                children: [
                  // 🔥 核心修复：设置按钮 - 更精致的尺寸
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: UIHelpers.primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                      border: Border.all(color: UIHelpers.primaryColor.withValues(alpha: 0.4)),
                    ),
                    child: TextButton(
                      onPressed: () => toggleSettingPanel(paper),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text("设置", style: TextStyle(color: UIHelpers.primaryColor, fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 🔥 核心修复：删除按钮 - 更精致的尺寸
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: UIHelpers.errorColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: UIHelpers.errorColor.withValues(alpha: 0.4)),
                    ),
                    child: TextButton(
                      onPressed: () => deletePaper(paper),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: const Text("删除", style: TextStyle(color: UIHelpers.errorColor, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                ),
                child: Text("科目：${paper["subject"] ?? ""}"),
              );
            },
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                ),
                child: Text("开始：${ts[0]}", style: UIHelpers.bodySmall.copyWith(fontSize: 12)),
              );
            },
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                ),
                child: Text("结束：${ts[1]}", style: UIHelpers.bodySmall.copyWith(fontSize: 12)),
              );
            },
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth,
                ),
                child: Text("计时：${paper["timingType"] == "totalTime" ? "总计时" : "每题计时"}"),
              );
            },
          ),
          const SizedBox(height: 8),
          // 🔥 核心修复：添加加载动画
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: loadingPaperId == paper["examId"]
                ? const SizedBox(
                    height: 30,
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: UIHelpers.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(UIHelpers.radiusRound),
                        border: Border.all(color: UIHelpers.primaryColor.withValues(alpha: 0.4)),
                      ),
                      child: TextButton(
                        onPressed: () => togglePaperDetail(paper["examId"]),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: Text(ex ? "↑ 收起题目" : "↓ 查看题目",
                            style: const TextStyle(color: UIHelpers.primaryColor, fontSize: 12)),
                      ),
                    ),
                  ),
          ),
          if (ex && !st)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _questions(paper),
            ),
          if (st) _settingPanel(),
        ],
      ),
    );
  }

  Widget _questions(Map<String, dynamic> paper) {
    List qs = paper["questions"] ?? [];
    if (qs.isEmpty) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(16), child: Text("该试卷暂无题目")));
    }

    // 🔥 统计各题型数据
    Map<String, int> typeCount = {};
    Map<String, num> typeScore = {};
    for (var q in qs) {
      String type = q["type"] ?? "unknown";
      num score = q["score"] ?? 0;
      typeCount[type] = (typeCount[type] ?? 0) + 1;
      typeScore[type] = (typeScore[type] ?? 0) + score;
    }

    // 🔥 计算整体总分
    num totalScore = 0;
    for (var score in typeScore.values) {
      totalScore += score;
    }

    // 🔥 定义题型顺序
    const typeOrder = ["single", "multi", "fill", "short"];
    List<Map<String, dynamic>> typeSummary = [];
    for (var type in typeOrder) {
      if (typeCount.containsKey(type)) {
        typeSummary.add({
          "type": type,
          "label": getQuestionTypeText(type),
          "count": typeCount[type]!,
          "scorePerQuestion": qs.firstWhere((q) => q["type"] == type, orElse: () => {"score": 0})["score"] ?? 0,
          "typeTotalScore": typeScore[type]!,
        });
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 🔥 题型统计表格
        Container(
          margin: const EdgeInsets.only(top: 8, bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
            border: Border.all(color: UIHelpers.primaryColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              // 🔥 核心修复：简化表格布局，移除Stack跨行合并，改用传统方式显示整体总分
              // 表头
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: UIHelpers.primaryColor.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(UIHelpers.radiusMedium),
                    topRight: Radius.circular(UIHelpers.radiusMedium),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(flex: 3, child: Text("题型", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    const Expanded(flex: 2, child: Text("题数", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    const Expanded(flex: 2, child: Text("单题分", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    const Expanded(flex: 2, child: Text("题总分", textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '卷总分 $totalScore分',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange),
                      ),
                    ),
                  ],
                ),
              ),
              // 表格内容
              ...List.generate(typeSummary.length, (index) {
                var item = typeSummary[index];
                bool isLastRow = index == typeSummary.length - 1;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.grey.withValues(alpha: 0.1),
                        width: isLastRow ? 0 : 1,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 3, child: Text(item["label"], style: const TextStyle(fontSize: 13))),
                      Expanded(flex: 2, child: Text("${item["count"]}", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                      Expanded(flex: 2, child: Text("${item["scorePerQuestion"]}分", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                      Expanded(flex: 2, child: Text("${item["typeTotalScore"]}分", textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: UIHelpers.primaryColor, fontWeight: FontWeight.w500))),
                      const Expanded(flex: 2, child: SizedBox()), // 卷总分列在数据行留空
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
        // 🔥 题目列表
        ...qs.asMap().entries.map((e) {
          int idx = e.key;
          var q = e.value;
          return Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(UIHelpers.radiusMedium)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("第${idx + 1}题"),
                    const SizedBox(width: 8),
                    Text(getQuestionTypeText(q["type"]),
                        style: const TextStyle(color: UIHelpers.primaryColor)),
                    const SizedBox(width: 8),
                    Text("${q["score"] ?? 0}分"),
                    const Spacer(),
                    // 🔥 核心修复：加图按钮 - 更精致的尺寸
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: UIHelpers.primaryColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                        border: Border.all(color: UIHelpers.primaryColor.withValues(alpha: 0.4)),
                      ),
                      child: TextButton(
                        onPressed: () => openImgUploadPanel(paper["examId"], idx),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: const Text("加图", style: TextStyle(color: UIHelpers.primaryColor, fontSize: 11)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 🔥 核心修复：使用 Align 确保公式自然换行
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width - 60, // 减去左右边距
                    ),
                    child: FormulaRenderer.renderMixedText(
                      "${q["title"] ?? q["content"] ?? ""}",
                      style: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                      // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
                    ),
                  ),
                ),

                if (q["imgUrl"] != null && q["imgUrl"].toString().isNotEmpty)
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              q["imgUrl"],
                              fit: BoxFit.contain,
                              height: 150,
                              errorBuilder: (a,b,c) => Container(
                                height: 150,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.grey[200],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text("🖼️ 图片加载失败", style: TextStyle(fontSize: 12)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // 🔥 核心修复：删除图片按钮 - 更精致的尺寸
                        Expanded(
                          flex: 1,
                          child: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), // 🔥 减小图标尺寸
                            onPressed: () => _deleteQuestionImage(expandId, idx, q["imgUrl"]),
                            tooltip: "删除图片",
                            padding: EdgeInsets.zero, // 🔥 移除内边距
                            constraints: const BoxConstraints(), // 🔥 移除约束
                          ),
                        ),
                      ],
                    ),
                  ),
                if (["single", "multi"].contains(q["type"]) && q["options"] != null)
                  ...List.generate(q["options"].length, (i) {
                    // 🔥 核心修复：选项中的公式应该作为行内公式显示（不换行）
                    // 将 $$...$$ 转换为 $...$，确保公式和选项字母在同一行
                    String optionContent = q["options"][i];
                    optionContent = optionContent.replaceAllMapped(
                      RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true, dotAll: true),
                      (match) => '\$${match.group(1)}\$',
                    );
                    
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("${String.fromCharCode(65 + i)}. ", style: const TextStyle(fontSize: 13, color: Colors.black87)),
                          // 🔥 核心修复：使用 Flexible 确保选项内容正确换行
                          Flexible(
                            fit: FlexFit.loose,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                return ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth,
                                  ),
                                  child: FormulaRenderer.renderMixedText(
                                    optionContent,  // 使用转换后的内容
                                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                                    // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                if (q["answer"] != null && q["answer"].isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width - 60, // 减去左右边距
                      ),
                      child: FormulaRenderer.renderMixedText("答案：${q["answer"]}",
                          style: const TextStyle(color: Colors.green, fontSize: 13),
                          // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
                        ),
                    ),
                  ),
                if (q["analysis"] != null && q["analysis"].isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width - 60, // 减去左右边距
                      ),
                      child: FormulaRenderer.renderMixedText("解析：${q["analysis"]}",
                          style: const TextStyle(color: Colors.orange, fontSize: 13),
                          // 🔥 修复：移除 autoWrapLatex，避免对已有正确格式的公式进行二次包裹
                        ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _settingPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(labelText: "试卷名称"),
            controller: paperNameController, // 🔥 使用持久的 Controller
            autofocus: false, // 🔥 修复：禁止自动聚焦
            onChanged: (v) {
              setState(() => editForm["paperName"] = v);
              paperNameController.text = v; // 🔥 同步更新
            },
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: editForm["subjectIndex"],
            items: List.generate(
                subjectList.length, (i) => DropdownMenuItem(value: i, child: Text(subjectList[i]))),
            onChanged: (v) => setState(() => editForm["subjectIndex"] = v!),
            decoration: const InputDecoration(labelText: "科目"),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: editForm["examStatusIndex"],
            items: List.generate(
                examStatusList.length, (i) => DropdownMenuItem(value: i, child: Text(examStatusList[i]))),
            onChanged: (v) => setState(() => editForm["examStatusIndex"] = v!),
            decoration: const InputDecoration(labelText: "考试类型"),
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('开始时间', style: TextStyle(color: Colors.black87, fontSize: 12)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _showTimePickerDialog(true),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    (editForm["startTimeText"] ?? '').isEmpty ? '点击选择开始时间' : editForm["startTimeText"]!,
                    style: TextStyle(
                      color: (editForm["startTimeText"] ?? '').isEmpty ? UIHelpers.textHint : UIHelpers.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('结束时间', style: TextStyle(color: Colors.black87, fontSize: 12)),
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => _showTimePickerDialog(false),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    (editForm["endTimeText"] ?? '').isEmpty ? '点击选择结束时间' : editForm["endTimeText"]!,
                    style: TextStyle(
                      color: (editForm["endTimeText"] ?? '').isEmpty ? UIHelpers.textHint : UIHelpers.textPrimary,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: editForm["timeType"] == "per" ? UIHelpers.primaryColor : Colors.grey[200],
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8)),
                  onPressed: () => setState(() => editForm["timeType"] = "per"),
                  child: const Text("每题计时", style: TextStyle(fontSize: 13)),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: editForm["timeType"] == "total" ? UIHelpers.primaryColor : Colors.grey[200],
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8)),
                  onPressed: () => setState(() => editForm["timeType"] = "total"),
                  child: const Text("总计时", style: TextStyle(fontSize: 13)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text("题型分数设置", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ...List.generate(editForm["questionTypes"].length, (i) {
            var item = editForm["questionTypes"][i];
            return Padding(
              key: ValueKey('question-type-${item["type"]}'),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(flex: 2, child: Text(item["label"], style: UIHelpers.bodyNormal.copyWith(fontSize: 14))),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      keyboardType: TextInputType.numberWithOptions(decimal: false), // 🔥 核心修复：禁止小数输入
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly], // 🔥 只允许数字
                      decoration: const InputDecoration(
                        labelText: "每题分数",
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      controller: item["scoreController"] as TextEditingController, // 🔥 使用持久的 Controller
                      autofocus: false, // 🔥 修复：禁止自动聚焦
                      onChanged: (v) {
                        final newValue = int.tryParse(v) ?? 0;
                        setState(() => item["score"] = newValue);
                        // 🔥 修复：确保显示的是整数，去除小数位
                        if ((item["scoreController"] as TextEditingController).text != v) {
                          (item["scoreController"] as TextEditingController).text = newValue.toString();
                        }
                      },
                    ),
                  ),
                  if (editForm["timeType"] == "per") const SizedBox(width: 8),
                  if (editForm["timeType"] == "per")
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              keyboardType: TextInputType.numberWithOptions(decimal: false), // 🔥 核心修复：禁止小数输入
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly], // 🔥 只允许数字
                              decoration: const InputDecoration(
                                labelText: "每题时间",
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              ),
                              controller: item["timeController"] as TextEditingController, // 🔥 使用持久的 Controller
                              autofocus: false, // 🔥 修复：禁止自动聚焦
                              onChanged: (v) {
                                final newValue = int.tryParse(v) ?? 0;
                                setState(() => item["time"] = newValue);
                                // 🔥 修复：确保显示的是整数，去除小数位
                                if ((item["timeController"] as TextEditingController).text != v) {
                                  (item["timeController"] as TextEditingController).text = newValue.toString();
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setState(() {
                              item["timeUnitIndex"] = item["timeUnitIndex"] == 0 ? 1 : 0;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                              ),
                              child: Text(
                                timeUnits[item["timeUnitIndex"]],
                                style: UIHelpers.buttonNormal.copyWith(fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
          if (editForm["timeType"] == "total")
            TextField(
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "总时长（分钟）"),
              controller: totalTimeController, // 🔥 使用持久的 Controller
              autofocus: false, // 🔥 修复：禁止自动聚焦
              onChanged: (v) {
                final newValue = num.tryParse(v) ?? 0;
                setState(() => editForm["totalTime"] = newValue);
                totalTimeController.text = v; // 🔥 同步更新
              },
            ),
          const SizedBox(height: 16),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    backgroundColor: UIHelpers.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: saveExamSetting,
                  child: const Text("保存修改", style: TextStyle(fontSize: 14))))
        ],
      ),
    );
  }
}