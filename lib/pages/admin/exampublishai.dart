import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:zdxtapp/config.dart';

// 智谱AI配置（从public/aichat.dart复制）
const String aiUrl = "https://open.bigmodel.cn/api/paas/v4/chat/completions";
const String apiKey = "a5e3218c3c034f63afa1017f4e93c6e0.iJKY0ydDMk4o64AU";
const String modelName = "glm-4-flash";

class Exampublishai {
  /// 🔥 核心修复：清理流式数据中的脏字符
  /// 处理跨chunk的不完整行、控制字符、非法Unicode等
  static String cleanStreamData(String data) {
    if (data.isEmpty) return data;
    
    String cleaned = data;
    
    // 1. 移除BOM标记（UTF-8 BOM）
    if (cleaned.startsWith('\uFEFF')) {
      cleaned = cleaned.substring(1);
    }
    
    // 2. 清理控制字符（保留换行、制表符）
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    
    // 3. 清理零宽字符
    cleaned = cleaned.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '');
    
    // 4. 统一换行符（\r\n → \n）
    cleaned = cleaned.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    
    // 5. 处理多余的空白（保留必要的空格和换行，但在JSON键值对中通常不需要多余空格）
    // 注意：这里不盲目压缩所有空格，以免破坏LaTeX或文本内容，仅在必要时由JSON解析器处理
    // cleaned = cleaned.replaceAll(RegExp(r'[ \t]+'), ' '); 
    
