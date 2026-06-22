import 'package:flutter_test/flutter_test.dart';
import 'package:lx_music_flutter/core/music_source/platform/kw_source.dart';
import 'package:lx_music_flutter/core/music_source/platform/kg_source.dart';
import 'package:lx_music_flutter/core/music_source/platform/tx_source.dart';
import 'package:lx_music_flutter/core/music_source/platform/wy_source.dart';
import 'package:lx_music_flutter/core/music_source/platform/mg_source.dart';

void main() {
  group('KwSource', () {
    late KwSource source;
    setUp(() => source = KwSource());
    tearDown(() => source.dispose());

    test('搜索', () async {
      final results = await source.search('周杰伦', page: 1, limit: 3);
      expect(results, isNotEmpty);
      print('KW 搜索: ${results.length} 条');
      final item = results.first;
      print('  首条: ${item.name} - ${item.singer} (id: ${item.id})');
    });

    test('歌词', () async {
      final results = await source.search('周杰伦', page: 1, limit: 1);
      if (results.isNotEmpty) {
        final lyric = await source.getLyric(results.first);
        if (lyric != null) {
          print('KW 歌词: ${lyric.substring(0, lyric.length > 100 ? 100 : lyric.length)}...');
        } else {
          print('KW 歌词: null');
        }
      }
    });
  });

  group('KgSource', () {
    late KgSource source;
    setUp(() => source = KgSource());
    tearDown(() => source.dispose());

    test('搜索', () async {
      final results = await source.search('周杰伦', page: 1, limit: 3);
      expect(results, isNotEmpty);
      print('KG 搜索: ${results.length} 条');
      final item = results.first;
      print('  首条: ${item.name} - ${item.singer} (id: ${item.id})');
    });

    test('歌词', () async {
      final results = await source.search('周杰伦', page: 1, limit: 1);
      if (results.isNotEmpty) {
        final lyric = await source.getLyric(results.first);
        if (lyric != null) {
          print('KG 歌词: ${lyric.substring(0, lyric.length > 100 ? 100 : lyric.length)}...');
        } else {
          print('KG 歌词: null');
        }
      }
    });
  });

  group('TxSource', () {
    late TxSource source;
    setUp(() => source = TxSource());
    tearDown(() => source.dispose());

    test('搜索', () async {
      final results = await source.search('周杰伦', page: 1, limit: 3);
      expect(results, isNotEmpty);
      print('TX 搜索: ${results.length} 条');
      final item = results.first;
      print('  首条: ${item.name} - ${item.singer} (id: ${item.id})');
    });

    test('歌词', () async {
      final results = await source.search('周杰伦', page: 1, limit: 1);
      if (results.isNotEmpty) {
        final lyric = await source.getLyric(results.first);
        if (lyric != null) {
          print('TX 歌词: ${lyric.substring(0, lyric.length > 100 ? 100 : lyric.length)}...');
        } else {
          print('TX 歌词: null');
        }
      }
    });
  });

  group('WySource', () {
    late WySource source;
    setUp(() => source = WySource());
    tearDown(() => source.dispose());

    test('搜索', () async {
      final results = await source.search('周杰伦', page: 1, limit: 3);
      expect(results, isNotEmpty);
      print('WY 搜索: ${results.length} 条');
      final item = results.first;
      print('  首条: ${item.name} - ${item.singer} (id: ${item.id})');
    });

    test('歌词', () async {
      final results = await source.search('周杰伦', page: 1, limit: 1);
      if (results.isNotEmpty) {
        final lyric = await source.getLyric(results.first);
        if (lyric != null) {
          print('WY 歌词: ${lyric.substring(0, lyric.length > 100 ? 100 : lyric.length)}...');
        } else {
          print('WY 歌词: null');
        }
      }
    });
  });

  group('MgSource', () {
    late MgSource source;
    setUp(() => source = MgSource());
    tearDown(() => source.dispose());

    test('搜索', () async {
      final results = await source.search('周杰伦', page: 1, limit: 3);
      expect(results, isNotEmpty);
      print('MG 搜索: ${results.length} 条');
      final item = results.first;
      print('  首条: ${item.name} - ${item.singer} (id: ${item.id})');
    });

    test('歌词', () async {
      final results = await source.search('周杰伦', page: 1, limit: 1);
      if (results.isNotEmpty) {
        final lyric = await source.getLyric(results.first);
        if (lyric != null) {
          print('MG 歌词: ${lyric.substring(0, lyric.length > 100 ? 100 : lyric.length)}...');
        } else {
          print('MG 歌词: null');
        }
      }
    });
  });
}