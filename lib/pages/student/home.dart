import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:zdxtapp/pages/public/aichat.dart';
import 'exam.dart';
import 'study.dart';
import 'package:zdxtapp/pages/public/notice.dart';
import 'mine.dart';
import 'package:zdxtapp/widgets/nav_background.dart';
import 'package:zdxtapp/widgets/liquid_glass_slider.dart';

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> with SingleTickerProviderStateMixin {
  int currentIndex = 0;

  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  bool _isPageOut = false;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );
    _animationController.forward();
  }

  void switchTab(int index) {
    setState(() {
      _isPageOut = true;
    });
    Future.delayed(const Duration(milliseconds: 180), () {
      setState(() {
        currentIndex = index;
        _isPageOut = false;
      });
      _animationController.reset();
      _animationController.forward();
    });
  }

  Widget _buildPage() {
    switch (currentIndex) {
      case 0:
        return const ExamPage();
      case 1:
        return const StudyPage();
      case 2:
        return const NoticePage();
      case 3:
        return const MinePage();
      default:
        return const SizedBox();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: NavBackgroundManager(
        child: Stack(
          children: [
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 0),
                child: AnimatedBuilder(
                  animation: _scaleAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _isPageOut ? 0.8 : _scaleAnimation.value,
                      child: Opacity(
                        opacity: _isPageOut ? 0 : _scaleAnimation.value,
                        child: _buildPage(),
                      ),
                    );
                  },
                ),
              ),
            ),

            // 悬浮底部导航栏 — 双层玻璃结构：
            // ① 外层：磨砂液态玻璃长圆卡片（BackdropFilter 模糊 + 半透明渐变，稳定可见）
            // ② 内层：简约玻璃指示器（透明底 + 柔和高光 + 边缘描边）
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 4,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: Container(
                      height: 52,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white.withValues(alpha: 0.22),
                            Colors.white.withValues(alpha: 0.10),
                          ],
                          stops: const [0.0, 1.0],
                        ),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.28),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final sliderWidth = constraints.maxWidth * 0.15;
                          final tabWidth = (constraints.maxWidth - 52) / 4;
                          final positions = [
                            tabWidth * 0.5 - sliderWidth * 0.5,
                            tabWidth * 1.5 - sliderWidth * 0.5,
                            tabWidth * 2.5 + 52 - sliderWidth * 0.5,
                            tabWidth * 3.5 + 52 - sliderWidth * 0.5,
                          ];
                          return Stack(
                            children: [
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.easeOutCubic,
                                left: positions[currentIndex].clamp(0.0, constraints.maxWidth - sliderWidth),
                                top: 4,
                                child: LiquidGlassSlider(
                                  width: sliderWidth,
                                  height: 44,
                                  cornerRadius: 8,
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _tabItem("考试", 0),
                                  _tabItem("学习", 1),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => const AiChatPage(),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF007AFF),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Center(
                                        child: Text(
                                          "AI",
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  _tabItem("通知", 2),
                                  _tabItem("我的", 3),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tabItem(String title, int index) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => switchTab(index),
        child: Center(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              color: currentIndex == index ? const Color(0xFF2B7DFF) : Colors.white,
              fontWeight: currentIndex == index ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