    return cleaned.trim();
  }

  /// 统一格式化特殊符号、数学公式、语文声调
  /// 🔥 优化：遵循最小干预原则，只处理必要的Unicode解码和HTML实体清理，避免破坏LaTeX语法
  static String formatSpecialText(String? text) {
    if (text == null || text.isEmpty) return text ?? '';

    String result = text;

    // 🔥 关键修复1：先解码Unicode转义字符（如 \u00b2 → ²）
    result = _decodeUnicodeEscapes(result);

    // 🔥 关键修复2：将AI可能返回的特殊字符转换为LaTeX格式
    // 注意：这些转换是必要的，因为AI可能返回特殊字符而不是LaTeX
    
    // 1. 平方/立方符号
    result = result.replaceAll('²', '^{2}');
    result = result.replaceAll('³', '^{3}');
    
    // 2. 根号 √ → \sqrt{...}
    // 先处理简单的 √x 格式
    result = result.replaceAllMapped(
      RegExp(r'√([a-zA-Z0-9]+)'),
      (match) => '\\sqrt{${match.group(1)}}',
    );
    // 再处理单独的 √ 符号
    result = result.replaceAll('√', '\\sqrt{}');
    
    // 3. 乘号 × → \times
    result = result.replaceAll('×', '\\times');
    
    // 4. 除号 ÷ → \div
    result = result.replaceAll('÷', '\\div');
    
    // 5. 分数格式 (a/b) → \frac{a}{b}（简单情况）
    result = result.replaceAllMapped(
      RegExp(r'\(([^/]+)/([^)]+)\)'),
      (match) => '\\frac{${match.group(1)}}{${match.group(2)}}',
    );
    
    // 6. 清理HTML实体编码
    result = result.replaceAll(RegExp(r'&#(\d+);'), '');
    result = result.replaceAll('&nbsp;', ' ');
    result = result.replaceAll('&lt;', '<');
    result = result.replaceAll('&gt;', '>');
    result = result.replaceAll('&amp;', '&');

    // 7. 清理多余的LaTeX包裹符（保留内部公式）
    // 某些AI可能返回 \( ... \) 或 \[ ... \]，统一清理以便使用 $ 包裹
    result = result.replaceAll(RegExp(r'\\\('), '');
    result = result.replaceAll(RegExp(r'\\\)'), '');
    result = result.replaceAll(RegExp(r'\\\['), '');
    result = result.replaceAll(RegExp(r'\\\]'), '');

    // 🔥 重要：不进行多余空格清理，保持LaTeX语法完整性
    // 移除首尾空白即可
    return result.trim();
  }

  /// 🔥 新增：解码Unicode转义字符
  /// 将 \uXXXX 格式的字符串转换为对应的Unicode字符
  static String _decodeUnicodeEscapes(String text) {
    return text.replaceAllMapped(
      RegExp(r'\\u([0-9a-fA-F]{4})'),
      (match) {
        try {
          final codePoint = int.parse(match.group(1)!, radix: 16);
          return String.fromCharCode(codePoint);
        } catch (e) {
          return match.group(0)!; // 解析失败则保留原样
        }
      },
    );
  }

  /// 🔥 核心修复：安全的JSON解析方法
  /// 增加多层容错机制，处理AI返回的不完整或格式错误的JSON
  /// 
  /// 参数：
  /// - content: JSON字符串
  /// - silent: 是否静默模式（不打印错误日志），默认false
  static Map<String, dynamic>? safeJsonParse(String content, {bool silent = false}) {
    if (content.isEmpty) return null;
    
    // 第1层：尝试直接解析
    try {
      final result = jsonDecode(content);
      if (result is Map<String, dynamic>) {
        if (!silent) debugPrint('✅ JSON直接解析成功');
        return result;
      }
    } catch (e) {
      if (!silent) debugPrint('⚠️ JSON直接解析失败: $e');
    }
    
    // 第2层：清理特殊字符后解析
    try {
      String cleaned = _cleanJsonForParse(content);
      final result = jsonDecode(cleaned);
      if (result is Map<String, dynamic>) {
        if (!silent) debugPrint('✅ JSON清理后解析成功');
        return result;
      }
    } catch (e) {
      if (!silent) debugPrint('⚠️ JSON清理后解析失败: $e');
    }
    
    // 第3层：提取JSON对象
    try {
      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
      if (jsonMatch != null) {
        final jsonStr = jsonMatch.group(0)!;
        String cleaned = _cleanJsonForParse(jsonStr);
        final result = jsonDecode(cleaned);
        if (result is Map<String, dynamic>) {
          if (!silent) debugPrint('✅ JSON提取后解析成功');
          return result;
        }
      }
    } catch (e) {
      if (!silent) debugPrint('⚠️ JSON提取后解析失败: $e');
    }
    
    // 第4层：尝试修复常见问题
    try {
      String fixed = _fixCommonJsonIssues(content);
      final result = jsonDecode(fixed);
      if (result is Map<String, dynamic>) {
        if (!silent) debugPrint('✅ JSON修复后解析成功');
        return result;
      }
    } catch (e) {
      if (!silent) debugPrint('⚠️ JSON修复后解析失败: $e');
    }
    
    if (!silent) debugPrint('❌ 所有JSON解析策略均失败');
    return null;
  }
  
  /// 🔥 内部方法：清理JSON内容以支持解析
  static String _cleanJsonForParse(String content) {
    String cleaned = content;
    
    // 🔥 核心修复1：移除 Markdown 代码块标记
    // 移除开头的 ```json 或 ```
    cleaned = cleaned.replaceAll(RegExp(r'^\s*```json\s*', multiLine: true), '');
    cleaned = cleaned.replaceAll(RegExp(r'^\s*```\s*', multiLine: true), '');
    // 移除结尾的 ```
    cleaned = cleaned.replaceAll(RegExp(r'\s*```\s*$', multiLine: true), '');
    
    // 🔥 核心修复2：直接转义所有单个反斜杠为双反斜杠
    // 这是最关键的一步！JSON字符串中的所有反斜杠都必须转义
    // 例如：\geq → \\geq, \frac → \\frac
    cleaned = cleaned.replaceAll('\\', '\\\\');
    
    // 3. 清理破坏性字符（控制字符、回车符等）
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    cleaned = cleaned.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    
    return cleaned;
  }
  
  /// 🔥 内部方法：修复常见的JSON格式问题
  static String _fixCommonJsonIssues(String content) {
    String fixed = content;
    
    // 1. 确保JSON以{开头，以}结尾
    final openBrace = fixed.indexOf('{');
    final closeBrace = fixed.lastIndexOf('}');
    if (openBrace != -1 && closeBrace != -1 && closeBrace > openBrace) {
      fixed = fixed.substring(openBrace, closeBrace + 1);
    }
    
    // 2. 移除末尾的逗号（JSON不允许）
    fixed = fixed.replaceAll(RegExp(r',\s*([\}\]])'), r'$1');
    
    // 3. 修复未闭合的字符串 (简化版：尝试在末尾补全引号，如果明显缺失)
    // 这是一个启发式修复，针对AI截断情况
    if (fixed.endsWith('"') == false && fixed.contains('": "')) {
       // 简单的启发式：如果最后一行看起来像是一个未完成的字符串值
       // 这里不做过于复杂的正则替换，以免误伤，主要依靠前面的提取和清理
    }
    
    return fixed;
  }

  /// 递归格式化试卷中所有题目
  static Map<String, dynamic> formatPaperData(Map<String, dynamic> data) {
    if (data['questions'] != null && data['questions'] is List) {
      data['questions'] = data['questions'].map((q) {
        // 🔥 核心修复：先格式化特殊字符，再包裹未包裹的 LaTeX 公式
        q['title'] = wrapAndFormatLatex(q['title']);
        q['answer'] = wrapAndFormatLatex(q['answer']);
        q['analysis'] = wrapAndFormatLatex(q['analysis']);
        if (q['options'] != null && q['options'] is List) {
          // 🔥 核心修复：去除选项中的字母前缀（如 "A. "、"B. "），系统会自动生成选项字母
          q['options'] = q['options'].map((opt) {
            String optStr = opt.toString();
            // 去除开头的字母前缀（如 "A. "、"B. "、"C. "、"D. "）
            optStr = optStr.replaceAll(RegExp(r'^[A-D]\s*[\.\、]\s*'), '');
            return wrapAndFormatLatex(optStr);
          }).toList();
        }
        return q;
      }).toList();
    }

    data['paperName'] = formatSpecialText(data['paperName']);
    data['subject'] = formatSpecialText(data['subject']);
    return data;
  }

  /// 🔥 核心修复：先格式化特殊字符，再包裹未包裹的 LaTeX 公式（增强版）
  /// 
  /// 公开方法，供导入出题和 AI 出题统一使用
  static String wrapAndFormatLatex(String? text) {
    if (text == null || text.isEmpty) return text ?? '';
    
    // 第1步：格式化特殊字符（如 ² → ^{2}）
    String formatted = formatSpecialText(text);
    
    // 第2步：如果包含反斜杠，说明有 LaTeX 命令，需要包裹
    if (!formatted.contains('\\')) {
      return formatted; // 没有 LaTeX 命令，直接返回
    }
    
    try {
      String result = formatted;
      
      // 保护已正确包裹的公式
      List<String> protectedFormulas = [];
      
      // 保护 $$...$$ 块级公式
      result = result.replaceAllMapped(
        RegExp(r'\$\$([\s\S]*?)\$\$', multiLine: true, dotAll: true),
        (match) {
          protectedFormulas.add(match.group(0)!);
          return '<<BLOCK_FORMULA_${protectedFormulas.length - 1}>>';
        },
      );
      
      // 保护 $...$ 行内公式
      result = result.replaceAllMapped(
        RegExp(r'(?<!\$)\$(?!\$)(.+?)(?<!\$)\$(?!\$)', dotAll: true),
        (match) {
          protectedFormulas.add(match.group(0)!);
          return '<<INLINE_FORMULA_${protectedFormulas.length - 1}>>';
        },
      );
      
      // 🔥 核心修复：识别连续的 LaTeX 表达式并整体包裹
      // 策略：找到所有 \命令{...} 或 \命令 的位置，然后合并相邻的为一个公式
      final latexCommands = [
        'sqrt', 'frac', 'boldsymbol', 'text', 'mathrm', 'mathbf', 'mathit',
        'sum', 'prod', 'int', 'lim', 'infty',
        'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'pi', 'sigma', 'omega',
        'cdot', 'times', 'div', 'pm', 'mp',
        'leq', 'geq', 'neq', 'approx', 'equiv',
        'subset', 'supset', 'cup', 'cap', 'emptyset',
        'forall', 'exists', 'neg', 'land', 'lor',
        'rightarrow', 'leftarrow', 'leftrightarrow',
        'Rightarrow', 'Leftarrow', 'Leftrightarrow',
        'hat', 'bar', 'vec', 'dot', 'ddot',
        'sin', 'cos', 'tan', 'log', 'ln', 'exp',
        'partial', 'nabla', 'prime',
      ];
      
      //  核心修复：使用更强大的正则，支持嵌套花括号和多参数命令
      // 匹配 \命令{内容}，其中内容可以包含嵌套的花括号
      for (String cmd in latexCommands) {
        // 匹配带花括号的命令（支持多参数和嵌套）
        // 关键修复：使用 + 匹配一个或多个 {..} 组，以支持 \frac{a}{b} 这样的多参数命令
        final regexWithBraces = RegExp(r'\\' + cmd + r'(\{(?:[^{}]|\{[^{}]*\})*\})+');
        result = result.replaceAllMapped(regexWithBraces, (match) {
          String matched = match.group(0)!;
          if (matched.contains('<<BLOCK_FORMULA_') || matched.contains('<<INLINE_FORMULA_')) {
            return matched;
          }
          return '\$$matched\$';
        });
        
        // 匹配不带花括号的命令
        final regexWithoutBraces = RegExp(r'\\' + cmd + r'(?![a-zA-Z{])');
        result = result.replaceAllMapped(regexWithoutBraces, (match) {
          String matched = match.group(0)!;
          if (matched.contains('<<BLOCK_FORMULA_') || matched.contains('<<INLINE_FORMULA_')) {
            return matched;
          }
          return '\$$matched\$';
        });
      }
      
      // 🔥 核心修复：合并相邻的公式（去除中间的多余 $ 符号）
      // 例如：$x$ + $y$ → $x + y$
      result = result.replaceAll(RegExp(r'\$([^$]+)\$\s*([+\-*/=<>])\s*\$([^$]+)\$'), r'$\1 \2 \3$');
      
      // 🔥 核心修复：处理未被包裹的数学表达式
      // 匹配包含 ^ 或 _ 的表达式（如 a^2+b^2, x_1），但不在 $...$ 内
      result = result.replaceAllMapped(
        RegExp(r'(?<!\$)([a-zA-Z0-9][\^_][a-zA-Z0-9{}]+[^$]*?)(?=\s*[,+\-*/=<>]\s|$|\]|\)|，|。|；)(?!\$)'),
        (match) {
          String matched = match.group(0)!;
          if (matched.contains('<<BLOCK_FORMULA_') || matched.contains('<<INLINE_FORMULA_')) {
            return matched;
          }
          // 如果表达式中包含LaTeX命令，必须包裹
          if (matched.contains('\\') || matched.contains('^') || matched.contains('_')) {
            return '\$$matched\$';
          }
          return matched;
        },
      );
      
      // 🔥 核心修复：处理不完整的公式（只有开头或只有结尾的 $）
      // 匹配 $内容 但没有闭合 $ 的情况
      result = result.replaceAllMapped(
        RegExp(r'(?<!\$)\$(?!\$)([^$]+?)(?=$|\s|，|。|；|\]|\))', dotAll: true),
        (match) {
          String matched = match.group(0)!;
          // 如果已经包含在保护占位符中，跳过
          if (matched.contains('<<BLOCK_FORMULA_') || matched.contains('<<INLINE_FORMULA_')) {
            return matched;
          }
          // 关键修复：检查匹配的内容是否是占位符的一部分
          // 占位符格式：<<BLOCK_FORMULA_0>> 或 <<INLINE_FORMULA_0>>
          if (matched.contains('BLOCK_FORMULA') || matched.contains('INLINE_FORMULA')) {
            return matched;
          }
          // 如果匹配的内容中已经包含 $（说明是单独的 $），则补全
          if (!matched.endsWith('\$')) {
            return '$matched\$';
          }
          return matched;
        },
      );
      
      // 还原保护的公式
      // 🔥 关键修复：必须从后往前还原，避免占位符被重复替换
      for (int i = protectedFormulas.length - 1; i >= 0; i--) {
        // 🔥 关键修复：replaceAll 的替换字符串中的 $ 会被解释为捕获组引用
        // 所以需要将公式中的 $ 转义为 $$
        String escapedFormula = protectedFormulas[i].replaceAll('\$', '\$\$');
        result = result.replaceAll('<<BLOCK_FORMULA_$i>>', escapedFormula);
        result = result.replaceAll('<<INLINE_FORMULA_$i>>', escapedFormula);
      }
      
      return result;
    } catch (e) {
      debugPrint('⚠️ [AI出题] LaTeX 公式包裹失败: $e');
      debugPrint('⚠️ [AI出题] 原始文本: $text');
      return formatted; // 失败时返回格式化后的文本
    }
  }

  /// 🔥 新增：流式生成试卷（支持实时回调）
  static Future<void> generatePaperByAIStream(
    Map<String, dynamic> params, {
    required Function(String chunk) onChunkReceived, // 实时接收原始内容
    required Function(Map<String, dynamic> result) onComplete, // 生成完成
    required Function(String error) onError, // 生成失败
  }) async {
    try {
      // 🔥 修复1：先把题型题量转成明确的Map，方便后面校验
      final typeCountMap = <String, int>{};
      final typeLabelMap = <String, String>{};
      for (var item in params['questionTypes'] as List) {
        typeCountMap[item['type']] = item['count'] ?? 0;
        typeLabelMap[item['type']] = item['label'];
      }

      final String prompt = '''
你是专业学科出题老师，**只返回标准JSON，禁止输出任何多余文字**。

## 🔥 硬性题量要求（最高优先级，必须严格遵守）
**必须生成 exactly 以下数量的题目，一道都不能少，一道都不能多：**
- 单选题：${typeCountMap['single'] ?? 0} 道
- 多选题：${typeCountMap['multi'] ?? 0} 道
- 填空题：${typeCountMap['fill'] ?? 0} 道
- 简答题：${typeCountMap['short'] ?? 0} 道
**总计：${(typeCountMap.values.fold(0, (sum, count) => sum + count))} 道题目**
⚠️ 如果题量不符，系统将拒绝接收！

## 试卷基础信息
试卷名称：${params['paperName']}
科目：${params['subject']}
出题范围：${params['questionScope']}

## 统一出题规范
1. 题目贴合教学考纲，内容严谨无误
2. **题干只写纯题目内容，严禁写入任何选项文字**，所有选项统一存入options数组
3. 答案规范：单选题填单个大写字母，多选题填大写字母组合，填空题直接填写答案，简答题书写完整标准答案
4. 每道题目必须附带解析，解析简洁清晰，点明核心考点与解题思路
5. 数学格式统一规则：所有数学公式统一使用\$...\$包裹编写（如：\$x^2 + y^2 = z^2\$），公式紧贴文字排版，禁止公式单独换行拆分

## 🔥 JSON格式强制要求（非常重要）
1. **必须返回合法的JSON格式**，可以直接被jsonDecode解析
2. **LaTeX公式中的反斜杠必须转义**：
   - 错误示例："\\geq", "\\neq", "\\sin", "\\frac"
   - 正确示例："\\\\geq", "\\\\neq", "\\\\sin", "\\\\frac"
   - 即：每个反斜杠 \\ 必须写成两个反斜杠 \\\\
3. **禁止输出Markdown代码块标记**（不要使用 ```json 或 ```）
4. **选项内容不带A/B/C/D标识**，只写选项内容本身

## 题型区分规则
1. 单选题、多选题：正常填写完整选项内容，选项内不带A/B/C/D标识
2. 填空题、简答题：options字段固定为空数组

## 固定返回JSON格式
{
  "paperName": "试卷名称",
  "subject": "科目",
  "questions": [
    {
      "type": "single|multi|fill|short",
      "title": "题目内容",
      "options": [],
      "answer": "对应标准答案",
      "analysis": "题目解析"
    }
  ]
}

      '''.trim();

      debugPrint('🚀 开始流式请求AI出题...');
      
      final request = http.Request('POST', Uri.parse(aiUrl));
      request.headers.addAll({
        "Content-Type": "application/json",
        "Authorization": "Bearer $apiKey"
      });
      request.body = jsonEncode({
        "model": modelName,
        "messages": [
          {"role": "system", "content": "你是专业出题助手，严格按照要求返回标准JSON格式试卷数据。题型type字段必须使用英文值：single（单选题）、multi（多选题）、fill（填空题）、short（简答题）。答案格式：单选题仅返回单个大写字母（如A），多选题返回多个大写字母组合（如AB），填空题返回答案文本用分号分隔，简答题返回完整参考答案。每道题必须包含完整的解析字段。只返回JSON，无任何其他文字。"},
          {"role": "user", "content": prompt}
        ],
        "stream": true, // 🔥 启用流式输出
        "temperature": 0.3
      });

      final streamedResponse = await request.send().timeout(const Duration(seconds: 600));
      
      if (streamedResponse.statusCode != 200) {
        throw Exception('AI接口请求失败：${streamedResponse.statusCode}');
      }

      // 🔥 读取流式响应并拼接，同时实时回调
      final StringBuffer contentBuffer = StringBuffer();
      String incompleteLine = ''; // 用于处理跨chunk的不完整行
      
      await for (final chunk in streamedResponse.stream.transform(utf8.decoder)) {
        // 将当前块与之前不完整的行合并
        String fullChunk = incompleteLine + chunk;
        
        // 按行分割
        final lines = fullChunk.split('\n');
        
        // 最后一行可能是不完整的，保存到下次处理
        incompleteLine = lines.last;
        
        // 处理除最后一行之外的所有行
        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.startsWith('data: ')) {
            final data = line.substring(6).trim();
            if (data == '[DONE]') {
              break;
            }
            
            try {
              final jsonData = jsonDecode(data);
              final delta = jsonData['choices']?[0]?['delta']?['content'];
              if (delta != null && delta is String) {
                contentBuffer.write(delta);
                // 🔥 实时回调原始内容
                onChunkReceived(delta);
              }
            } catch (e) {
              debugPrint('⚠️ 解析流式数据块失败: $e');
              debugPrint('⚠️ 错误数据: $data');
            }
          }
        }
      }
      
      // 处理最后可能剩余的不完整行
      if (incompleteLine.isNotEmpty) {
        final line = incompleteLine.trim();
        if (line.startsWith('data: ')) {
          final data = line.substring(6).trim();
          if (data != '[DONE]' && data.isNotEmpty) {
            try {
              final jsonData = jsonDecode(data);
              final delta = jsonData['choices']?[0]?['delta']?['content'];
              if (delta != null && delta is String) {
                contentBuffer.write(delta);
                onChunkReceived(delta);
              }
            } catch (e) {
              debugPrint('⚠️ 解析流式数据块失败: $e');
              debugPrint('⚠️ 错误数据: $data');
            }
          }
        }
      }

      final content = contentBuffer.toString();
      debugPrint('🤖 流式接收完成，总长度: ${content.length}');

      if (content.isEmpty) {
        throw Exception('AI未返回有效试卷内容');
      }

      debugPrint('🤖 AI原始返回内容长度: ${content.length}');
      debugPrint('🤖 AI原始返回前200字符: ${content.substring(0, content.length > 200 ? 200 : content.length)}');
      
      // 🔥 核心修复：打印完整内容（如果不太长）
      if (content.length < 5000) {
        debugPrint('📝 AI完整返回内容:\n$content');
      } else {
        debugPrint('📝 AI返回内容太长(${content.length}字符)，仅显示前后各500字符');
        debugPrint('前500字符: ${content.substring(0, 500)}');
        debugPrint('后500字符: ${content.substring(content.length - 500)}');
      }
      
      // ✅ 尝试解析JSON，使用安全解析机制
      Map<String, dynamic>? result = safeJsonParse(content);
      if (result == null) {
        throw Exception('无法从AI响应中解析JSON数据');
      }
      
      debugPrint('✅ JSON解析成功，题目总数: ${(result['questions'] as List?)?.length ?? 0}');
      
      // 🔥 修复3：强制校验题型数量（一道都不能少）
      if (result['questions'] != null && result['questions'] is List) {
        final questions = result['questions'] as List;
        
        // 统计各题型实际数量
        final actualCountMap = <String, int>{};
        for (var q in questions) {
          String type = q['type']?.toString() ?? 'single';
          actualCountMap[type] = (actualCountMap[type] ?? 0) + 1;
        }
        
        debugPrint('📊 题型数量统计 - 要求: $typeCountMap, 实际: $actualCountMap');
        
        // 逐一校验
        for (var entry in typeCountMap.entries) {
          final type = entry.key;
          final required = entry.value;
          final actual = actualCountMap[type] ?? 0;
          
          if (required > 0 && actual < required) {
            throw Exception('AI生成题量不足！${typeLabelMap[type]}要求 $required 道，实际只生成了 $actual 道，请重试');
          }
        }
        
        debugPrint('✅ 题型数量校验通过！');
      }
      
      // 🔥 调试：打印第一道题的公式格式
      if (result['questions'] != null && (result['questions'] as List).isNotEmpty) {
        final firstQ = result['questions'][0];
        debugPrint('📝 第一题题干: ${firstQ['title']}');
        debugPrint('📝 第一题答案: ${firstQ['answer']}');
        debugPrint('📝 第一题解析: ${firstQ['analysis']}');
        if (firstQ['options'] != null && (firstQ['options'] as List).isNotEmpty) {
          debugPrint('📝 第一题选项: ${firstQ['options']}');
        }
      }
      
      final formattedResult = formatPaperData(result);
      
      // ✅ 验证格式化后的数据
      if (formattedResult['questions'] == null || (formattedResult['questions'] as List).isEmpty) {
        throw Exception('AI返回的题目列表为空');
      }
      
      // 🔥 调用完成回调
      onComplete(formattedResult);
      
    } catch (e) {
      debugPrint('❌ AI出题异常: $e');
      onError(e.toString());
    }
  }

  /// 提交试卷到后端
  static Future<Map<String, dynamic>> submitPaperToServer(
    Map<String, dynamic> paperData,
    Map<String, dynamic> examConfig,
  ) async {
    try {
      final Map<String, dynamic> submitData = {
        'action': 'createExam',
        'examName': paperData['paperName'],
        'subject': paperData['subject'],
        'examTime': examConfig['examTime'],
        'status': examConfig['status'] ?? '自由',
        'timingType': examConfig['timingType'] ?? 'totalTime',
        'totalTime': examConfig['timingType'] == 'totalTime' ? examConfig['totalTime'] : null,
        'perTypeTime': examConfig['timingType'] == 'perQuestionTime' ? examConfig['perTypeTime'] : null,
        'questions': paperData['questions'],
      };

      final res = await http.post(
        Uri.parse('${Config.baseUrl}/api/exam'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(submitData),
      );

      if (res.statusCode != 200) {
        throw Exception('提交试卷失败：${res.statusCode}');
      }

      final result = jsonDecode(res.body);
      if (result['success'] != true) {
        throw Exception(result['msg'] ?? '提交失败');
      }

      return {
        'success': true,
        'examId': result['examId'],
        'message': result['msg'],
      };
    } catch (e) {
      rethrow;
    }
  }
}