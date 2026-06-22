import 'package:flutter_test/flutter_test.dart';
import 'package:lx_music_flutter/features/custom_source/domain/custom_source.dart';
import 'package:lx_music_flutter/features/custom_source/domain/custom_source_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CustomSourceEngine Tests', () {
    late CustomSourceEngine engine;

    setUp(() {
      engine = CustomSourceEngine();
    });

    tearDown(() {
      engine.dispose();
    });

    test('should initialize and load a basic script', () async {
      final script = r'''
        lx.on(lx.EVENT_NAMES.request, async (data) => {
          if (data.action === 'search') {
            return {
              list: [
                { songmid: '123', name: 'Test Song', singer: 'Test Singer' }
              ]
            };
          }
        });
        lx.send(lx.EVENT_NAMES.inited, { status: 'ok' });
      ''';

      final source = CustomSource(
        id: 'test',
        name: 'Test Source',
        description: 'Testing',
        version: '1.0.0',
        author: 'Test',
        script: script,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final success = await engine.loadSource(source);
      expect(success, isTrue);

      final results = await engine.search('test');
      expect(results.length, 1);
      expect(results[0].name, 'Test Song');
    });

    test('crypto and complex buffer operations', () async {
      final script = r'''
        lx.on(lx.EVENT_NAMES.request, async (data) => {
          if (data.action === 'search') {
            // Test MD5
            var hash = lx.utils.crypto.md5('hello');
            
            // Test AES (simplified mock of what a real script might do)
            var encrypted = lx.utils.crypto.aesEncrypt('test-data', 'aes-128-cbc', '1234567890123456', '1234567890123456');
            
            // Test Buffer array-like access
            var buf = lx.utils.buffer.from('abc');
            var firstChar = buf[0]; // should be 97
            
            return {
              list: [
                { 
                  songmid: hash, 
                  name: 'Enc: ' + encrypted.substring(0, 5), 
                  singer: 'Char: ' + firstChar 
                }
              ]
            };
          }
        });
        lx.send(lx.EVENT_NAMES.inited, {});
      ''';

      final source = CustomSource(
        id: 'crypto_test',
        name: 'Crypto Test',
        description: '',
        version: '1.0.0',
        author: '',
        script: script,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await engine.loadSource(source);
      final results = await engine.search('test');
      
      expect(results[0].songmid, '5d41402abc4b2a76b9719d911017c592'); // md5 of 'hello'
      expect(results[0].singer, 'Char: 97');
    });
  });
}
