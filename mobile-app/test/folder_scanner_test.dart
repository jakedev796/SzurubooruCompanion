import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:szuruqueue/src/models/scheduled_folder.dart';
import 'package:szuruqueue/src/services/backend_client.dart';
import 'package:szuruqueue/src/services/folder_scanner.dart';
import 'package:szuruqueue/src/services/settings_model.dart';

class FakeBackendClient extends BackendClient {
  FakeBackendClient({this.fail = false}) : super(baseUrl: 'http://localhost');

  final bool fail;
  final uploaded = <String>[];

  @override
  Future<({String? jobId, String? error})> enqueueFromFile({
    required File file,
    String? source,
    List<String>? tags,
    String? safety,
    bool? skipTagging,
  }) async {
    uploaded.add(file.path);
    if (fail) return (jobId: null, error: 'upload failed');
    return (jobId: 'job-${uploaded.length}', error: null);
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('folder_scanner_test');
  });

  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<File> mediaFile(String name, {Duration age = Duration.zero}) async {
    final file = File(path.join(dir.path, name));
    await file.writeAsBytes([0, 1, 2]);
    if (age > Duration.zero) {
      await file.setLastModified(DateTime.now().subtract(age));
    }
    return file;
  }

  Future<SettingsModel> settingsWith(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final settings = SettingsModel();
    await settings.loadSettings();
    return settings;
  }

  ScheduledFolder folder({int lastRun = 0}) => ScheduledFolder(
        id: 'f1',
        name: 'Test',
        uri: dir.path,
        intervalSeconds: 1800,
        lastRunTimestamp: lastRun,
      );

  test('skips files still awaiting deferred deletion', () async {
    final pending = await mediaFile('pending.jpg');
    final fresh = await mediaFile('fresh.jpg');
    final settings = await settingsWith({
      'deleteMediaAfterSync': true,
      'pending_upload_files': '{"job-old":"${pending.path.replaceAll(r'\', r'\\')}"}',
    });
    final client = FakeBackendClient();

    final result = await FolderScanner(backendClient: client, settings: settings)
        .processFolder(folder());

    expect(client.uploaded, [fresh.path]);
    expect(result.filesUploaded, 1);
  });

  test('does not queue failed uploads offline when the scan will retry them', () async {
    await mediaFile('a.jpg');
    final settings = await settingsWith({'deleteMediaAfterSync': true});

    await FolderScanner(
      backendClient: FakeBackendClient(fail: true),
      settings: settings,
    ).processFolder(folder());

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('offline_queue'), isNull);
  });

  test('queues failed uploads offline when mtime filtering would skip them', () async {
    await mediaFile('a.jpg');
    final settings = await settingsWith({'deleteMediaAfterSync': false});

    await FolderScanner(
      backendClient: FakeBackendClient(fail: true),
      settings: settings,
    ).processFolder(folder());

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('offline_queue'), contains('a.jpg'));
  });

  test('a file uploaded in one scan is not uploaded again by the next', () async {
    await mediaFile('a.jpg', age: const Duration(minutes: 1));
    final settings = await settingsWith({
      'deleteMediaAfterSync': false,
      'scheduled_folders': '[]',
    });
    await settings.addScheduledFolder(folder(lastRun: 1));
    final client = FakeBackendClient();
    final scanner = FolderScanner(backendClient: client, settings: settings);

    await scanner.processFolder(folder(lastRun: 1));
    final afterFirst = (await settings.getScheduledFolders()).single;
    await scanner.processFolder(afterFirst);

    expect(client.uploaded, hasLength(1));
  });
}
