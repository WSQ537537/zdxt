import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/upload_progress.dart';
import '../../widgets/common_video_player.dart';
import 'package:zdxtapp/utils/ui_helpers.dart'; // 🔥 全局UI辅助工具

class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  final String baseUrl = Config.baseUrl;
  int mainTab = 1;

  final List<String> weekList = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  String selDay = '周一';
  Map<String, Map<String, String>> timeData = {};

  final List<String> tabs = ['全部', '语文', '数学', '英语', '其他'];
  final Map<String, String> subjectMap = {
    '语文': 'chinese',
    '数学': 'math',
    '英语': 'english',
    '其他': 'other'
  };
  int activeTab = 0;
  List<dynamic> videoList = [];
  bool isLoading = false;
  int openIndex = -1;

  List<dynamic> batchList = [];
  bool showBatchPopup = false;
  int currentIndex = 0;
  int totalCount = 0;
  String currentVideoName = '';
  bool uploading = false;
  int uploadingIndex = 0;
  int uploadingTotal = 0;
  String uploadingName = '';
  double uploadProgress = 0;

  String searchKey = '';
  List<dynamic> userProgressList = [];
  bool progressLoading = false;
  int expandedUser = -1;
  Map<int, int> expandedWeek = {};

  bool showOnlineVideoPopup = false;
  String onlineVideoUrl = '';
  String onlineVideoName = '';
  String biliParseUrl = '';

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    initTimeData();
    loadVideoList();
  }

  void initTimeData() {
    setState(() {
      timeData = {
        '周一': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周二': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周三': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周四': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周五': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周六': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
        '周日': {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'},
      };
    });
  }

  Future<void> handleMainTabChange(int index) async {
    if (!mounted) return;
    setState(() => mainTab = index);
    if (index == 1) {
      loadVideoList();
    } else if (index == 0) {
      await loadTimeConfig();
    } else if (index == 2) {
      searchKey = '';
      await searchProgress();
    }
  }

  Future<void> loadTimeConfig() async {
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'getConfig'}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final Map<String, Map<String, String>> newData = {};
        for (final day in weekList) {
          newData[day] = {'yw': '0', 'sx': '0', 'en': '0', 'ot': '0'};
        }

        final weekMap = {1: '周一', 2: '周二', 3: '周三', 4: '周四', 5: '周五', 6: '周六', 7: '周日'};
        for (final item in data['data'] ?? []) {
          final day = weekMap[item['weekday']];
          if (day != null) {
            newData[day] = {
              'yw': item['subjects']['chinese']?.toString() ?? '0',
              'sx': item['subjects']['math']?.toString() ?? '0',
              'en': item['subjects']['english']?.toString() ?? '0',
              'ot': item['subjects']['other']?.toString() ?? '0',
            };
          }
        }
        setState(() => timeData = newData);
      }
    } catch (e) {
      debugPrint('❌ loadTimeConfig异常: $e');
    }
  }

  Future<void> saveTimeConfig() async {
    try {
      final weekMap = {'周一': 1, '周二': 2, '周三': 3, '周四': 4, '周五': 5, '周六': 6, '周日': 7};
      final List<Map<String, dynamic>> weekConfig = [];

      for (final entry in timeData.entries) {
        final day = entry.key;
        final sub = entry.value;
        weekConfig.add({
          'weekday': weekMap[day],
          'subjects': {
            'chinese': int.tryParse(sub['yw'] ?? '0') ?? 0,
            'math': int.tryParse(sub['sx'] ?? '0') ?? 0,
            'english': int.tryParse(sub['en'] ?? '0') ?? 0,
            'other': int.tryParse(sub['ot'] ?? '0') ?? 0,
          }
        });
      }

      await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'setConfig', 'weekConfig': weekConfig}),
      );
      await loadTimeConfig();
      if (mounted) {
        ToastUtil.show(context, '保存成功');
      }
    } catch (e) {
      if (mounted) {
        ToastUtil.show(context, '保存失败');
      }
    }
  }

  void toggleVideoPlay(int idx) {
    setState(() {
      if (openIndex == idx) {
        openIndex = -1;
      } else {
        openIndex = idx;
      }
    });
  }

  Future<void> chooseVideos() async {
    try {
      final XFile? video = await _picker.pickVideo(
        source: ImageSource.gallery,
      );

      if (video == null) return;

      String fileName = video.name.toLowerCase();
      if (!fileName.endsWith('.mp4') && !fileName.endsWith('.mov') &&
          !fileName.endsWith('.avi') && !fileName.endsWith('.mkv') &&
          !fileName.endsWith('.wmv') && !fileName.endsWith('.flv')) {
        if (mounted) {
          ToastUtil.show(context, '请选择视频文件（MP4、MOV、AVI等格式）');
        }
        return;
      }

      String name = video.name;
      if (name.contains('.')) {
        name = name.substring(0, name.lastIndexOf('.'));
      }

      batchList = [
        {
          'path': video.path,
          'name': name.trim(),
          'editing': false,
        }
      ];

      setState(() {
        totalCount = batchList.length;
        currentIndex = 0;
        currentVideoName = batchList[0]['name'];
        showBatchPopup = true;
      });
    } catch (e) {
      if (mounted) {
        ToastUtil.show(context, '选择视频失败: $e');
      }
    }
  }

  void switchTab(int idx) {
    if (activeTab == idx) return;
    setState(() => activeTab = idx);
    loadVideoList();
  }

  void showOnlineVideoDialog() {
    setState(() {
      onlineVideoUrl = '';
      onlineVideoName = '';
      showOnlineVideoPopup = true;
    });
  }

  Future<void> loadVideoList() async {
    setState(() {
      isLoading = true;
      videoList.clear();
    });
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/video'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'getAll',
          'subject': subjectMap[tabs[activeTab]] ?? ''
        }),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        setState(() => videoList = data['data'] ?? []);
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> deleteVideo(dynamic item) async {
    try {
      await http.post(
        Uri.parse('$baseUrl/api/video'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'delete', 'videoId': item['_id'] ?? item['videoId']}),
      );
      loadVideoList();
    } catch (e) {
      debugPrint('❌ deleteVideo异常: $e');
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

  Future<void> searchProgress() async {
    setState(() => progressLoading = true);
    try {
      final res = await http.post(
        Uri.parse('$baseUrl/api/time'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'searchProgress', 'searchKey': searchKey.trim()}),
      );
      final data = jsonDecode(res.body);
      debugPrint('🔍 Admin端请求参数: ${jsonEncode({'action': 'searchProgress', 'searchKey': searchKey.trim()})}');
      debugPrint('📊 Admin端完整响应: ${res.body}');

      if (data['success'] == true) {
        setState(() => userProgressList = data['data'] ?? []);
      } else {
        debugPrint('❌ 后端返回失败: ${data['message']}');
      }
    } catch (e) {
      debugPrint('❌ searchProgress异常: $e');
    } finally {
      setState(() => progressLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildMainTab(),
                  const SizedBox(height: 16),
                  Expanded(
                    child: IndexedStack(
                      index: mainTab,
                      children: [
                        _buildTimePage(),
                        _buildVideoPage(),
                        _buildProgressPage(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (showBatchPopup) _buildBatchUploadDialog(),
            if (showOnlineVideoPopup) _buildOnlineVideoDialog(),
          ],
        ),
      ),
    );
  }

  Widget _buildMainTab() {
    return Container(
      padding: const EdgeInsets.all(4),
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
          _buildMainTabItem("时长要求配置", 0),
          _buildMainTabItem("科目视频管理", 1),
          _buildMainTabItem("用户学习进度", 2),
        ],
      ),
    );
  }

  Widget _buildMainTabItem(String text, int idx) {
    return Expanded(
      child: GestureDetector(
        onTap: () => handleMainTabChange(idx),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: mainTab == idx ? UIHelpers.primaryColor : Colors.transparent,
            borderRadius: BorderRadius.circular(UIHelpers.radiusRound),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: mainTab == idx ? Colors.white : Colors.black87,
              fontWeight: mainTab == idx ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimePage() {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: weekList.map((day) {
              return GestureDetector(
                onTap: () => setState(() => selDay = day),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: selDay == day ? UIHelpers.primaryColor : Colors.white.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(UIHelpers.radiusLarge),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(day, style: TextStyle(color: selDay == day ? Colors.white : Colors.black87)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _buildInputItem("语文", "yw"),
          _buildInputItem("数学", "sx"),
          _buildInputItem("英语", "en"),
          _buildInputItem("其他", "ot"),
          const SizedBox(height: 24),
          Center(
            child: ElevatedButton(
              onPressed: saveTimeConfig,
              style: ElevatedButton.styleFrom(
                backgroundColor: UIHelpers.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text("保存配置"),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputItem(String label, String key) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
          SizedBox(width: 60, child: Text(label, style: const TextStyle(fontSize: 16))),
          Expanded(
            child: TextField(
              keyboardType: TextInputType.number,
              controller: TextEditingController(text: timeData[selDay]![key]),
              onChanged: (v) => timeData[selDay]![key] = v,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const Text(" 分钟", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildVideoPage() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
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
            children: tabs.asMap().entries.map((e) {
              return Expanded(
                child: GestureDetector(
                  onTap: () => switchTab(e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: activeTab == e.key ? UIHelpers.primaryColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
                    ),
                    child: Text(
                      e.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: activeTab == e.key ? Colors.white : Colors.black87,
                        fontWeight: activeTab == e.key ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 16),
        if (activeTab != 0)
          Container(
            width: double.infinity,
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
                const Text("视频上传", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: chooseVideos,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UIHelpers.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("上传本地视频"),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: showOnlineVideoDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UIHelpers.successColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("上传在线视频"),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        //  视频列表区域（自适应渐变效果：参考 student study 的渐变逻辑）
        Expanded(
          child: isLoading
              ? const Center(child: CircularProgressIndicator())
              : videoList.isEmpty
              ? const Center(child: Text("暂无视频", style: TextStyle(color: Colors.black54)))
              : ShaderMask(
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
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      top: 12,  // 第一个视频卡片与上传卡片的间距
                      bottom: MediaQuery.of(context).size.height * 0.35,  // 底部留白，内容自然渐隐
                    ),
                  itemCount: videoList.length,
                  itemBuilder: (ctx, idx) {
                      final item = videoList[idx];
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
                              leading: const Text("📹", style: TextStyle(fontSize: 16)),
                              title: Text(item["name"] ?? ""),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: UIHelpers.errorColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                                  border: Border.all(color: UIHelpers.errorColor.withValues(alpha: 0.4)),
                                ),
                                child: GestureDetector(
                                  onTap: () => deleteVideo(item),
                                  child: const Text("删除", style: TextStyle(color: UIHelpers.errorColor, fontSize: 13)),
                                ),
                              ),
                              onTap: () {
                                setState(() {
                                  openIndex = openIndex == idx ? -1 : idx;
                                });
                              },
                            ),
                            if (openIndex == idx)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: CommonVideoPlayer(
                                videoUrl: item["url"] ?? '',
                                videoType: item["isOnline"] == true ? 2 : 1, // 🔥 传递videoType参数
                                autoPlay: true,
                                onVideoClosed: () {
                                  setState(() {
                                    openIndex = -1;
                                  });
                                },
                                // 🔥 新增：播放完成时自动收起卡片
                                onEnd: () {
                                  setState(() {
                                    openIndex = -1;
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),

      ],
    );
  }

  Widget _buildProgressPage() {
    // 添加方法：获取当前是周几（0=周一, 6=周日）
    int getCurrentWeekDayIndex() {
      final now = DateTime.now();
      return now.weekday - 1; // Dart中weekday: 1=Monday, 7=Sunday
    }
    
    final currentDayIndex = getCurrentWeekDayIndex();

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: TextEditingController(text: searchKey),
                onChanged: (v) => searchKey = v,
                decoration: InputDecoration(
                  hintText: "输入用户/手机号搜索",
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.85),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: searchProgress,
              style: ElevatedButton.styleFrom(
                backgroundColor: UIHelpers.primaryColor,
                foregroundColor: Colors.white,
              ),
              child: const Text("搜索"),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: progressLoading
              ? const Center(child: CircularProgressIndicator())
              : userProgressList.isEmpty
              ? const Center(child: Text("暂无用户数据", style: TextStyle(color: Colors.black54)))
              : ShaderMask(
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
                  child: ListView.builder(
                    padding: EdgeInsets.only(
                      top: 12,  // 第一个用户卡片与搜索框的间距
                      bottom: MediaQuery.of(context).size.height * 0.35,  // 底部留白，内容自然渐隐
                    ),
                    itemCount: userProgressList.length,
                    itemBuilder: (ctx, userIdx) {
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
                        child: ExpansionTile(
                          title: Text("${user['name']} | ${user['phone']}"),
                          onExpansionChanged: (v) => toggleUserWeek(userIdx),
                          children: () {
                            List<Widget> weekTiles = [];
                            // 只显示本周的数据：从周一开始到当前日期
                            for (int weekIdx = 0; weekIdx <= currentDayIndex && weekIdx < weekList.length; weekIdx++) {
                              final weekData = user['weekData'];
                              if (weekData is! List || weekIdx >= weekData.length) {
                                continue;
                              }
                              weekTiles.add(
                                ExpansionTile(
                                  title: Text(weekList[weekIdx]),
                                  children: [
                                    _buildSubjectProgress("语文", user, weekIdx, "yw"),
                                    _buildSubjectProgress("数学", user, weekIdx, "sx"),
                                    _buildSubjectProgress("英语", user, weekIdx, "en"),
                                    _buildSubjectProgress("其他", user, weekIdx, "ot"),
                                  ],
                                )
                              );
                            }
                            // 如果还没有到周末，显示剩余天数的占位符
                            if (currentDayIndex < 6) {
                              for (int futureIdx = currentDayIndex + 1; futureIdx < weekList.length; futureIdx++) {
                                weekTiles.add(
                                  ExpansionTile(
                                    title: Text(weekList[futureIdx]),
                                    subtitle: const Text("尚未开始", style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                                    children: [],
                                  )
                                );
                              }
                            }
                            return weekTiles;
                          }(),
                        ),
                      );
                    },
                  ),
                ),
        ),

      ],
    );
  }

  Widget _buildSubjectProgress(String name, dynamic user, int weekIdx, String key) {
    final weekData = user['weekData'];
    if (weekData is! List || weekIdx >= weekData.length) {
      return const SizedBox.shrink();
    }

    final weekItem = weekData[weekIdx] ?? {};
    final nowValue = weekItem[key];
    final targetValue = weekItem['${key}Target'];

    final now = nowValue is num ? nowValue.toInt() : (int.tryParse(nowValue?.toString() ?? '0') ?? 0);
    final target = targetValue is num ? targetValue.toInt() : (int.tryParse(targetValue?.toString() ?? '0') ?? 0);

    final p = target <= 0 ? 0.0 : now / target;
    debugPrint('📊 [$name] 已学=$now, 目标=$target, 进度=${(p * 100).toStringAsFixed(1)}%');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text("$name：已学 $now 分钟 / 要求 $target 分钟"),
          const SizedBox(height: 6),
          LinearProgressIndicator(value: p.clamp(0, 1)),
        ],
      ),
    );
  }

  Future<void> startBatchUpload() async {
    if (batchList.isEmpty) return;

    setState(() {
      uploading = true;
      uploadingIndex = 0;
      uploadingTotal = batchList.length;
    });

    int successCount = 0;

    for (int i = 0; i < batchList.length; i++) {
      if (!mounted) return;

      final video = batchList[i];
      final uploadId = 'study_video_${DateTime.now().millisecondsSinceEpoch}_$i';
      final fileName = video['name'] ?? '视频';

      setState(() {
        uploadingName = fileName;
        uploadingIndex = i + 1;
        uploadProgress = 0;
      });

      try {
        UploadProgressManager.startUpload(uploadId, fileName);
        debugPrint('📤 开始上传视频: $fileName');
        if (mounted) {
          showUploadProgress(context, uploadId);
        }

        final result = await UploadProgressManager.uploadFileWithProgress(
          url: "$baseUrl/api/video",
          filePath: video['path'],
          fieldName: 'file',
          uploadId: uploadId,
          fields: {
            'action': 'write',
            'subject': subjectMap[tabs[activeTab]] ?? '',
            'name': fileName,
          },
          onProgress: (progress) {
            setState(() {
              uploadProgress = progress * 100;
            });
            UploadProgressManager.updateProgress(uploadId, progress);
          },
        );

        bool uploadSuccess = false;
        String errorMsg = '上传失败';

        if (result['success'] == true) {
          final responseData = result['data'];
          if (responseData is Map<String, dynamic>) {
            if (responseData['success'] == true) {
              uploadSuccess = true;
            } else {
              errorMsg = responseData['message'] ?? '服务器返回上传失败';
            }
          }
        } else {
          errorMsg = result['error'] ?? '上传失败';
        }

        if (uploadSuccess) {
          UploadProgressManager.uploadSuccess(uploadId);
          successCount++;
        } else {
          UploadProgressManager.uploadFailed(uploadId, errorMsg);
          if (mounted) {
            ToastUtil.show(context, '$fileName 上传失败: $errorMsg');
          }
        }
      } catch (e) {
        final errorMsg = '上传异常: $e';
        UploadProgressManager.uploadFailed(uploadId, errorMsg);
        if (mounted) {
          ToastUtil.show(context, '$fileName $errorMsg');
        }
      } finally {
        // 确保每个视频上传结束后关闭进度对话框
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
      await Future.delayed(const Duration(milliseconds: 500));
    }

    if (mounted) {
      setState(() {
        uploading = false;
        showBatchPopup = false;
        batchList.clear();
      });

      if (successCount == uploadingTotal) {
        ToastUtil.show(context, '批量上传完成');
      } else if (successCount > 0) {
        ToastUtil.show(context, '批量上传完成，$successCount/$uploadingTotal 个视频上传成功');
      } else {
        ToastUtil.show(context, '批量上传失败');
      }
      loadVideoList();
    }
  }

  Widget _buildBatchUploadDialog() {
    return Stack(
      children: [
        ModalBarrier(color: Colors.black54, dismissible: !uploading),
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "批量上传视频",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "共 ${batchList.length} 个视频",
                    style: const TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  if (uploading)
                    Column(
                      children: [
                        Text(
                          "正在上传：$uploadingName",
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "进度：$uploadingIndex / $uploadingTotal",
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: uploadingTotal > 0 ? uploadingIndex / uploadingTotal : 0,
                          backgroundColor: Colors.grey[200],
                          valueColor: const AlwaysStoppedAnimation<Color>(UIHelpers.primaryColor),
                        ),
                      ],
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        shrinkWrap: true,
                        physics: const ClampingScrollPhysics(),
                        itemCount: batchList.length,
                        itemBuilder: (ctx, idx) {
                          final video = batchList[idx];
                          final isEditing = video['editing'] == true;

                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  const Icon(Icons.video_library, color: Colors.blue, size: 32),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: isEditing
                                        ? TextField(
                                      controller: TextEditingController(text: video['name']),
                                      autofocus: true,
                                      onSubmitted: (value) {
                                        setState(() {
                                          batchList[idx]['name'] = value.trim();
                                          batchList[idx]['editing'] = false;
                                        });
                                      },
                                      decoration: const InputDecoration(
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                    )
                                        : Text(
                                      video['name'],
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(isEditing ? Icons.check : Icons.edit, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        if (isEditing) {
                                          batchList[idx]['name'] = batchList[idx]['name'].toString().trim();
                                          batchList[idx]['editing'] = false;
                                        } else {
                                          batchList[idx]['editing'] = true;
                                          currentIndex = idx;
                                          currentVideoName = batchList[idx]['name'].toString();
                                        }
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (!uploading)
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                showBatchPopup = false;
                                batchList.clear();
                              });
                            },
                            child: const Text("取消"),
                          ),
                        ),
                      if (!uploading) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: uploading ? null : () {
                            for (int i = 0; i < batchList.length; i++) {
                              if (batchList[i]['editing'] == true) {
                                if (i == currentIndex) {
                                  batchList[i]['name'] = currentVideoName.trim();
                                }
                                batchList[i]['editing'] = false;
                              }
                            }
                            startBatchUpload();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: UIHelpers.primaryColor,
                            foregroundColor: Colors.white,
                          ),
                          child: Text(
                            uploading ? "上传中..." : "开始上传",
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOnlineVideoDialog() {
    return GestureDetector(
      onTap: () {
        setState(() {
          showOnlineVideoPopup = false;
        });
      },
      child: Stack(
        children: [
          ModalBarrier(color: Colors.black54, dismissible: true),
          Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "上传在线视频",
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    TextField(
                      onChanged: (v) => setState(() => onlineVideoUrl = v),
                      decoration: const InputDecoration(
                        labelText: "视频链接",
                        border: OutlineInputBorder(),
                        hintText: "请输入视频直链地址（如：https://example.com/video.mp4）",
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      onChanged: (v) => setState(() => onlineVideoName = v),
                      decoration: const InputDecoration(
                        labelText: "视频名称",
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setState(() {
                                showOnlineVideoPopup = false;
                              });
                            },
                            child: const Text("取消"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: onlineVideoUrl.isEmpty || onlineVideoName.isEmpty
                                ? null
                                : uploadOnlineVideo,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: UIHelpers.successColor,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text("上传"),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> uploadOnlineVideo() async {
    if (!mounted) return;
    
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/video'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'write',
          'subject': subjectMap[tabs[activeTab]],
          'name': onlineVideoName.trim(),
          'url': onlineVideoUrl.trim(),
          'isOnline': true,
        }),
      );

      final data = jsonDecode(resp.body);
      if (data['success'] == true) {
        if (mounted) ToastUtil.show(context, "上传成功");
        if (mounted) {
          setState(() {
            showOnlineVideoPopup = false;
            onlineVideoUrl = "";
            onlineVideoName = "";
          });
          loadVideoList();
        }
      } else {
        if (mounted) ToastUtil.show(context, "上传失败");
      }
    } catch (e) {
      if (mounted) ToastUtil.show(context, "上传异常");
    }
  }
}