class LyricLine {
  final Duration time;
  final String text;
  final String? translation;
  final List<LyricWord>? words;

  const LyricLine({
    required this.time,
    required this.text,
    this.translation,
    this.words,
  });
}

class LyricWord {
  final Duration time;
  final String text;

  const LyricWord({
    required this.time,
    required this.text,
  });
}

class Lyrics {
  final String raw;
  final List<LyricLine> lines;

  const Lyrics({
    required this.raw,
    required this.lines,
  });

  factory Lyrics.empty() => const Lyrics(raw: '', lines: []);

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  // 根据当前播放位置获取当前行索引
  int getCurrentLineIndex(Duration position) {
    if (lines.isEmpty) return -1;
    
    // 二分查找优化
    int low = 0;
    int high = lines.length - 1;
    
    while (low <= high) {
      int mid = (low + high) ~/ 2;
      if (lines[mid].time <= position) {
        if (mid == lines.length - 1 || lines[mid + 1].time > position) {
          return mid;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    
    return 0;
  }

  // 获取当前行
  LyricLine? getCurrentLine(Duration position) {
    final index = getCurrentLineIndex(position);
    if (index >= 0 && index < lines.length) {
      return lines[index];
    }
    return null;
  }
}
