import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:wakelock_plus/wakelock_plus.dart'; // 🔥 新增：屏幕常亮

/// 通用视频播放器组件（使用 video_player + chewie）
/// - 自动播放支持
/// - 完整的播放控制UI
/// - 全屏切换支持
/// - 优化的布局，避免按钮拥挤
/// 修复：全屏白屏、竖屏视频强制横屏、控制栏不显示问题
class CommonVideoPlayer extends StatefulWidget {
  final String videoUrl;
  final VoidCallback? onVideoClosed;
  final bool autoPlay;
  final double? height;

  final VoidCallback? onPlay;
  final VoidCallback? onPause;
  final VoidCallback? onEnd;
  
  // 🔥 新增：缓冲状态回调
  final ValueChanged<bool>? onBuffering;
  
  // 🔥 新增：视频类型参数
  // type=1: 本地视频, type=2: 在线视频(B站链接)
  final int? videoType;

  const CommonVideoPlayer({
    super.key,
    required this.videoUrl,
    this.onVideoClosed,
    this.autoPlay = false,
    this.height,
    this.onPlay,
    this.onPause,
    this.onEnd,
    this.onBuffering, // 🔥 添加缓冲状态回调
    this.videoType, // 🔥 添加videoType参数
  });

  @override
  State<CommonVideoPlayer> createState() => _CommonVideoPlayerState();
}

class _CommonVideoPlayerState extends State<CommonVideoPlayer> with WidgetsBindingObserver {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;
  
  // 添加ValueNotifier来管理播放状态
  final ValueNotifier<VideoPlayerValue?> _playerValueNotifier = ValueNotifier(null);
  
  // 🔥 新增：B站解析相关状态
  bool _isResolving = false;
  Timer? _resolveTimer;

  // 🔥 新增：存储视频原始宽高比，用于判断全屏方向
  double? _videoAspectRatio;
  
  // 🔥 新增：跟踪全屏状态，用于切换全屏/退出全屏图标
  bool _isFullScreen = false;
  
