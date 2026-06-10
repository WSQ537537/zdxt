import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import 'package:zdxtapp/config.dart';
import 'package:zdxtapp/utils/toast.dart';
import 'package:zdxtapp/utils/ui_helpers.dart'; // 🔥 全局UI辅助工具

class SignManagePage extends StatefulWidget {
  const SignManagePage({super.key});

  @override
  State<SignManagePage> createState() => _SignManagePageState();
}

class _SignManagePageState extends State<SignManagePage> {
  final String baseUrl = Config.baseUrl;

  bool showCreateSign = false;
  bool showSignHistory = false;
  bool signRunning = false;
  bool showSignDetail = false;
  bool signEnded = false;

  String signType = 'code';
  String signCode = '';
  int countdown = 60;
  String subject = '语文';
  String title = '';
  int leftTime = 0;

  List signedList = [];
  List unsignedList = [];
  Map<String, dynamic> detail = {};
  String historySubject = '语文';
  List allHistoryList = [];

  Timer? pollTimer;

  List get filteredList => allHistoryList
      .where((item) => (item['subject'] ?? '其他') == historySubject)
      .toList();

  @override
  void initState() {
    super.initState();
    // 🔥 页面初始化时检查是否有运行中的签到
    openCreateSign();
  }

  @override
  void dispose() {
    stopPoll();
    super.dispose();
  }

  void closeAll() {
    setState(() {
      showSignHistory = false;
      signRunning = false;
      showSignDetail = false;
      signEnded = false;
    });
  }

