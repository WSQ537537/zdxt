import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

/// 导航栏背景管理器
/// 职责：
/// 1. 每次冷启动清空旧缓存，默认显示蓝白渐变
/// 2. 异步拉取后端最新背景图
/// 3. 拉取成功则动画切换，失败保持默认渐变
/// 4. 不使用旧缓存，确保显示最新或默认
class NavBackgroundManager extends StatefulWidget {
  final Widget child;

  const NavBackgroundManager({super.key, required this.child});

  @override
  State<NavBackgroundManager> createState() => _NavBackgroundManagerState();
}

class _NavBackgroundManagerState extends State<NavBackgroundManager>
    with SingleTickerProviderStateMixin {
  // 默认渐变背景色
  static const LinearGradient _defaultGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFe0f7fa), Color(0xFF1e88e5)],
  );

  // 背景图状态
  File? _bgImage;
  bool _isLoading = true;

  // 动画控制器
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _loadBackground();
  }

  /// 加载背景图
  /// 策略：冷启动清空旧缓存，默认显示渐变，异步拉取新图
  Future<void> _loadBackground() async {
    final prefs = await SharedPreferences.getInstance();
    const cacheKey = 'nav_bg_cached';
    final cachePath = prefs.getString('nav_bg_path');

    // 第1步：清空旧缓存（删除文件+清除标记）
    if (cachePath != null) {
      try {
        final oldFile = File(cachePath);
        if (await oldFile.exists()) {
          await oldFile.delete();
        }
      } catch (e) {
        debugPrint('删除旧缓存失败: $e');
      }
    }
    await prefs.remove(cacheKey);
    await prefs.remove('nav_bg_path');

    // 第2步：立即显示默认渐变背景（不使用旧缓存）
    setState(() => _isLoading = false);

    // 第3步：异步下载最新背景图
    await _downloadBackground(prefs, cacheKey);
  }

  /// 下载背景图
  Future<void> _downloadBackground(
    SharedPreferences prefs,
    String cacheKey,
  ) async {
    try {
      final response = await http.get(
        Uri.parse('${Config.baseUrl}/bg/background.png'),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        // 保存到应用缓存目录
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/nav_background.png');
        await file.writeAsBytes(response.bodyBytes);

        // 标记已缓存
        await prefs.setBool(cacheKey, true);
        await prefs.setString('nav_bg_path', file.path);

        // 显示新背景图（淡入动画）
        _showBackgroundImage(file);
      }
      // 后端无图或下载失败：保持默认渐变，静默处理
    } catch (e) {
      debugPrint('背景图下载失败（保持默认渐变）: $e');
      // 保持默认渐变背景
    }
  }

  /// 显示背景图（淡入动画）
  void _showBackgroundImage(File file) {
    if (!mounted) return;

    setState(() {
      _bgImage = file;
    });

    // 延迟启动淡入动画
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _animationController.forward();
      }
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: _defaultGradient),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 第1层：新背景图（淡入动画，在最底层）
          if (_bgImage != null)
            AnimatedBuilder(
              animation: _fadeAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: child,
                );
              },
              child: Image.file(
                _bgImage!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            ),

          // 第2层：页面内容（始终在最上层）
          widget.child,

          // 第3层：加载指示器（仅在初始加载时显示）
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}