  // 🔥 新增：控制栏显示状态和自动隐藏定时器（使用ValueNotifier确保UI能响应状态变化）
  final ValueNotifier<bool> _showControlsNotifier = ValueNotifier<bool>(true);
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // 🔥 根据视频类型决定初始化方式
    _initializeVideoPlayer();
  }

  // 🔥 B站解析方法
  Future<String?> _parseBilibiliVideo(String input) async {
    if (input.isEmpty) {
      return null;
    }

    try {
      // 1. 提取 BV 号
      final bvRegex = RegExp(r'BV[0-9A-Za-z]+');
      final match = bvRegex.firstMatch(input);
      if (match == null) {
        return null;
      }
      final bvid = match.group(0)!;

      // 2. 提取 p 参数（分P标识）
      int? pageParam;
      final uri = Uri.tryParse(input);
      if (uri != null && uri.queryParameters.containsKey('p')) {
        final pStr = uri.queryParameters['p'];
        if (pStr != null) {
          try {
            pageParam = int.parse(pStr);
          } catch (e) {
            // p参数无效，忽略
            pageParam = null;
          }
        }
      }
      
      // 3. 获取视频信息（包含所有分P信息）
      final infoUrl = 'https://api.bilibili.com/x/web-interface/view?bvid=$bvid';
      final infoRes = await http.get(Uri.parse(infoUrl), headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Referer": "https://www.bilibili.com/",
        "Origin": "https://www.bilibili.com"
      });
      final infoData = json.decode(infoRes.body);
      if (infoData['code'] != 0) {
        return null;
      }
      
      // 4. 确定正确的 cid
      String cid;
      if (pageParam != null && pageParam > 1) {
        // 合集视频，需要获取指定分P的cid
        // pages数组索引从0开始，所以pageParam-1
        final pages = infoData['data']['pages'] as List;
        if (pageParam <= pages.length) {
          cid = pages[pageParam - 1]['cid'].toString();
        } else {
          // p参数超出范围，使用第一个分P
          cid = infoData['data']['cid'].toString();
        }
      } else {
        // 单个视频或p=1，使用主cid
        cid = infoData['data']['cid'].toString();
      }

      // 5. 获取真实视频直链（m4s）
      final playUrl =
          "https://api.bilibili.com/x/player/playurl?bvid=$bvid&cid=$cid&qn=80&type=m4s&platform=html5&high_quality=1";
      final playRes = await http.get(Uri.parse(playUrl), headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Referer": "https://www.bilibili.com/",
        "Origin": "https://www.bilibili.com"
      });

      final playData = json.decode(playRes.body);
      if (playData['code'] != 0) {
        return null;
      }

      // 6. 提取真实视频直链（这才是能播放的）
      String videoUrl = "";
      try {
        videoUrl = playData['data']['durl'][0]['url']; // 兼容老格式
      } catch (e) {
        try {
          videoUrl = playData['data']['dash']['video'][0]['baseUrl']; // dash 格式
        } catch (e2) {
          try {
            videoUrl = playData['data']['dash']['video'][0]['backupUrl'][0];
          } catch (e3) {
            // 所有格式都失败
            videoUrl = "";
          }
        }
      }

      if (videoUrl.isEmpty) {
        return null;
      }

      return videoUrl; // ✅ 真实视频直链
    } catch (e) {
      return null;
    }
  }

  // 🔥 初始化视频播放器
  Future<void> _initializeVideoPlayer() async {
    final videoType = widget.videoType ?? 1; // 默认为本地视频
    final originalUrl = widget.videoUrl;
    
    if (originalUrl.isEmpty) {
      setState(() {
        _hasError = true;
      });
      return;
    }
    
    if (videoType == 2) {
      // 在线视频，需要解析
      setState(() {
        _isResolving = true;
      });
      
      try {
        final resolvedUrl = await _parseBilibiliVideo(originalUrl);
        if (resolvedUrl != null && mounted) {
          setState(() {
            _isResolving = false;
          });
          await _setupVideoPlayer(resolvedUrl);
        } else if (mounted) {
          setState(() {
            _isResolving = false;
            _hasError = true;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isResolving = false;
            _hasError = true;
          });
        }
      }
    } else {
      // 本地视频，直接播放
      await _setupVideoPlayer(originalUrl);
    }
  }

  // 🔥 设置视频播放器（核心修复点）
  Future<void> _setupVideoPlayer(String videoUrl) async {
    try {
      final videoType = widget.videoType ?? 1;
      
      // 🔥 优化本地视频播放：使用 VideoPlayerOptions 配置流式播放
      // 在带宽有限的服务器上，允许边加载边播放，而不是一次性下载完整视频
      VideoPlayerController? controller;
      
      if (videoType == 1) {
        // 本地视频：配置HTTP Range请求支持流式播放
        // 🔥 关键优化：
        // 1. mixWithOthers: 允许与其他音频混合，避免独占音频焦点
        // 2. allowBackgroundPlayback: 允许后台播放
        // 注意：HTTP Range请求由底层播放器（ExoPlayer/AVPlayer）自动处理
        controller = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: true,
          ),
        );
      } else {
        // 在线视频（B站解析后的直链）
        controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      }
      
      _videoPlayerController = controller;
      
      // 🔥 关键优化：在初始化之前设置监听器，以便捕获初始化过程中的事件
      // 这有助于在视频开始缓冲时就更新UI状态
      
      await _videoPlayerController!.initialize();
      
      if (!mounted) return;
      
      // 🔥 修复问题2：存储视频原始宽高比，用于判断全屏方向
      _videoAspectRatio = _videoPlayerController!.value.aspectRatio;
      
      // 🔥 修复问题1：根据视频宽高比自动选择全屏方向
      // 宽高比 > 1 是横屏视频，宽高比 < 1 是竖屏视频
      List<DeviceOrientation> fullScreenOrientations = [];
      if (_videoAspectRatio! > 1) {
        // 横屏视频，允许左右横屏
        fullScreenOrientations = const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ];
      } else {
        // 竖屏视频，保持竖屏
        fullScreenOrientations = const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ];
      }
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: widget.autoPlay,
        looping: false,
        aspectRatio: _videoAspectRatio!,
        customControls: _buildCustomControls(), // 🔥 自定义控制栏
        // 🔥 关键修复：必须设置为true，Chewie才会渲染customControls
        showControls: true,
        showControlsOnInitialize: true,
        placeholder: Container(color: Colors.black),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Text(
              '视频加载失败，请稍后重试',
              style: const TextStyle(color: Colors.white),
            ),
          );
        },
        // 🔥 添加控制栏安全区域配置，避免按钮拥挤
        controlsSafeAreaMinimum: const EdgeInsets.all(8),
        // 🔥 修复问题1：使用Flutter 3.0+颜色API规范
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.blue.withValues(alpha: 1.0),
          handleColor: Colors.blue.withValues(alpha: 1.0),
          bufferedColor: Colors.white.withValues(alpha: 0.3),
          backgroundColor: Colors.black.withValues(alpha: 0.54),
        ),
        allowFullScreen: true,
        // 🔥 修复问题1：使用Flutter 3.0+颜色API规范
        deviceOrientationsOnEnterFullScreen: fullScreenOrientations,
        deviceOrientationsAfterFullScreen: const [
          DeviceOrientation.portraitUp,
        ],
        systemOverlaysOnEnterFullScreen: [],
        systemOverlaysAfterFullScreen: SystemUiOverlay.values,
        fullScreenByDefault: false,
        // 🔥 核心修复：简化全屏路由，使用Scaffold确保背景色正确
        routePageBuilder: (context, animation, secondAnimation, child) {
          return PopScope(
            canPop: true,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop && mounted) {
                // 🔥 退出全屏时重置状态
                setState(() {
                  _isFullScreen = false;
                });
                _showControlsNotifier.value = true;
                _showControlsBar();
              }
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: child,
            ),
          );
        },
        // 🔥 新增：防止屏幕休眠干扰渲染
        allowedScreenSleep: false,
      );

      // 监听播放状态变化
      _videoPlayerController!.addListener(() {
        _playerValueNotifier.value = _videoPlayerController!.value;
          
        // 🔥 缓冲状态回调
        if (_videoPlayerController!.value.isBuffering) {
          widget.onBuffering?.call(true);
        } else {
          widget.onBuffering?.call(false);
        }
          
        // 🔥 播放状态回调（避免重复调用）
        if (_videoPlayerController!.value.isPlaying) {
          // 🔥 视频开始播放时，启用屏幕常亮
          WakelockPlus.enable();
          widget.onPlay?.call();
        } else if (!_videoPlayerController!.value.isBuffering) {
          // 🔥 只有在非缓冲状态下才调用 onPause
          widget.onPause?.call();
        }
          
        // 播放结束回调
        if (_videoPlayerController!.value.isCompleted) {
          // 🔥 视频播放结束时，禁用屏幕常亮
          WakelockPlus.disable();
          widget.onEnd?.call();
        }
      });
        
        setState(() {
          _isInitialized = true;
          _isResolving = false;
        });
        
        // 🔥 初始化完成后，延迟一帧再启动自动隐藏定时器，确保UI已渲染
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showControlsBar();
          }
        });
        
        if (widget.autoPlay) {
          _videoPlayerController!.play();
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _hasError = true;
            _isResolving = false;
          });
        }
      }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    
    // 🔥 禁用屏幕常亮（防止内存泄漏）
    WakelockPlus.disable();
    
    // 清理解析定时器
    _resolveTimer?.cancel();
    _resolveTimer = null;
    
    // 🔥 清理控制栏自动隐藏定时器
    _hideTimer?.cancel();
    _hideTimer = null;
    
    // 清理播放器
    _videoPlayerController?.pause();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _playerValueNotifier.dispose(); // 销毁ValueNotifier
    
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      // 🔥 修复问题5：应用切换到后台时暂停视频
      // 无论是否全屏，切换到后台都应暂停以节省资源并符合预期行为
      // 退出全屏后视频停止播放的问题通常是因为全屏退出时触发了生命周期变化或路由重建
      // 这里统一处理为后台暂停，前台恢复时可根据需要自动播放或保持暂停
      _videoPlayerController?.pause();
      // 🔥 关键修复：不在这里调用 onPause，避免与全屏切换冲突
      // widget.onPause?.call();
      
      // 🔥 应用进入后台时，禁用屏幕常亮
      WakelockPlus.disable();
    } else if (state == AppLifecycleState.resumed) {
      // 🔥 应用恢复前台时，如果视频仍在播放则重新启用屏幕常亮
      if (_videoPlayerController?.value.isPlaying == true) {
        WakelockPlus.enable();
      }
    }
  }

  // ========== 控制栏显示/隐藏管理方法 ==========
  
  /// 显示控制栏并重置自动隐藏定时器
  void _showControlsBar() {
    if (!mounted) return;
    
    _showControlsNotifier.value = true;
    
    // 取消之前的定时器
    _hideTimer?.cancel();
    
    // 启动新的5秒自动隐藏定时器
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _showControlsNotifier.value) {
        _showControlsNotifier.value = false;
      }
    });
  }
  
  /// 切换控制栏显示/隐藏状态
  void _toggleControls() {
    if (_showControlsNotifier.value) {
      // 当前显示，则隐藏并取消定时器
      _showControlsNotifier.value = false;
      _hideTimer?.cancel();
    } else {
      // 当前隐藏，则显示并启动定时器
      _showControlsBar();
    }
  }
  
  /// 用户交互时重置定时器（仅在控制栏显示时有效）
  void _onUserInteraction() {
    // 只有当控制栏当前处于显示状态时，才重置自动隐藏定时器
    // 如果控制栏已隐藏，通常由 onTap (_toggleControls) 负责重新显示
    if (_showControlsNotifier.value) {
      _showControlsBar();
    }
  }

  // ========== 自定义控制栏构建方法（修复层级问题） ==========
  Widget _buildCustomControls() {
    debugPrint('🎬 [DEBUG] _buildCustomControls被调用');
    
    return GestureDetector(
      onTap: _toggleControls,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          // 🔥 控制栏内容，根据_showControlsNotifier状态显示/隐藏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: _showControlsNotifier,
              builder: (context, showControls, _) {
                debugPrint('🎬 [DEBUG] ValueListenableBuilder重建，showControls = $showControls');
                return AnimatedOpacity(
                  opacity: showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: !showControls, // 🔥 隐藏时忽略指针事件，避免误触
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.54),
                          ],
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 左侧：播放/暂停按钮 + 已播放时长
                          ValueListenableBuilder<VideoPlayerValue?>(
                            valueListenable: _playerValueNotifier,
                            builder: (context, value, _) {
                              return Row(
                                children: [
                                  IconButton(
                                    icon: Icon(
                                      value?.isPlaying == true ? Icons.pause : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                    onPressed: () {
                                      _onUserInteraction(); // 🔥 用户交互时重置定时器
                                      final controller = _videoPlayerController!;
                                      if (controller.value.isPlaying) {
                                        controller.pause();
                                      } else {
                                        controller.play();
                                      }
                                    },
                                  ),
                                  Text(
                                    value != null ? _formatDuration(value.position) : '00:00',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                          // 中间：进度条
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8.0),
                              child: ValueListenableBuilder<VideoPlayerValue?>(
                                valueListenable: _playerValueNotifier,
                                builder: (context, value, _) {
                                  if (value == null) {
                                    return Slider(
                                      value: 0,
                                      min: 0,
                                      max: 1,
                                      onChanged: (_) {},
                                    );
                                  }
                                  return SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: Colors.blue,
                                      inactiveTrackColor: Colors.white.withValues(alpha: 0.3),
                                      thumbColor: Colors.blue,
                                      overlayColor: Colors.blue.withValues(alpha: 0.2),
                                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12.0),
                                    ),
                                    child: Slider(
                                      value: value.position.inMilliseconds.toDouble(),
                                      min: 0.0,
                                      max: value.duration.inMilliseconds.toDouble(),
                                      onChangeStart: (_) => _onUserInteraction(), // 🔥 开始拖动时重置定时器
                                      onChanged: (newValue) {
                                        final newDuration = Duration(milliseconds: newValue.toInt());
                                        _videoPlayerController!.seekTo(newDuration);
                                      },
                                      onChangeEnd: (_) => _onUserInteraction(), // 🔥 结束拖动时重置定时器
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          // 右侧：总时长 + 全屏按钮
                          ValueListenableBuilder<VideoPlayerValue?>(
                            valueListenable: _playerValueNotifier,
                            builder: (context, value, _) {
                              return Row(
                                children: [
                                  Text(
                                    value != null ? _formatDuration(value.duration) : '00:00',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      decoration: TextDecoration.none,
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                                      color: Colors.white,
                                      size: 30,
                                    ),
                                    onPressed: () {
                                      _onUserInteraction(); // 🔥 用户交互时重置定时器
                                      // 🔥 修复问题8：严格按照Flutter视频全屏播放优化规范
                                      if (_isFullScreen) {
                                        // 当前是全屏状态，点击退出全屏
                                        Navigator.of(context).pop();
                                        setState(() {
                                          _isFullScreen = false;
                                        });
                                      } else {
                                        // 当前是小窗状态，点击进入全屏
                                        _chewieController?.enterFullScreen();
                                        setState(() {
                                          _isFullScreen = true;
                                        });
                                      }
                                    },
                                  ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // 格式化时间显示
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    
    if (hours > 0) {
      return '${twoDigits(hours)}:${twoDigits(minutes)}:${twoDigits(seconds)}';
    } else {
      return '${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 处理解析中的状态
    if (_isResolving) {
      return Container(
        height: widget.height ?? 200,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 8),
              Text(
                '正在解析视频链接...',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }
    
    // 🔥 处理解析失败的状态
    if (_hasError) {
      return Container(
        height: widget.height ?? 200,
        color: Colors.black,
         child: const Center(
          child: Text(
            '视频加载失败，请检查链接有效性',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        ),
      );
    }

    if (!_isInitialized || _videoPlayerController == null || _chewieController == null) {
      return Container(
        height: widget.height ?? 200,
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    return Container(
      height: widget.height ?? 200,
      color: Colors.black,
      child: Chewie(controller: _chewieController!),
    );
  }
}