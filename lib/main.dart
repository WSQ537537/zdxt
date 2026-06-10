import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'config.dart';
import 'pages/login/login.dart';
import 'pages/login/help.dart';
import 'pages/admin/home.dart' as admin_home;
import 'pages/student/home.dart' as student_home;
import 'pages/parent/home.dart' as parent_home;
import 'pages/public/update.dart';
import 'pages/public/browser.dart';  // ✅ 新增：浏览器页面
import 'pages/public/bindemail.dart';  // ✅ 新增：邮箱绑定页面

// 全局状态（和你原版 globalData 完全一致）
WebSocket? globalWs;
bool isConnecting = false;
bool isConnected = false; // 新增：连接状态标识
int reconnectAttempts = 0; // 新增：重连尝试次数
// ✅ 优化：移除最大重连次数限制，改为智能重连
// const int maxReconnectAttempts = 10; // 删除这行
Timer? heartbeatTimer; // 新增：心跳定时器

// ✅ 新增：标记是否主动断开（避免主动断开后还重连）
bool isManualDisconnect = false;

// ✅ 新增：全局函数，用于登录时重置WebSocket连接
void resetWebSocketConnection() {
  debugPrint("🔄 重置WebSocket连接（账号切换）");
  isManualDisconnect = true; // 阻止自动重连
  
  if (globalWs != null) {
    try {
      // 发送断开通知
      if (globalWs!.readyState == WebSocket.open) {
        globalWs!.add(jsonEncode({
          "action": "disconnect",
          "reason": "account_switch"
        }));
      }
      globalWs!.close();
    } catch (e) {
      debugPrint("❌ 关闭旧连接失败: $e");
    }
  }
  
  globalWs = null;
  isConnected = false;
  isConnecting = false;
  reconnectAttempts = 0; // 重置重连计数
  _stopHeartbeatGlobal(); // 停止心跳
  
  debugPrint("✅ WebSocket连接已重置");
}

// 全局停止心跳函数
void _stopHeartbeatGlobal() {
  heartbeatTimer?.cancel();
  heartbeatTimer = null;
}

// ✅ 优化：心跳配置常量（与后端保持一致）
const int heartbeatInterval = 20; // Ping间隔：20秒
const int maxReconnectDelay = 60000; // 最大重连延迟：60秒

