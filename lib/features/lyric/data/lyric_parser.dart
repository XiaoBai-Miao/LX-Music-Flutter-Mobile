import 'package:flutter/foundation.dart';
import '../domain/lyric.dart';

class _ParsedLine {
  final Duration time;
  final String text;
  const _ParsedLine({required this.time, required this.text});
}

class LyricParser {
  // 解析 LRC 格式歌词（支持翻译歌词）
  static Lyrics parseLrc(String lrc) {
    debugPrint('[LyricParser] parseLrc 开始, 长度=${lrc.length}');
    debugPrint('[LyricParser] 原始歌词前200字符: ${lrc.substring(0, lrc.length > 200 ? 200 : lrc.length)}');
    
    final lines = <LyricLine>[];
    final List<String> lineList = lrc.split('\n');
    debugPrint('[LyricParser] 总行数: ${lineList.length}');

    // 先解析所有行（包括翻译行）
    final parsedLines = <_ParsedLine>[];
    for (final line in lineList) {
      final parsed = _parseLrcLine(line);
      if (parsed != null) {
        parsedLines.add(parsed);
      }
    }
    
    debugPrint('[LyricParser] 解析成功行数: ${parsedLines.length}');

    // 按时间排序
    parsedLines.sort((a, b) => a.time.compareTo(b.time));

    // 合并翻译：相同时间戳的行，后一个作为前一个的翻译
    int i = 0;
    while (i < parsedLines.length) {
      final current = parsedLines[i];
      String? translation;

      // 检查下一行是否是翻译（相同时间戳）
      if (i + 1 < parsedLines.length &&
          parsedLines[i + 1].time == current.time &&
          parsedLines[i + 1].text != current.text) {
        translation = parsedLines[i + 1].text;
        i += 2; // 跳过翻译行
      } else {
        i++;
      }

      lines.add(LyricLine(
        time: current.time,
        text: current.text,
        translation: translation,
      ));
    }

    return Lyrics(raw: lrc, lines: lines);
  }

  // 解析单行 LRC 歌词
  static _ParsedLine? _parseLrcLine(String line) {
    // 匹配 [mm:ss.xx] 或 [mm:ss.xxx] 或 [mm:ss]
    final RegExp timeRegExp = RegExp(r'\[(\d{2}):(\d{2})\.?(\d{0,3})\]');
    final matches = timeRegExp.allMatches(line);

    if (matches.isEmpty) {
      // 非歌词行（可能是标签行或空行）
      return null;
    }

    // 提取歌词文本（去除所有时间标签）
    String text = line.replaceAll(timeRegExp, '').trim();
    
    // 移除 LRCX 格式的逐字时间标签 <数字,数字> 或 <数字,数字,数字>
    text = text.replaceAll(RegExp(r'<-?\d+,-?\d+(?:,-?\d+)?>'), '');
    
    if (text.isEmpty) {
      debugPrint('[LyricParser] 行解析后文本为空: $line');
      return null;
    }

    // 获取第一个时间标签
    final match = matches.first;
    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final millisecondsStr = match.group(3) ?? '0';
    
    // 兼容 .xx (两位毫秒) 和 .xxx (三位毫秒)
    int milliseconds;
    if (millisecondsStr.length == 2) {
      milliseconds = int.parse(millisecondsStr) * 10;
    } else if (millisecondsStr.length == 1) {
      milliseconds = int.parse(millisecondsStr) * 100;
    } else {
      milliseconds = int.parse(millisecondsStr.substring(0, 3).padRight(3, '0'));
    }

    final time = Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );

    debugPrint('[LyricParser] 解析成功: time=$time, text=$text');
    return _ParsedLine(time: time, text: text);
  }

  // 解析逐字 LRC 歌词（QRC 格式）
  static Lyrics parseQrc(String qrc) {
    final lines = <LyricLine>[];
    final List<String> lineList = qrc.split('\n');

    for (final line in lineList) {
      final parsed = _parseQrcLine(line);
      if (parsed != null) {
        lines.add(parsed);
      }
    }

    lines.sort((a, b) => a.time.compareTo(b.time));

    return Lyrics(raw: qrc, lines: lines);
  }

  // 解析单行 QRC 歌词
  static LyricLine? _parseQrcLine(String line) {
    // QRC 格式: [00:12.34]<00:12.34>逐<00:12.50>字<00:12.70>歌<00:12.90>词
    final RegExp timeRegExp = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');
    final match = timeRegExp.firstMatch(line);

    if (match == null) return null;

    final minutes = int.parse(match.group(1)!);
    final seconds = int.parse(match.group(2)!);
    final milliseconds = int.parse(match.group(3)!.padRight(3, '0'));

    final time = Duration(
      minutes: minutes,
      seconds: seconds,
      milliseconds: milliseconds,
    );

    // 提取逐字歌词
    final textPart = line.substring(match.end);
    final words = _parseQrcWords(textPart);

    if (words.isEmpty) return null;

    final text = words.map((w) => w.text).join();

    return LyricLine(time: time, text: text, words: words);
  }

  // 解析 QRC/LRCX 逐字歌词
  static List<LyricWord> _parseQrcWords(String text) {
    final words = <LyricWord>[];
    // 支持 QRC 格式 <mm:ss.xxx> 和 LRCX 格式 <mm:ss.xxx,ddd>
    final RegExp wordRegExp = RegExp(r'<(\d{2}):(\d{2})\.(\d{2,3})(?:,\d+)>([^<]*)');
    final matches = wordRegExp.allMatches(text);

    for (final match in matches) {
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final milliseconds = int.parse(match.group(3)!.padRight(3, '0'));
      final wordText = match.group(4) ?? '';

      if (wordText.isNotEmpty) {
        words.add(LyricWord(
          time: Duration(
            minutes: minutes,
            seconds: seconds,
            milliseconds: milliseconds,
          ),
          text: wordText,
        ));
      }
    }

    return words;
  }

  // 格式化时间
  static String formatTime(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
