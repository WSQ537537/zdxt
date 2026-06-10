import 'dart:async'; // 🔥 异步操作支持（unawaited）
import 'dart:convert'; // 🔥 JSON 编解码
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart'; // 🔥 使用增强版WebView
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 🔥 持久化存储
// import 'package:media_scanner/media_scanner.dart'; // 🔥 媒体扫描支持（已移除，存在跨盘符编译问题）
// import 'package:open_file/open_file.dart'; // 🔥 打开文件（预留）
// import 'package:url_launcher/url_launcher.dart'; // 🔥 打开目录（已移除，避免 FileUriExposedException）

class BrowserPage extends StatefulWidget {
  const BrowserPage({super.key});

  @override
  State<BrowserPage> createState() => _BrowserPageState();
}

class _BrowserPageState extends State<BrowserPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _currentTabIndex = 0; // 当前选中的标签索引
  bool _isLoading = false; // 加载状态
  
  // 🔥 下载状态管理
  String? _downloadingFilename; // 当前下载的文件名
  double _downloadProgress = 0.0; // 下载进度（0.0-1.0）
  bool _isDownloading = false; // 是否正在下载
  
  // 🔥 下载历史记录
  List<Map<String, dynamic>> _downloadHistory = []; // 下载记录列表

  @override
  void initState() {
    super.initState();
    
    // 🔥 设置状态栏样式
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    
    // 🔥 移除自动权限请求，让WebView在处理文件上传时自动触发系统权限请求
    
    // 初始化Tab控制器
    _tabController = TabController(length: 2, vsync: this);
    
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentTabIndex = _tabController.index;
        });
        
        // 🔥 切换标签时清除所有 SnackBar
        ScaffoldMessenger.of(context).clearSnackBars();
      }
    });
    
    // 🔥 加载下载历史记录
    _loadDownloadHistory();
  }

  // 🔥 从本地存储加载下载历史
  Future<void> _loadDownloadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final historyJson = prefs.getString('download_history');
      
      if (historyJson != null && historyJson.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(historyJson);
        setState(() {
          _downloadHistory = decoded.map((item) {
            // 将时间字符串转换回 DateTime 对象
            return <String, dynamic>{
              ...item as Map<String, dynamic>,
              'time': DateTime.parse(item['time'] as String),
            };
          }).toList();
        });
        debugPrint('📚 加载了 ${_downloadHistory.length} 条下载记录');
      }
    } catch (e) {
      debugPrint('⚠️ 加载下载历史失败: $e');
    }
  }

  // 🔥 保存下载历史到本地存储
  Future<void> _saveDownloadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // 将 DateTime 转换为字符串以便存储
      final historyToSave = _downloadHistory.map((item) {
        return {
          ...item,
          'time': item['time'].toIso8601String(),
        };
      }).toList();
      
      final historyJson = jsonEncode(historyToSave);
      await prefs.setString('download_history', historyJson);
      debugPrint('💾 已保存 ${_downloadHistory.length} 条下载记录');
    } catch (e) {
      debugPrint('⚠️ 保存下载历史失败: $e');
    }
  }

  @override
  void dispose() {
    // 🔥 清除所有 SnackBar（下载完成提示、错误提示等）
    ScaffoldMessenger.of(context).clearSnackBars();
    _tabController.dispose();
    super.dispose();
  }

  // 🔥 权限检查和引导功能已移至Android原生层处理
  // AndroidManifest.xml中已声明所需权限，WebView会自动处理文件上传时的权限请求
  // 如需Flutter层权限管理，可后续启用permission_handler库

  // 🔥 处理文件下载
  Future<void> _handleDownload(String url, String? suggestedFilename) async {
    if (_isDownloading) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已有文件正在下载，请稍候')),
      );
      return;
    }

    // 🔥 请求存储权限（Android 需要）
    debugPrint('🔍 检查存储权限...');
    final storageStatus = await Permission.storage.request();
    final photosStatus = await Permission.photos.request();
    
    if (!storageStatus.isGranted && !photosStatus.isGranted && !photosStatus.isLimited) {
      debugPrint('❌ 存储权限被拒绝');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('需要存储权限才能下载文件\n请在设置中手动开启权限'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: '去设置',
              textColor: Colors.white,
              onPressed: () {
                openAppSettings();
              },
            ),
          ),
        );
      }
      return;
    }
    debugPrint('✅ 存储权限已授予');

    // 🔥 智能提取文件名并判断文件类型
    String filename;
    String? fileExtension;
    
    try {
      // 🔥 优先使用后端提供的建议文件名（从 Content-Disposition 头获取）
      if (suggestedFilename != null && suggestedFilename.isNotEmpty) {
        filename = suggestedFilename;
        
        // 🔥 URL 解码建议文件名（解决中文乱码问题）
        try {
          // 检查是否包含 URL 编码字符（%XX 格式）
          if (filename.contains('%')) {
            filename = Uri.decodeComponent(filename);
            debugPrint('🔤 URL 解码后的建议文件名: $filename');
          } else {
            debugPrint('📌 使用后端提供的文件名（无需解码）: $filename');
          }
        } catch (e) {
          debugPrint('⚠️ URL 解码失败，使用原始文件名: $e');
        }

        // 从建议文件名中提取扩展名
        if (filename.contains('.')) {
          fileExtension = filename.split('.').last.toLowerCase();
          debugPrint('🏷️ 从建议文件名提取扩展名: .$fileExtension');
        }
      } else {
        // 如果没有建议文件名，从 URL 推断
        final uri = Uri.parse(url);
        final pathSegments = uri.pathSegments;
        
        if (pathSegments.isNotEmpty) {
          filename = pathSegments.last;
          // 移除查询参数和锚点
          if (filename.contains('?')) filename = filename.split('?').first;
          if (filename.contains('#')) filename = filename.split('#').first;
          
          // 🔥 URL 解码文件名（解决中文乱码问题）
          try {
            filename = Uri.decodeComponent(filename);
            debugPrint('🔤 URL 解码后的文件名: $filename');
          } catch (e) {
            debugPrint('⚠️ URL 解码失败: $e');
          }
          
          // 检查是否有扩展名
          if (filename.contains('.')) {
            fileExtension = filename.split('.').last.toLowerCase();
          }
          
          // 如果文件名无效或过长，使用默认名称
          if (filename.isEmpty || filename.length > 100 || !filename.contains('.')) {
            filename = 'download_${DateTime.now().millisecondsSinceEpoch}';
          }
        } else {
          filename = 'download_${DateTime.now().millisecondsSinceEpoch}';
        }
        
        debugPrint('🔍 从 URL 提取文件名: $filename');
      }
      
      // 🔥 如果没有扩展名，根据 URL 特征推断文件类型
      if (fileExtension == null || fileExtension.isEmpty) {
        final urlLower = url.toLowerCase();
        
        // 文档类
        if (urlLower.contains('.pdf') || urlLower.contains('/pdf/')) {
          fileExtension = 'pdf';
        } else if (urlLower.contains('.doc') || urlLower.contains('/doc/') || 
                   urlLower.contains('word') || urlLower.contains('/document/')) {
          fileExtension = 'docx';
        } else if (urlLower.contains('.xls') || urlLower.contains('/xls/') || 
                   urlLower.contains('excel') || urlLower.contains('/spreadsheet/')) {
          fileExtension = 'xlsx';
        } else if (urlLower.contains('.ppt') || urlLower.contains('/ppt/') || 
                   urlLower.contains('powerpoint') || urlLower.contains('/presentation/')) {
          fileExtension = 'pptx';
        }
        // 压缩文件
        else if (urlLower.contains('.zip') || urlLower.contains('/zip/') || 
                 urlLower.contains('archive') || urlLower.contains('/package/')) {
          fileExtension = 'zip';
        } else if (urlLower.contains('.rar') || urlLower.contains('/rar/')) {
          fileExtension = 'rar';
        } else if (urlLower.contains('.7z') || urlLower.contains('/7z/')) {
          fileExtension = '7z';
        }
        // 图片类
        else if (urlLower.contains('.jpg') || urlLower.contains('.jpeg') || 
                 urlLower.contains('/image/') || urlLower.contains('/photo/')) {
          fileExtension = 'jpg';
        } else if (urlLower.contains('.png') || urlLower.contains('/png/')) {
          fileExtension = 'png';
        } else if (urlLower.contains('.gif') || urlLower.contains('/gif/')) {
          fileExtension = 'gif';
        }
        // 视频类
        else if (urlLower.contains('.mp4') || urlLower.contains('/video/') || 
                 urlLower.contains('/media/')) {
          fileExtension = 'mp4';
        } else if (urlLower.contains('.avi') || urlLower.contains('/avi/')) {
          fileExtension = 'avi';
        } else if (urlLower.contains('.mov') || urlLower.contains('/mov/')) {
          fileExtension = 'mov';
        }
        // 音频类
        else if (urlLower.contains('.mp3') || urlLower.contains('/audio/') || 
                 urlLower.contains('/music/')) {
          fileExtension = 'mp3';
        } else if (urlLower.contains('.wav') || urlLower.contains('/wav/')) {
          fileExtension = 'wav';
        }
        // APK 应用
        else if (urlLower.contains('.apk') || urlLower.contains('/apk/')) {
          fileExtension = 'apk';
        }
        // 默认使用 dat
        else {
          fileExtension = 'dat';
          debugPrint('⚠️ 无法识别文件类型，使用默认扩展名 .dat');
        }
        
        // 添加扩展名到文件名
        if (!filename.endsWith('.$fileExtension')) {
          filename = '$filename.$fileExtension';
        }
      }
      
      debugPrint('📄 最终文件名: $filename');
      debugPrint('🏷️ 文件类型: .$fileExtension');
      
    } catch (e) {
      debugPrint('⚠️ 解析文件名失败: $e');
      filename = 'download_${DateTime.now().millisecondsSinceEpoch}.dat';
    }

    // 🔥 根据文件类型确定保存到哪个公共目录
    String publicDir;
    
    if (fileExtension != null) {
      final ext = fileExtension.toLowerCase();
      // 图片类 -> Pictures
      if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'].contains(ext)) {
        publicDir = 'Pictures';
      }
      // 视频类 -> Movies
      else if (['mp4', 'avi', 'mov', 'wmv', 'flv', 'mkv', 'webm'].contains(ext)) {
        publicDir = 'Movies';
      }
      // 音频类 -> Music
      else if (['mp3', 'wav', 'ogg', 'flac', 'aac', 'wma'].contains(ext)) {
        publicDir = 'Music';
      }
      // 文档类 -> Documents
      else if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'rtf'].contains(ext)) {
        publicDir = 'Documents';
      }
      // APK 应用 -> Download
      else if (ext == 'apk') {
        publicDir = 'Download';
      }
      // 其他文件 -> Download
      else {
        publicDir = 'Download';
      }
    } else {
      publicDir = 'Download';
    }
    
    // 🔥 构建公共目录路径（Android 标准公共目录）
    // 注意：这里假设是标准的 Android 内部存储路径。
    // 在生产环境中，可能需要处理不同厂商的路径差异，或者使用 android_path_provider 等库获取确切的外部存储根路径。
    final String savePath = '/storage/emulated/0/$publicDir/$filename';
    
    debugPrint('📂 保存到公共目录: $publicDir');
    debugPrint('💾 完整路径: $savePath');

    setState(() {
      _isDownloading = true;
      _downloadingFilename = filename;
      _downloadProgress = 0.0;
    });

    // 🔥 显示下载进度对话框
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext dialogContext) {
          return _buildDownloadDialog();
        },
      );
    }

    try {
      debugPrint('📥 开始下载: $url');

      // 使用 Dio 下载文件
      final Dio dio = Dio();
      await dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            debugPrint('📊 下载进度: ${(progress * 100).toStringAsFixed(1)}%');
            setState(() {
              _downloadProgress = progress;
            });
          }
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 10), // 🔥 增加到10分钟
          sendTimeout: const Duration(minutes: 2),
        ),
      );

      // 下载完成
      debugPrint('✅ 下载完成');
      
      // 🔥 通知系统媒体扫描器扫描新文件（让相册/文件管理器立即识别）
      // 注意：由于 media_scanner 插件存在跨盘符编译问题，这里暂时注释掉
      // 文件仍然会保存到公共目录，系统会在下次启动时自动扫描
      /*
      try {
        await MediaScanner.loadMedia(path: savePath);
        debugPrint('📡 已通知系统扫描文件: $savePath');
      } catch (e) {
        debugPrint('⚠️ 媒体扫描失败: $e');
      }
      */
      
      setState(() {
        _isDownloading = false;
        _downloadProgress = 1.0;
      });

      // 🔥 添加到下载历史
      setState(() {
        _downloadHistory.insert(0, {
          'filename': filename,
          'url': url,
          'savePath': savePath,
          'time': DateTime.now(),
          'status': 'completed',
        });
      });
      
      // 🔥 保存到本地存储
      await _saveDownloadHistory();

      // 关闭进度对话框并显示成功提示
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ 下载完成\n保存位置: $savePath'),
            duration: const Duration(seconds: 3), // 🔥 3秒后自动消失
            backgroundColor: Colors.green,
            // 🔥 移除"查看"按钮
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ 下载失败: $e');
      setState(() {
        _isDownloading = false;
      });
      
      // 🔥 添加失败的下载记录
      setState(() {
        _downloadHistory.insert(0, {
          'filename': filename,
          'url': url,
          'savePath': savePath,
          'time': DateTime.now(),
          'status': 'failed',
          'error': e.toString(),
        });
      });
      
      // 🔥 保存到本地存储
      await _saveDownloadHistory();
      
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ 下载失败: ${e.toString()}'),
            duration: const Duration(seconds: 5),
            backgroundColor: Colors.red,
            action: SnackBarAction(
              label: '重试',
              textColor: Colors.white,
              onPressed: () {
                _handleDownload(url, suggestedFilename);
              },
            ),
          ),
        );
      }
    }
  }

  // 🔥 用于存储 InAppWebViewController 以便执行 goBack/reload
  InAppWebViewController? _courseResourceWebViewController;
  InAppWebViewController? _quarkWebViewController;
  
  // 🔥 页面实际加载完成标记
  bool _courseResourceLoaded = false;
  bool _quarkLoaded = false;

  // 🔥 直接退出浏览器页面（不再处理网页内返回逻辑）
  void _exitBrowser() {
    if (mounted) {
      Navigator.pop(context);
    }
  }

  // 🔥 网页后退
  Future<void> _goBack() async {
    final controller = _currentTabIndex == 0 ? _courseResourceWebViewController : _quarkWebViewController;
    if (controller != null) {
      if (await controller.canGoBack()) {
        await controller.goBack();
      }
    }
  }

  // 🔥 网页前进
  Future<void> _goForward() async {
    final controller = _currentTabIndex == 0 ? _courseResourceWebViewController : _quarkWebViewController;
    if (controller != null) {
      if (await controller.canGoForward()) {
        await controller.goForward();
      }
    }
  }

  // 刷新页面
  Future<void> _refresh() async {
    final controller = _currentTabIndex == 0 ? _courseResourceWebViewController : _quarkWebViewController;
    if (controller != null) {
      // 🔥 刷新时重置加载状态
      if (mounted) {
        setState(() {
          _isLoading = true;
          if (_currentTabIndex == 0) {
            _courseResourceLoaded = false;
          } else {
            _quarkLoaded = false;
          }
        });
      }
      await controller.reload();
    }
  }

  // 🔥 显示下载管理弹窗
  void _showDownloadManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5, // 半屏高度
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 标题栏
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '下载管理',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Row(
                    children: [
                      if (_downloadHistory.isNotEmpty)
                        TextButton.icon(
                          icon: const Icon(Icons.delete_sweep, size: 20),
                          label: const Text('清空全部'),
                          onPressed: () {
                            // 🔥 先关闭弹窗（同步操作）
                            Navigator.pop(context);
                            
                            // 🔥 清空记录（同步操作）
                            setState(() {
                              _downloadHistory.clear();
                            });
                            
                            // 🔥 异步保存（使用 unawaited 明确表示不等待结果）
                            unawaited(_saveDownloadHistory());
                            
                            // 🔥 显示提示（同步操作）
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('已清空所有下载记录'),
                                duration: Duration(seconds: 2),
                              ),
                            );
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(),
              
              // 下载记录列表
              Expanded(
                child: _downloadHistory.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.download_outlined,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '暂无下载记录',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _downloadHistory.length,
                        itemBuilder: (context, index) {
                          final item = _downloadHistory[index];
                          final isCompleted = item['status'] == 'completed';
                          
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: Icon(
                                isCompleted ? Icons.check_circle : Icons.error,
                                color: isCompleted ? Colors.green : Colors.red,
                              ),
                              title: Text(
                                item['filename'],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item['time'].year}-${item['time'].month.toString().padLeft(2, '0')}-${item['time'].day.toString().padLeft(2, '0')} ${item['time'].hour.toString().padLeft(2, '0')}:${item['time'].minute.toString().padLeft(2, '0')}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (!isCompleted && item['error'] != null)
                                    Text(
                                      item['error'],
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.red,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                              trailing: isCompleted
                                  ? IconButton(
                                      icon: const Icon(Icons.open_in_new, size: 20),
                                      tooltip: '打开文件',
                                      onPressed: () {
                                        
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(
                                            content: Text('打开文件功能待实现'),
                                            duration: Duration(seconds: 2),
                                          ),
                                        );
                                      },
                                    )
                                  : IconButton(
                                      icon: const Icon(Icons.refresh, size: 20),
                                      tooltip: '重新下载',
                                      onPressed: () {
                                        _handleDownload(item['url'], item['filename']);
                                        Navigator.pop(context);
                                      },
                                    ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // 🔥 构建课程资源 WebView
  Widget _buildCourseResourceWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('http://cydc.dpdns.org')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        userAgent: 'Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
        useShouldOverrideUrlLoading: true,
        supportZoom: true, // 启用缩放
        // 🔥 启用下载支持
        useOnDownloadStart: true,
        // 🔥 允许混合内容（HTTP/HTTPS）
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        // 🔥 启用第三方 Cookie（某些下载需要）
        thirdPartyCookiesEnabled: true,
        // 🔥 允许文件访问（下载需要）
        allowFileAccess: true,
        allowFileAccessFromFileURLs: true,
        allowUniversalAccessFromFileURLs: true,
        // 🔥 禁用缓存，确保下载最新文件
        cacheEnabled: false,
      ),
      onWebViewCreated: (controller) {
        _courseResourceWebViewController = controller;
        // 🔥 初始显示加载动画
        if (mounted && !_courseResourceLoaded) {
          setState(() {
            _isLoading = true;
          });
        }
      },
      onLoadStart: (controller, url) {
        debugPrint('🔄 页面开始加载: $url');
      },
      onProgressChanged: (controller, progress) {
        // 🔥 使用进度变化来控制加载状态，更准确
        if (mounted) {
          if (progress < 100) {
            // 页面还在加载中
            if (!_isLoading) {
              setState(() {
                _isLoading = true;
              });
            }
          } else {
            // 进度达到100%，但还需要等待页面真正渲染完成
            debugPrint('📊 课程资源页面加载进度: $progress%');
          }
        }
      },
      onLoadStop: (controller, url) async {
        debugPrint('✅ 课程资源页面加载完成: $url');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _courseResourceLoaded = true;
          });
        }
        
        // 🔥 注入JavaScript检测文件上传元素和下载链接
        await controller.evaluateJavascript(source: '''
          (function() {
            // 1. 检测文件上传元素
            const fileInputs = document.querySelectorAll('input[type="file"]');
            console.log('📁 检测到 ' + fileInputs.length + ' 个文件上传元素');
            
            fileInputs.forEach((input, index) => {
              console.log('文件上传元素 ' + index + ':', input);
              
              // 添加点击事件监听
              input.addEventListener('click', function(e) {
                console.log('🔘 用户点击了文件上传按钮');
              });
              
              // 添加change事件监听
              input.addEventListener('change', function(e) {
                console.log('✅ 文件已选择:', this.files.length + ' 个文件');
              });
            });
            
            // 2. 🔥 拦截所有下载链接的点击事件
            const downloadLinks = document.querySelectorAll('a[href]');
            console.log('🔗 检测到 ' + downloadLinks.length + ' 个链接');
            
            downloadLinks.forEach((link, index) => {
              const href = link.href.toLowerCase();
              // 检测是否为下载链接（常见文件扩展名或下载API）
              const isDownloadLink = 
                href.endsWith('.pdf') || href.endsWith('.doc') || href.endsWith('.docx') ||
                href.endsWith('.xls') || href.endsWith('.xlsx') || href.endsWith('.ppt') ||
                href.endsWith('.pptx') || href.endsWith('.zip') || href.endsWith('.rar') ||
                href.endsWith('.7z') || href.endsWith('.tar') || href.endsWith('.gz') ||
                href.endsWith('.apk') || href.endsWith('.mp4') || href.endsWith('.avi') ||
                href.endsWith('.mov') || href.endsWith('.wmv') || href.endsWith('.flv') ||
                href.endsWith('.mkv') || href.endsWith('.mp3') || href.endsWith('.wav') ||
                href.endsWith('.jpg') || href.endsWith('.jpeg') || href.endsWith('.png') ||
                href.endsWith('.gif') || href.endsWith('.bmp') || href.endsWith('.webp') ||
                href.includes('/download/') || href.includes('/api/download/') ||
                href.includes('/api/file/') || href.includes('/file/download');
              
              if (isDownloadLink) {
                console.log('📥 检测到下载链接 ' + index + ':', link.href);
                
                link.addEventListener('click', function(e) {
                  console.log('🔘 用户点击下载链接:', this.href);
                  // 不阻止默认行为，让 WebView 的 onDownloadStart 处理
                });
              }
            });
          })();
        ''');
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString().toLowerCase() ?? '';
        
        // 🔥 只拦截不支持的协议，其他所有请求都允许正常加载
        if (url.startsWith('intent://')) {
          debugPrint('⚠️ 拦截不支持的协议: $url');
          return NavigationActionPolicy.CANCEL;
        }
        
        // 允许所有 http/https 请求（包括下载）
        if (url.startsWith('http') || url.startsWith('https')) {
          return NavigationActionPolicy.ALLOW;
        } else {
          // 其他协议一律拦截
          debugPrint('⚠️ 拦截未知协议: $url');
          return NavigationActionPolicy.CANCEL;
        }
      },
      onDownloadStartRequest: (controller, request) async {
        debugPrint('📥 检测到下载请求: ${request.url}');
        await _handleDownload(request.url.toString(), request.suggestedFilename);
      },
    );
  }

  // 🔥 构建夸克搜索 WebView
  Widget _buildQuarkWebView() {
    return InAppWebView(
      initialUrlRequest: URLRequest(url: WebUri('https://quark.sm.cn/')),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        userAgent: 'Mozilla/5.0 (Linux; Android 10; SM-G975F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.120 Mobile Safari/537.36',
        useShouldOverrideUrlLoading: true,
        supportZoom: true, // 启用缩放
        // 🔥 启用下载支持
        useOnDownloadStart: true,
        // 🔥 允许混合内容（HTTP/HTTPS）
        mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
        // 🔥 启用第三方 Cookie（某些下载需要）
        thirdPartyCookiesEnabled: true,
      ),
      onWebViewCreated: (controller) {
        _quarkWebViewController = controller;
        // 🔥 初始显示加载动画
        if (mounted && !_quarkLoaded) {
          setState(() {
            _isLoading = true;
          });
        }
      },
      onLoadStart: (controller, url) {
        debugPrint('🔄 页面开始加载: $url');
      },
      onProgressChanged: (controller, progress) {
        // 🔥 使用进度变化来控制加载状态，更准确
        if (mounted) {
          if (progress < 100) {
            // 页面还在加载中
            if (!_isLoading) {
              setState(() {
                _isLoading = true;
              });
            }
          } else {
            // 进度达到100%，但还需要等待页面真正渲染完成
            debugPrint('📊 夸克搜索页面加载进度: $progress%');
          }
        }
      },
      onLoadStop: (controller, url) async {
        debugPrint('✅ 夸克搜索页面加载完成: $url');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _quarkLoaded = true;
          });
        }
        
        // 🔥 注入JavaScript检测文件上传元素和下载链接
        await controller.evaluateJavascript(source: '''
          (function() {
            // 1. 检测文件上传元素
            const fileInputs = document.querySelectorAll('input[type="file"]');
            console.log('📁 检测到 ' + fileInputs.length + ' 个文件上传元素');
            
            fileInputs.forEach((input, index) => {
              console.log('文件上传元素 ' + index + ':', input);
              
              // 添加点击事件监听
              input.addEventListener('click', function(e) {
                console.log('🔘 用户点击了文件上传按钮');
              });
              
              // 添加change事件监听
              input.addEventListener('change', function(e) {
                console.log('✅ 文件已选择:', this.files.length + ' 个文件');
              });
            });
            
            // 2. 🔥 拦截所有下载链接的点击事件
            const downloadLinks = document.querySelectorAll('a[href]');
            console.log('🔗 检测到 ' + downloadLinks.length + ' 个链接');
            
            downloadLinks.forEach((link, index) => {
              const href = link.href.toLowerCase();
              // 检测是否为下载链接（常见文件扩展名或下载API）
              const isDownloadLink = 
                href.endsWith('.pdf') || href.endsWith('.doc') || href.endsWith('.docx') ||
                href.endsWith('.xls') || href.endsWith('.xlsx') || href.endsWith('.ppt') ||
                href.endsWith('.pptx') || href.endsWith('.zip') || href.endsWith('.rar') ||
                href.endsWith('.7z') || href.endsWith('.tar') || href.endsWith('.gz') ||
                href.endsWith('.apk') || href.endsWith('.mp4') || href.endsWith('.avi') ||
                href.endsWith('.mov') || href.endsWith('.wmv') || href.endsWith('.flv') ||
                href.endsWith('.mkv') || href.endsWith('.mp3') || href.endsWith('.wav') ||
                href.endsWith('.jpg') || href.endsWith('.jpeg') || href.endsWith('.png') ||
                href.endsWith('.gif') || href.endsWith('.bmp') || href.endsWith('.webp') ||
                href.includes('/download/') || href.includes('/api/download/') ||
                href.includes('/api/file/') || href.includes('/file/download');
              
              if (isDownloadLink) {
                console.log('📥 检测到下载链接 ' + index + ':', link.href);
                
                link.addEventListener('click', function(e) {
                  console.log('🔘 用户点击下载链接:', this.href);
                  // 不阻止默认行为，让 WebView 的 onDownloadStart 处理
                });
              }
            });
          })();
        ''');
      },
      onReceivedError: (controller, request, error) {
        debugPrint('❌ WebView加载错误: ${error.description}');
      },
      shouldOverrideUrlLoading: (controller, navigationAction) async {
        final url = navigationAction.request.url?.toString().toLowerCase() ?? '';
        
        if (url.startsWith('intent://')) {
          return NavigationActionPolicy.CANCEL;
        }
        
        if (url.startsWith('http') || url.startsWith('https')) {
          return NavigationActionPolicy.ALLOW;
        } else {
          return NavigationActionPolicy.CANCEL;
        }
      },
      onDownloadStartRequest: (controller, request) async {
        debugPrint('📥 检测到下载请求: ${request.url}');
        await _handleDownload(request.url.toString(), request.suggestedFilename);
      },
    );
  }

  // 🔥 下载进度对话框组件
  Widget _buildDownloadDialog() {
    return AlertDialog(
      title: const Text('下载文件'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_downloadingFilename ?? ''),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: _downloadProgress,  // 🔥 直接使用进度值，从 0 开始显示
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
          ),
          const SizedBox(height: 8),
          Text('${(_downloadProgress * 100).toStringAsFixed(1)}%'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            // 🔥 允许随时关闭对话框，但不取消下载任务
            if (_isDownloading) {
              debugPrint('⚠️ 用户关闭了下载对话框，但下载仍在后台继续');
            }
            Navigator.of(context).pop();
          },
          child: const Text('关闭'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 🔥 获取状态栏高度
    final statusBarHeight = MediaQuery.of(context).padding.top;
    
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 🔥 状态栏安全区域占位
          SizedBox(height: statusBarHeight),
          
          // ✅ 顶部工具栏：严格按 6 等份分配
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 🔥 第1份（最左）：返回按钮（直接退出页面）
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.black87),
                    onPressed: _exitBrowser,
                    tooltip: '退出浏览器',
                  ),
                ),
                
                // 🔥 第2、3份：课程资源标签（占2份）
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () {
                      if (_currentTabIndex != 0) {
                        _tabController.animateTo(0);
                      }
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _currentTabIndex == 0 ? Colors.blue : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        '课程资源',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _currentTabIndex == 0 ? Colors.blue : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 🔥 第4、5份：夸克搜索标签（占2份）
                Expanded(
                  flex: 2,
                  child: GestureDetector(
                    onTap: () {
                      if (_currentTabIndex != 1) {
                        _tabController.animateTo(1);
                      }
                    },
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _currentTabIndex == 1 ? Colors.blue : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                      child: Text(
                        '夸克搜索',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _currentTabIndex == 1 ? Colors.blue : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
                
                // 🔥 第6份（最右）：刷新按钮
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: Icon(
                      Icons.refresh,
                      color: Colors.black87,
                    ),
                    onPressed: _refresh,
                    tooltip: '刷新',
                  ),
                ),
              ],
            ),
          ),
          
          // WebView内容区域
          Expanded(
            child: Stack(
              children: [
                TabBarView(
                  controller: _tabController,
                  physics: const NeverScrollableScrollPhysics(), // 禁止左右滑动切换
                  children: [
                    _buildCourseResourceWebView(),
                    _buildQuarkWebView(),
                  ],
                ),
                
                // 🔥 加载动画（页面加载中显示居中圆形进度条）
                if (_isLoading)
                  Container(
                    color: Colors.white.withValues(alpha: 0.9),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                            strokeWidth: 4,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '加载中...',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                
                // 顶部加载进度条（细线）
                if (_isLoading)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                      backgroundColor: Colors.grey[200],
                      minHeight: 2,
                    ),
                  ),
              ],
            ),
          ),
          
          // 🔥 底部工具栏：三栏均分
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              children: [
                // 🔥 左侧：网页后退
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios, color: Colors.black87),
                    onPressed: _goBack,
                    tooltip: '后退',
                  ),
                ),
                
                // 🔥 中间：网页前进
                Expanded(
                  flex: 1,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_forward_ios, color: Colors.black87),
                    onPressed: _goForward,
                    tooltip: '前进',
                  ),
                ),
                
                // 🔥 右侧：下载管理入口
                Expanded(
                  flex: 1,
                  child: Stack(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.download, color: Colors.black87),
                        onPressed: _showDownloadManager,
                        tooltip: '下载管理',
                      ),
                      // 🔥 下载数量角标
                      if (_downloadHistory.isNotEmpty)
                        Positioned(
                          right: 8,
                          top: 8,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              _downloadHistory.length > 99 ? '99+' : '${_downloadHistory.length}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