// 全局弹窗 key
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    debugPrint("Error: ${details.exception}");
  };

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  Widget? homePage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    checkLoginAndSetHome();
  }

  // 【关键】还原 uni-app onShow/onHide —— 页面显示/隐藏时管理 WS 连接
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    
    if (state == AppLifecycleState.resumed) {
      // ✅ 应用回到前台：重连 WebSocket
      debugPrint("📱 应用回到前台");
      
      // 重置主动断开标志，允许重连
      isManualDisconnect = false;
      
      // 如果未连接，重置重连计数并强制重连
      if (!isConnected) {
        debugPrint("🔄 检测到未连接状态，重置重连计数");
        reconnectAttempts = 0;
      }
      
      _delayedConnect(); // 延迟800ms连接
      
    } else if (state == AppLifecycleState.paused || 
               state == AppLifecycleState.detached ||
               state == AppLifecycleState.hidden) {
      // ✅ 应用退到后台/退出：立即断开 WebSocket
      debugPrint("📱 应用退到后台或退出，立即断开WebSocket连接");
      _closeWebSocket();
    }
  }

  Future<void> checkLoginAndSetHome() async {
    final sp = await SharedPreferences.getInstance();
    final userInfoStr = sp.getString("userInfo");

    if (userInfoStr == null || userInfoStr.isEmpty) {
      setState(() => homePage = const LoginPage());
      return;
    }

    try {
      final userInfo = jsonDecode(userInfoStr);
      final loginTime = userInfo["loginTime"] ?? 0;
      final role = userInfo["role"] ?? 2;
      final now = DateTime.now().millisecondsSinceEpoch;

      if (now - loginTime > 7 * 24 * 60 * 60 * 1000) {
        await sp.clear();
        setState(() => homePage = const LoginPage());
        return;
      }

      // 延迟800ms再连接 —— 完全和你原版 uni-app 一致
      _delayedConnect();

      if (role == 1) {
        homePage = const admin_home.Home();
      } else if (role == 2) {
        homePage = const student_home.Home();
      } else {
        homePage = const parent_home.Home();
      }
    } catch (e) {
      setState(() => homePage = const LoginPage());
    }
    setState(() {});
  }

  // 延迟 800ms 连接（原版 uni-app 逻辑）
  void _delayedConnect() async {
    final sp = await SharedPreferences.getInstance();
    final userInfoStr = sp.getString("userInfo");
    if (userInfoStr == null) return;

    final userInfo = jsonDecode(userInfoStr);
    
    // 检查账号是否变化，如果变化则强制重连
    if (isConnected && globalWs != null) {
      // 获取当前连接的账号信息（通过注册时的数据）
      // 简单判断：如果已连接但需要切换账号，则关闭旧连接
      debugPrint("⚠️ WebSocket 已连接，检查账号一致性...");
      // 由于无法直接获取当前连接的账号，我们采用保守策略：
      // 每次调用都先关闭旧连接，确保使用新账号
      debugPrint("🔄 检测到新的连接请求，关闭旧连接以确保账号正确");
      _closeWebSocket();
    }
    
    Future.delayed(const Duration(milliseconds: 800), () {
      _connectWebSocket(userInfo);
    });
  }

  // ================================
  // 🔥 优化版 WebSocket 连接（增强稳定性）
  // ================================
  void _connectWebSocket(Map userInfo) async {
    final account = userInfo["account"];
    final currentRole = userInfo["currentRole"] ?? userInfo["role"];

    debugPrint("🔗 开始连接 WS => $account (尝试第${reconnectAttempts + 1}次)");

    if (account == null || currentRole == null) {
      debugPrint("⚠️ 无账号信息，停止连接");
      return;
    }
    
    // 🔥 Bug修复：检查是否正在连接或已连接，避免并发重连
    if (isConnecting) {
      debugPrint("⚠️ 正在连接中，跳过重复请求");
      return;
    }
    
    if (isConnected && globalWs != null && globalWs!.readyState == WebSocket.open) {
      debugPrint("⚠️ 已存在有效连接，跳过重复连接");
      return;
    }

    _closeWebSocket();
    isConnecting = true;

    try {
      debugPrint("✅ 正在连接服务器：${Config.wsUrl}");
      final ws = await WebSocket.connect(Config.wsUrl);
      globalWs = ws;
      isConnecting = false;
      isConnected = true;
      reconnectAttempts = 0; // 重置重连计数

      debugPrint("✅ 连接成功！发送注册包...");

      // 发送注册（和你原版完全一样）
      final registerData = jsonEncode({
        "action": "register",
        "account": account,
        "type": currentRole,
      });
      ws.add(registerData);
      debugPrint("📤 发送注册：$registerData");

      // 启动心跳保活（每20秒发送一次ping）
      _startHeartbeat(ws);

      // 监听消息
      ws.listen(
        (data) {
          try {
            final msg = jsonDecode(data);
            
            // ✅ 处理服务器心跳 ping
            if (msg["type"] == "ping") {
              ws.add(jsonEncode({"type": "pong"}));
              debugPrint("🏓 收到服务器ping，回复pong");
              return;
            }
            
            final msgId = msg["id"] ?? msg["_id"];

            if (msg["type"] == "system" && msg["msg"] == "连接成功") {
              debugPrint("⏭️ 连接成功消息，不弹窗");
              return;
            }
            if (msgId == null) {
              debugPrint("⏭️ 无ID，不弹窗");
              return;
            }

            final title = msg["title"] ?? "通知";
            final content = msg["content"] ?? "您有新的通知";

            // 🔥 优化：用户点击"知道了"后才发送ACK，确保用户确实看到了消息
            // 全局弹窗
            showDialog(
              context: navigatorKey.currentContext!,
              barrierDismissible: false,
              builder: (ctx) => AlertDialog(
                title: Text(title),
                content: Text(content),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      // ✅ 用户点击"知道了"后才发送ACK
                      _sendAck(ws, msgId);
                    },
                    child: const Text("知道了"),
                  ),
                ],
              ),
            );
          } catch (e) {
            debugPrint("❌ 解析失败：$e");
          }
        },
        onDone: () {
          debugPrint("❌ 连接断开");
          globalWs = null;
          isConnected = false;
          isConnecting = false; // 🔥 Bug修复：重置连接标志
          _stopHeartbeat();
          
          // ✅ 如果是主动断开，不重连
          if (isManualDisconnect) {
            debugPrint("⚠️ 主动断开，不重连");
            isManualDisconnect = false; // 重置标志
            return;
          }
          
          // ✅ 智能重连：始终尝试，但间隔逐渐增大
          final delay = _calculateSmartDelay(reconnectAttempts);
          debugPrint("🔄 ${delay ~/ 1000}秒后尝试第${reconnectAttempts + 1}次重连...");
          Future.delayed(Duration(milliseconds: delay), () {
            reconnectAttempts++;
            _connectWebSocket(userInfo);
          });
        },
        onError: (err) {
          debugPrint("❌ WS 错误：$err");
          globalWs = null;
          isConnected = false;
          isConnecting = false; // 🔥 Bug修复：重置连接标志
          _stopHeartbeat();
          
          // ✅ 如果是主动断开，不重连
          if (isManualDisconnect) {
            debugPrint("⚠️ 主动断开，不重连");
            isManualDisconnect = false; // 重置标志
            return;
          }
          
          // ✅ 智能重连：始终尝试，但间隔逐渐增大
          final delay = _calculateSmartDelay(reconnectAttempts);
          debugPrint("🔄 ${delay ~/ 1000}秒后尝试第${reconnectAttempts + 1}次重连...");
          Future.delayed(Duration(milliseconds: delay), () {
            reconnectAttempts++;
            _connectWebSocket(userInfo);
          });
        },
      );
    } catch (e) {
      debugPrint("❌ 连接失败：$e");
      isConnecting = false; // 🔥 Bug修复：重置连接标志
      
      // ✅ 智能重连：始终尝试，但间隔逐渐增大
      final delay = _calculateSmartDelay(reconnectAttempts);
      debugPrint("🔄 ${delay ~/ 1000}秒后尝试第${reconnectAttempts + 1}次重连...");
      Future.delayed(Duration(milliseconds: delay), () {
        reconnectAttempts++;
        _connectWebSocket(userInfo);
      });
    }
  }

  // ✅ 智能重连延迟算法：1s, 2s, 4s, 8s, 16s, 30s, 60s, 60s...
  int _calculateSmartDelay(int attempts) {
    if (attempts < 5) {
      return 1000 * (1 << attempts);  // 指数增长：1s, 2s, 4s, 8s, 16s
    } else if (attempts < 10) {
      return 30000;  // 30秒
    } else {
      return 60000;  // 60秒（封顶）
    }
  }

  // 🔥 新增：发送ACK确认（带重试机制）
  void _sendAck(WebSocket ws, String msgId, {int retryCount = 0}) {
    const maxRetries = 3;
    
    try {
      if (ws.readyState == WebSocket.open) {
        ws.add(jsonEncode({
          "action": "ack",
          "msgId": msgId,
        }));
        debugPrint("✅ 发送ACK确认：$msgId");
      } else {
        debugPrint("⚠️ 连接已断开，跳过ACK发送");
        // 如果连接断开且未超过最大重试次数，延迟重试
        if (retryCount < maxRetries) {
          Future.delayed(Duration(seconds: 1), () {
            _sendAck(ws, msgId, retryCount: retryCount + 1);
          });
        }
      }
    } catch (ackErr) {
      debugPrint("❌ 发送ACK失败: $ackErr");
      // 如果发送失败且未超过最大重试次数，延迟重试
      if (retryCount < maxRetries) {
        Future.delayed(Duration(seconds: 1), () {
          _sendAck(ws, msgId, retryCount: retryCount + 1);
        });
      }
    }
  }

  // 启动心跳保活（优化版）
  void _startHeartbeat(WebSocket ws) {
    _stopHeartbeat(); // 先停止旧的
    
    heartbeatTimer = Timer.periodic(Duration(seconds: heartbeatInterval), (timer) {
      if (ws.readyState == WebSocket.open) {
        ws.add(jsonEncode({"type": "ping"}));
        debugPrint("🏓 发送心跳ping");
      } else {
        debugPrint("⚠️ WebSocket未打开，停止心跳");
        _stopHeartbeat();
      }
    });
  }

  // 停止心跳
  void _stopHeartbeat() {
    heartbeatTimer?.cancel();
    heartbeatTimer = null;
  }

  void _closeWebSocket() {
    // ✅ 标记为主动断开，阻止重连
    isManualDisconnect = true;
    
    _stopHeartbeat(); // ✅ 先停止心跳
    
    if (globalWs != null) {
      try {
        // ✅ 发送断开通知给后端
        if (globalWs!.readyState == WebSocket.open) {
          globalWs!.add(jsonEncode({
            "action": "disconnect",
            "reason": "app_background"
          }));
          debugPrint("📤 已发送断开通知给后端");
        }
        
        // 关闭连接
        globalWs!.close();
        debugPrint("✅ 旧连接已关闭");
      } catch (e) {
        debugPrint("❌ 关闭连接失败: $e");
      }
    }
    globalWs = null;
    isConnected = false;
    isConnecting = false;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '智答星途',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: homePage ?? const Scaffold(
              backgroundColor: Color(0xFF0F172A),
              body: Center(child: CircularProgressIndicator(color: Colors.blueAccent)),
            ),
      routes: {
        "/login": (context) => const LoginPage(),
        "/help": (context) => const HelpPage(type: 'forgot'),
        "/update": (context) => const UpdatePage(),
        "/public/browser": (context) => const BrowserPage(),  // ✅ 新增：浏览器页面路由
        "/bindemail": (context) => const BindEmailPage(),  // ✅ 新增：邮箱绑定页面路由
        "/admin/home": (context) => const admin_home.Home(),
        "/student/home": (context) => const student_home.Home(),
        "/parent/home": (context) => const parent_home.Home(),
      },
    );
  }
}