  Future<void> openCreateSign() async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/sign'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'status'}),
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true && data['data'] != null) {
      final d = data['data'];
      if (d['running'] == true) {
        setState(() {
          signRunning = true;
          signEnded = false;
          leftTime = d['leftTime'];
          signedList = d['signedList'] ?? [];
          unsignedList = d['unsignedList'] ?? [];
          subject = d['subject'] ?? '语文';
          title = d['title'] ?? '';
        });
        startPoll();
        return;
      }
      if (d['running'] == false && d['closed'] == false) {
        setState(() {
          signRunning = true;
          signEnded = true;
          signedList = d['signedList'] ?? [];
          unsignedList = d['unsignedList'] ?? [];
          subject = d['subject'] ?? '';
          title = d['title'] ?? '';
        });
        return;
      }
    }
    // 🔥 不再设置 showCreateSign，直接重置表单
    setState(() {
      signCode = '';
      title = '';
      countdown = 60;
    });
  }

  Future<void> openSignHistory() async {
    closeAll();
    setState(() => showSignHistory = true);
    final res = await http.post(
      Uri.parse('$baseUrl/api/sign'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'history'}),
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      setState(() {
        allHistoryList = data['data'] ?? [];
      });
    }
  }

  Future<void> startSign() async {
    if (signType == 'code' && signCode.isEmpty) {
      ToastUtil.show(context, '请输入4位口令');
      return;
    }
    if (countdown <= 0) {
      ToastUtil.show(context, '倒计时必须大于0');
      return;
    }
    final res = await http.post(
      Uri.parse('$baseUrl/api/sign'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'create',
        'type': signType,
        'code': signCode,
        'time': countdown,
        'subject': subject,
        'title': title,
      }),
    );
    final data = jsonDecode(res.body);
    if (data['success'] == true) {
      closeAll();
      setState(() {
        signRunning = true;
        signEnded = false;
        leftTime = countdown;
      });
      startPoll();
    }
  }

  void startPoll() {
    stopPoll();
    pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final res = await http.post(
        Uri.parse('$baseUrl/api/sign'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'action': 'status'}),
      );
      final data = jsonDecode(res.body);
      if (data['success'] != true) {
        stopPoll();
        return;
      }
      final d = data['data'];
      setState(() {
        leftTime = d['leftTime'] ?? 0;
        signedList = d['signedList'] ?? [];
        unsignedList = d['unsignedList'] ?? [];
        if (d['running'] == false) {
          signEnded = true;
          stopPoll();
        }
      });
    });
  }

  void stopPoll() {
    if (pollTimer != null) {
      pollTimer!.cancel();
      pollTimer = null;
    }
  }

  Future<void> stopSign() async {
    await http.post(
      Uri.parse('$baseUrl/api/sign'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'stop'}),
    );
    stopPoll();
    setState(() => signEnded = true);
  }

  Future<void> closeSignPanel() async {
    await http.post(
      Uri.parse('$baseUrl/api/sign'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'action': 'close'}),
    );
    stopPoll();
    closeAll();
  }

  void openSignDetail(Map<String, dynamic> item) {
    debugPrint('🔍 打开签到详情: ${jsonEncode(item)}');
    setState(() {
      detail = item;
      showSignHistory = false;
      showSignDetail = true;
    });
    debugPrint('✅ detail 已设置: signedList=${item['signedList']?.length ?? 0}, unsignedList=${item['unsignedList']?.length ?? 0}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1890FF), Color(0xFF096DD9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // 顶部导航
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(UIHelpers.radiusRound),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                        ),
                        child: const Text('返回', style: TextStyle(color: Colors.white, fontSize: 16)),
                      ),
                    ),
                    const Text('签到点名', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 60),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: _buildContent(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    // 🔥 优先检查详情面板（最高优先级）
    if (showSignDetail) {
      // 🔥 详情面板，也显示分栏卡片（历史记录激活）
      return Column(
        children: [
          const SizedBox(height: 20),
          // 🔥 左右分栏卡片（历史记录激活）
          Row(
            children: [
              Expanded(
                child: _buildModeCard(
                  title: '现场点名',
                  subtitle: '发起签到',
                  icon: Icons.qr_code_scanner,
                  isActive: false,
                  onTap: () {
                    setState(() {
                      showSignDetail = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildModeCard(
                  title: '历史签到',
                  subtitle: '记录查看',
                  icon: Icons.history,
                  isActive: true,
                  onTap: () {
                    // 已经在历史记录模式，无需操作
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildDetailPanel(),
        ],
      );
    }
    
    // 🔥 其次检查运行中的签到
    if (signRunning) return _buildRunningPanel();
    
    // 🔥 然后检查历史记录
    if (showSignHistory) {
      // 🔥 历史记录面板，也显示分栏卡片（历史记录激活）
      return Column(
        children: [
          const SizedBox(height: 20),
          // 🔥 左右分栏卡片（历史记录激活）
          Row(
            children: [
              Expanded(
                child: _buildModeCard(
                  title: '现场点名',
                  subtitle: '发起签到',
                  icon: Icons.qr_code_scanner,
                  isActive: false,
                  onTap: () {
                    setState(() {
                      showSignHistory = false;
                    });
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildModeCard(
                  title: '历史签到',
                  subtitle: '记录查看',
                  icon: Icons.history,
                  isActive: true,
                  onTap: () {
                    // 已经在历史记录模式，无需操作
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildHistoryPanel(),
        ],
      );
    }
    
    // 🔥 默认显示现场点名面板
    return Column(
      children: [
        const SizedBox(height: 20),
        // 🔥 左右分栏卡片（现场点名激活）
        Row(
          children: [
            Expanded(
              child: _buildModeCard(
                title: '现场点名',
                subtitle: '发起签到',
                icon: Icons.qr_code_scanner,
                isActive: true,
                onTap: () {
                  // 已经在现场点名模式，无需操作
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildModeCard(
                title: '历史签到',
                subtitle: '记录查看',
                icon: Icons.history,
                isActive: false,
                onTap: openSignHistory,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _buildCreatePanel(),
      ],
    );
  }

  // 🔥 左右分栏模式卡片（修正边框选中逻辑）
  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? [
                    UIHelpers.primaryColor.withValues(alpha: 0.9),
                    UIHelpers.primaryColor.withValues(alpha: 0.7),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.15),
                    Colors.white.withValues(alpha: 0.08),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
          // 核心修改：选中(isActive) 显示高亮边框，未选中透明无边框
          border: Border.all(
            color: isActive ? Colors.white.withValues(alpha: 0.25) : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? UIHelpers.primaryColor.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.1),
              blurRadius: isActive ? 15 : 10,
              offset: Offset(0, isActive ? 6 : 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 32,
              color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: isActive ? Colors.white.withValues(alpha: 0.9) : Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatePanel() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 类型
          const Text('签到方式', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildChip('二维码', signType == 'qrcode', () => setState(() => signType = 'qrcode')),
              const SizedBox(width: 10),
              _buildChip('4位口令', signType == 'code', () => setState(() => signType = 'code')),
            ],
          ),
          const SizedBox(height: 16),
          const Text('科目', style: TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: ['语文', '数学', '英语', '其他']
                .map((s) => _buildChip(s, subject == s, () => setState(() => subject = s)))
                .toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => title = v,
            autofocus: false,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: '标题（选填）',
              hintStyle: TextStyle(color: Colors.grey.shade600),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 16),
          if (signType == 'code')
            TextField(
              onChanged: (v) => signCode = v,
              autofocus: false,
              maxLength: 4,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.black87, letterSpacing: 4),
              decoration: InputDecoration(
                hintText: '4位口令',
                hintStyle: TextStyle(color: Colors.grey.shade600),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          const SizedBox(height: 16),
          TextField(
            onChanged: (v) => countdown = int.tryParse(v) ?? 60,
            autofocus: false,
            keyboardType: TextInputType.number,
            style: const TextStyle(color: Colors.black87),
            decoration: InputDecoration(
              hintText: '倒计时（秒）',
              hintStyle: TextStyle(color: Colors.grey.shade600),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.9),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: startSign,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('开始签到', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: UIHelpers.warningColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              elevation: 2,
              minimumSize: const Size(double.infinity, 0),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(UIHelpers.radiusMedium)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunningPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('签到进行中', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              if (!signEnded)
                ElevatedButton.icon(
                  onPressed: stopSign,
                  icon: const Icon(Icons.stop, size: 18),
                  label: const Text('结束'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: UIHelpers.errorColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
              if (signEnded)
                ElevatedButton.icon(
                  onPressed: closeSignPanel,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('关闭'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
            ],
          ),
          const Divider(color: Colors.white24, height: 24),
          // 信息卡片
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.book, color: Colors.white.withValues(alpha: 0.9), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$subject 课堂签到',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (title.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.title, color: Colors.yellowAccent.withValues(alpha: 0.9), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(color: Colors.yellowAccent, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                // 🔥 倒计时（单独一行）
                if (!signEnded) ...[
                  Row(
                    children: [
                      Icon(Icons.timer, color: Colors.white.withValues(alpha: 0.9), size: 18),
                      const SizedBox(width: 8),
                      Text('倒计时：$leftTime 秒', style: const TextStyle(color: Colors.white, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                // 🔥 签到统计（单独一行）
                Row(
                  children: [
                    Icon(Icons.people, color: Colors.white.withValues(alpha: 0.9), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '已签：${signedList.length} / 未签：${unsignedList.length}', 
                        style: TextStyle(
                          color: signedList.length > unsignedList.length ? UIHelpers.successColor : UIHelpers.warningColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 已签到列表
          if (signedList.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.check_circle, color: UIHelpers.successColor, size: 20),
                const SizedBox(width: 8),
                Text('已签到 (${signedList.length})', 
                  style: TextStyle(color: UIHelpers.successColor, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: signedList.map((e) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: UIHelpers.successColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                      border: Border.all(color: UIHelpers.successColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(e.toString(), style: TextStyle(color: UIHelpers.successColor, fontSize: 13)),
                  )).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
          // 未签到列表
          if (unsignedList.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.cancel, color: UIHelpers.errorColor, size: 20),
                const SizedBox(width: 8),
                Text('未签到 (${unsignedList.length})', 
                  style: TextStyle(color: UIHelpers.errorColor, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: unsignedList.map((e) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: UIHelpers.errorColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                      border: Border.all(color: UIHelpers.errorColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(e.toString(), style: TextStyle(color: UIHelpers.errorColor, fontSize: 13)),
                  )).toList(),
                );
              },
            ),
          ],
          if (signedList.isEmpty && unsignedList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text('等待学生签到...', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryPanel() {
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0.08),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // 🔥 科目筛选
          Wrap(
            spacing: 8,
            children: ['语文', '数学', '英语', '其他']
                .map((s) => _buildChip(s, historySubject == s, () => setState(() => historySubject = s)))
                .toList(),
          ),
          const SizedBox(height: 16),
          if (filteredList.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text('暂无$historySubject签到记录', style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
              ),
            )
          else
            ...filteredList.map((item) {
              final signedCount = item['signedList']?.length ?? 0;
              final totalCount = item['allStudents']?.length ?? 0;
              final rate = totalCount > 0 ? (signedCount / totalCount * 100).round() : 0;
              
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item['title'] ?? '未命名签到',
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () => openSignDetail(item),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: UIHelpers.primaryColor.withValues(alpha: 0.2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: const Text('详情', style: TextStyle(fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text('${item['subject']}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                        const SizedBox(width: 12),
                        Text('$signedCount/$totalCount', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: rate >= 80 ? UIHelpers.successColor.withValues(alpha: 0.2) : (rate >= 60 ? UIHelpers.warningColor.withValues(alpha: 0.2) : UIHelpers.errorColor.withValues(alpha: 0.2)),
                            borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                          ),
                          child: Text(
                            '$rate%',
                            style: TextStyle(
                              color: rate >= 80 ? UIHelpers.successColor : (rate >= 60 ? UIHelpers.warningColor : UIHelpers.errorColor),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildDetailPanel() {
    // 🔥 防御性编程：检查 detail 是否为空
    if (detail.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
        ),
        child: const Center(
          child: Text('数据加载中...', style: TextStyle(color: Colors.grey, fontSize: 16)),
        ),
      );
    }

    final signedList = detail['signedList'] ?? [];
    final unsignedList = detail['unsignedList'] ?? [];
    
    // 🔥 修复：父级 Column 已经在 SingleChildScrollView 中，不需要再次嵌套滚动
    return Container(
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0.98),
            Colors.white.withValues(alpha: 0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(UIHelpers.radiusXLarge),
        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('签到详情', style: TextStyle(color: Color(0xff333333), fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                onPressed: () => setState(() {
                  showSignDetail = false;
                  showSignHistory = true;  // 🔥 关闭详情后回到历史记录界面
                }),
                icon: const Icon(Icons.close, color: Colors.grey),
              ),
            ],
          ),
          const Divider(color: Colors.grey, height: 24),
          // 🔥 直接显示内容，不需要 SingleChildScrollView（父级已提供滚动）
          // 已签到
          Row(
            children: [
              Icon(Icons.check_circle, color: UIHelpers.successColor, size: 20),
              const SizedBox(width: 8),
              Text('已签到 (${signedList.length})', 
                style: TextStyle(color: UIHelpers.successColor, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (signedList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('无人签到', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: signedList.map<Widget>((e) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: UIHelpers.successColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                  border: Border.all(color: UIHelpers.successColor.withValues(alpha: 0.3)),
                ),
                child: Text(e.toString(), style: TextStyle(color: UIHelpers.successColor, fontSize: 13)),
              )).toList(),
            ),
          const SizedBox(height: 24),
          // 未签到
          Row(
            children: [
              Icon(Icons.cancel, color: UIHelpers.errorColor, size: 20),
              const SizedBox(width: 8),
              Text('未签到 (${unsignedList.length})', 
                style: TextStyle(color: UIHelpers.errorColor, fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (unsignedList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text('全部已签到', style: TextStyle(color: UIHelpers.successColor.withValues(alpha: 0.7), fontSize: 14)),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: unsignedList.map<Widget>((e) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: UIHelpers.errorColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(UIHelpers.radiusSmall),
                  border: Border.all(color: UIHelpers.errorColor.withValues(alpha: 0.3)),
                ),
                child: Text(e.toString(), style: TextStyle(color: UIHelpers.errorColor, fontSize: 13)),
              )).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(String text, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? UIHelpers.warningColor : Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(UIHelpers.radiusMedium),
        ),
        child: Text(text, style: TextStyle(color: active ? Colors.white : Colors.white70)),
      ),
    );
  }
}