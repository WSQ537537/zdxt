import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zdxtapp/config.dart';
import 'package:flutter/scheduler.dart';
import '../../widgets/common_video_player.dart';

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with WidgetsBindingObserver {
  final String baseUrl = Config.baseUrl;

  String account = '';
  String remark = '';
  String todayDate = '';

  // ====================== 修复 1：补全「其他」科目 ======================
  final List<String> tabs = ['语文', '数学', '英语', '其他'];
  final Map<String, String> subjectMap = {
    '语文': 'chinese',
    '数学': 'math',
    '英语': 'english',
    '其他': 'other',
  };

  int activeTab = 0;
  List<dynamic> videoList = [];
  bool isLoading = false;
  int openIndex = -1;

  Map<String, dynamic> studyStats = {
    'require': 0,
    'finished': 0,
    'percent': 0.0,
  };

  final ScrollController _scrollController = ScrollController();

  // ====================== 修复 2：视频计时全套逻辑 ======================
  bool timerVisible = false;
  int sessionSeconds = 0;  // ✅ 当前会话累计时间（未提交）
  int totalSubmittedSeconds = 0;  // ✅ 已提交的总时间
  Timer? timerInterval;
  Timer? submitInterval;

  Offset timerPosition = const Offset(20, 100);
  Offset? dragStart;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initUserAndDate();
    loadVideoList();
    loadStudyStats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _stopTimer();
    super.dispose();
  }


  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _stopTimer(); // ✅ 应用进入后台时暂停计时（保留累计时间）
    } else if (state == AppLifecycleState.resumed) {
      // ✅ 应用恢复前台时，如果视频仍在播放则继续计时
      // 注意：这里不自动重启，由视频的 onPlay 回调控制
    }
  }

  Future<void> _initUserAndDate() async {
    final prefs = await SharedPreferences.getInstance();
    final userInfo = prefs.getString('userInfo');
    if (userInfo != null) {
      final user = jsonDecode(userInfo);
      setState(() {
        account = user['account'] ?? '';
        remark = user['remark'] ?? '';
      });
    }
    setState(() {
      todayDate = DateTime.now().toIso8601String().split('T')[0];
    });
  }

  void switchTab(int idx) {
    _resetTimer(); // ✅ 切换科目时重置计时
    setState(() {
      activeTab = idx;
      openIndex = -1;
    });
    loadVideoList();
    loadStudyStats();
  }

  Future<void> loadVideoList() async {
    setState(() => isLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/video'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'getAll',
          'subject': subjectMap[tabs[activeTab]],
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() {
          videoList = data['data'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Load video error: $e');
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> loadStudyStats() async {
    await _initUserAndDate();
    try {
      final configRes = await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getConfig'}),
      );
      final configData = jsonDecode(configRes.body);

      final recordRes = await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'getUserStudyRecord',
          'userid': account,
          'date': todayDate,
        }),
      );
      final recordData = jsonDecode(recordRes.body);

      final weekDay = DateTime.now().weekday;
      final configList = configData['success'] ? configData['data'] ?? [] : [];
      final todayConfig = configList.firstWhere(
        (e) => e['weekday'] == weekDay,
        orElse: () => {'subjects': {}},
      );
      final subjects = todayConfig['subjects'] ?? {};
      final record = recordData['success'] ? recordData['data'] ?? {} : {};

      final subKey = subjectMap[tabs[activeTab]]!;
      final require = (subjects[subKey] ?? 0).toInt();
      final finished = (record[subKey] ?? 0).toInt();
      final percent = require > 0 ? (finished / require) * 100 : 0.0;

      setState(() {
        studyStats = {
          'require': require,
          'finished': finished,
          'percent': percent,
        };
      });
    } catch (e) {
      debugPrint('Stats error: $e');
    }
  }

  // ====================== 核心：启动计时（连续计时，不重置）======================
  void _startTimer() {
    // 如果已经在计时，直接返回（避免重复创建）
    if (timerInterval != null && timerInterval!.isActive) return;
    
    setState(() {
      timerVisible = true;
      // ✅ 关键修复：不清零 sessionSeconds，保持连续计时
    });

    // 每秒 +1（累计当前会话时间）
    timerInterval = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => sessionSeconds++);
      }
    });

    // ✅ 修复：每30秒提交一次（减少请求频率）
    submitInterval = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (sessionSeconds >= 30) {
        await submitStudyTime(30);
        // ✅ 关键修复：减去已提交的30秒，保留剩余时间
        setState(() {
          sessionSeconds -= 30;
          totalSubmittedSeconds += 30;
        });
      }
    });
  }

  // ====================== 核心：停止计时（保留累计时间）======================
  void _stopTimer() async {
    // ✅ 修复：先提交剩余的秒数（不足30秒的部分）
    if (sessionSeconds > 0) {
      await submitStudyTime(sessionSeconds);
      setState(() {
        totalSubmittedSeconds += sessionSeconds;
        sessionSeconds = 0;
      });
    }
    
    timerInterval?.cancel();
    submitInterval?.cancel();
    
    setState(() {
      timerInterval = null;
      submitInterval = null;
      // ✅ 关键修复：不清零 timerVisible，让计时器持续显示总学习时间
    });
  }

  // ====================== 🔥 新增：暂停计时（缓冲时使用，不提交）======================
  void _pauseTimer() {
    // 🔥 缓冲时只暂停计时器，不提交时间
    timerInterval?.cancel();
    submitInterval?.cancel();
    
    setState(() {
      timerInterval = null;
      submitInterval = null;
      // 不清零 sessionSeconds，保留已累计的时间
    });
  }

  // ====================== 🔥 新增：恢复计时（缓冲结束后使用）======================
  void _resumeTimer() {
    // 🔥 如果计时器已经在运行，直接返回
    if (timerInterval != null && timerInterval!.isActive) return;
    
    setState(() {
      timerVisible = true;
    });

    // 重新启动计时器
    timerInterval = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => sessionSeconds++);
      }
    });

    // 重新启动提交定时器
    submitInterval = Timer.periodic(const Duration(seconds: 30), (_) async {
      if (sessionSeconds >= 30) {
        await submitStudyTime(30);
        setState(() {
          sessionSeconds -= 30;
          totalSubmittedSeconds += 30;
        });
      }
    });
  }

  // ====================== 完全退出视频时清零 ======================
  void _resetTimer() async {
    // 先提交剩余时间
    if (sessionSeconds > 0) {
      await submitStudyTime(sessionSeconds);
      setState(() {
        totalSubmittedSeconds += sessionSeconds;
      });
    }
    
    timerInterval?.cancel();
    submitInterval?.cancel();
    
    setState(() {
      timerInterval = null;
      submitInterval = null;
      sessionSeconds = 0;         // ✅ 清零当前会话时间
      totalSubmittedSeconds = 0;  // ✅ 清零已提交时间
      timerVisible = false;       // ✅ 隐藏计时器
    });
  }

  // ====================== 构建悬浮计时器组件 ======================
  Widget _buildFloatingTimer() {
    return GestureDetector(
      onPanStart: (d) {
        dragStart = d.localPosition;
      },
      onPanUpdate: (d) {
        setState(() {
          timerPosition = Offset(
            timerPosition.dx + d.delta.dx,
            timerPosition.dy + d.delta.dy,
          );
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
        ),
        child: Text(
          formatTime,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
    );
  }

  // ====================== 提交时长到后端 ======================
  Future<void> submitStudyTime(int seconds) async {
    if (account.isEmpty || seconds <= 0) return;
    final subject = subjectMap[tabs[activeTab]];
    final minutes = seconds / 60;
    try {
      await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'addRecord',
          'userid': account,
          'date': todayDate,
          'subject': subject,
          'minutes': minutes,
          'remark': remark,
        }),
      );
      SchedulerBinding.instance.addPostFrameCallback((_) {
        loadStudyStats();
      });
    } catch (e) {
      debugPrint('Submit error: $e');
    }
  }

  String get formatTime {
    // ✅ 显示总学习时间（已提交 + 当前会话）
    int totalSeconds = totalSubmittedSeconds + sessionSeconds;
    int min = totalSeconds ~/ 60;
    int sec = totalSeconds % 60;
    return '已学习：${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // ✅ 固定区域：标题 + 标签栏 + 时间卡片（移除背景）
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),  // ✅ 减少垂直内边距从 20 改为 16，让卡片往上移
              // ✅ 移除 gradient 背景装饰，保持透明
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,  // ✅ 左对齐
                children: [
                  // ✅ 标题行：左侧"学习中心"，右侧"课程资源"按钮
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "学习中心",
                        style: TextStyle(
                          fontSize: 18,  // ✅ 字体从 16 放大到 18
                          color: Colors.white,
                          fontWeight: FontWeight.w600,  // ✅ 加粗
                        ),
                      ),
                      // ✅ 课程资源按钮
                      GestureDetector(
                        onTap: () {
                          Navigator.pushNamed(context, '/public/browser');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.book, size: 16, color: Colors.black87),
                              SizedBox(width: 4),
                              Text(
                                '课程资源',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),  // 🔥 缩小间距从12改为6，让科目标签栏靠近课程资源按钮下边界

                  // 标签栏（固定）
                  Container(
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: tabs.asMap().entries.map((e) {
                        int idx = e.key;
                        String t = e.value;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () => switchTab(idx),
                            child: Container(
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color:
                                    activeTab == idx ? Colors.blue : Colors.transparent,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Text(
                                t,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: activeTab == idx
                                      ? Colors.white
                                      : Colors.black54,
                                  fontWeight: activeTab == idx
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 8),  // ✅ 缩小间距从 12 改为 8，让时长卡片和科目标题更紧凑

                  // 进度卡片（固定）
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(14),
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
                          "今日 ${tabs[activeTab]} 学习进度",
                          style: const TextStyle(
                            color: Colors.black87,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("要求：${studyStats['require']} 分钟",
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 12)),
                            Text("已学：${studyStats['finished']} 分钟",
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: studyStats['percent'] / 100,
                            backgroundColor: Colors.black12,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text("完成度：${studyStats['percent'].toStringAsFixed(1)}%",
                            style: const TextStyle(
                                color: Colors.black54, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ✅ 可滚动内容区域：视频列表（参考 admin exam：使用 ShaderMask 实现渐变效果）
          Positioned(
            top: 230,  // 🔥 渐变边界线往上移，更靠近进度卡片下边界
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
              child: SingleChildScrollView(
                controller: _scrollController,  // ✅ 绑定滚动控制器
                padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 100),  // 🔥 减少顶部间距，让第一个视频卡片靠近渐变边界线
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    if (isLoading)
                      const Center(
                          child: CircularProgressIndicator(color: Colors.white))
                    else if (videoList.isEmpty)
                      const Center(
                          child: Text("暂无视频",
                              style: TextStyle(color: Colors.white70, fontSize: 14)))
                    else
                      ...videoList.asMap().entries.map((e) {
                        int idx = e.key;
                        var video = e.value;
                        bool isOpen = openIndex == idx;
                        return Container(
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
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  onTap: () {
                                    setState(() {
                                      if (isOpen) {
                                        // ✅ 关闭当前视频时重置计时
                                        _resetTimer();
                                        openIndex = -1;
                                      } else {
                                        // ✅ 打开新视频前先停止之前的计时
                                        _resetTimer();
                                        openIndex = idx;
                                      }
                                    });
                                  },
                                  leading: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.video_library,
                                        color: Colors.blue, size: 20),
                                  ),
                                  title: Text(video['name'] ?? '视频',
                                      style: const TextStyle(
                                          color: Colors.black87, fontSize: 14)),
                                  trailing: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      isOpen ? Icons.expand_less : Icons.expand_more,
                                      color: Colors.black54,
                                      size: 20,
                                    ),
                                  ),
                                ),
                                if (isOpen)
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(12, 0, 12, 10),
                                    child: Stack(
                                      children: [
                                        CommonVideoPlayer(
                                          videoUrl: video['url'] ?? '',
                                          videoType: video['isOnline'] == true ? 2 : 1, // 🔥 添加videoType参数
                                          autoPlay: true,
                                          onVideoClosed: () {
                                            _resetTimer(); // ✅ 完全退出时清零
                                            setState(() => openIndex = -1);
                                          },
                                          // ====================== 视频播放联动计时 ======================
                                          onPlay: _startTimer,
                                          onPause: _stopTimer, // ✅ 暂停时保留累计时间
                                          onEnd: () {
                                            _resetTimer(); // ✅ 播放结束时清零
                                            setState(() => openIndex = -1); // 🔥 播放完自动收起卡片
                                          },
                                          // 🔥 新增：缓冲状态监听（卡顿时暂停计时）
                                          onBuffering: (isBuffering) {
                                            if (isBuffering) {
                                              _pauseTimer(); // 缓冲时暂停计时
                                            } else {
                                              _resumeTimer(); // 缓冲结束后恢复计时
                                            }
                                          },
                                        ),
                                        // ✅ 悬浮计时器放在视频外部，更靠近左上角边缘
                                        if (timerVisible)
                                          Positioned(
                                            left: 8,
                                            top: 8,
                                            child: Material(
                                              color: Colors.transparent,
                                              elevation: 4,
                                              borderRadius: BorderRadius.circular(8),
                                              child: _buildFloatingTimer(),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                      }),

                    SizedBox(height: MediaQuery.of(context).size.height * 0.15),  // ✅ 减少底部留白，因为固定区域已占用空间
                  ],
                ),
              ),
            ),
          ),

        ],
      ),
    );
  }
}