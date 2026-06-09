import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../../core/models/models.dart';

class StorageService {
  static Future<String> get _localPath async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  static Future<File> _getLocalFile(String id) async {
    final path = await _localPath;
    return File('$path/chat_$id.json');
  }

  static Future<void> saveMessages(String id, List<BaseMessage> messages) async {
    try {
      final file = await _getLocalFile(id);
      final jsonList = messages.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (e) {
      print('Error saving messages for $id: $e');
    }
  }

  static Future<List<BaseMessage>> loadMessages(String id) async {
    try {
      final file = await _getLocalFile(id);
      if (!await file.exists()) return [];

      final contents = await file.readAsString();
      final List jsonList = jsonDecode(contents);
      return jsonList.map((j) => BaseMessage.fromJson(j)).toList();
    } catch (e) {
      print('Error loading messages for $id: $e');
      return [];
    }
  }

  static Future<void> clearAll() async {
    final path = await _localPath;
    final dir = Directory(path);
    final files = dir.listSync();
    for (var file in files) {
      if (file is File && file.path.contains('chat_')) {
        await file.delete();
      }
    }
  }
}
