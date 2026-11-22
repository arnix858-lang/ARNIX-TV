import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player_example/common/index.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

final _logger = LoggerUtil.create(['epg']);

/// 节目单工具
class EpgUtil {
  EpgUtil._();

  /// 获取远程epg xml
  static Future<String> _fetchXml(String url) async {
    _logger.debug('Загрузка XMLTV: $url');
    return RequestUtil.get(url, timeout: const Duration(minutes: 2));
  }

  static List<String> _sourceUrls() {
    final urls = <String>[];
    final playlistUrl = IptvSettings.customEpgXml.trim();
    if (playlistUrl.isNotEmpty) urls.add(playlistUrl);
    if (!urls.contains(Constants.iptvEpgXml)) urls.add(Constants.iptvEpgXml);
    return urls;
  }

  static int _cacheHash(List<String> channels) {
    final values = <String>[...channels, ..._sourceUrls()];
    return values.map((value) => value.hashCode).fold(0, (a, b) => a ^ b);
  }

  /// 获取缓存epg xml文件
  static Future<File> _getCacheXmlFile() async {
    return File('${(await getTemporaryDirectory()).path}/epg.xml');
  }

  /// 获取缓存epg xml
  static Future<String?> _getCacheXml() async {
    try {
      final cacheFile = await _getCacheXmlFile();
      if (await cacheFile.exists()) {
        return await cacheFile.readAsString();
      }

      return null;
    } catch (e, st) {
      _logger.handle(e, st);
      return null;
    }
  }


  /// 解析epg
  static Future<List<Epg>> _parseFromXml(String xml, List<String> filteredChannels) async {
    _logger.debug('开始解析epg');
    final startAt = DateTime.now().millisecondsSinceEpoch;

    try {
      final epgList = await compute(_parseEpgInIsolate, [xml, filteredChannels]);

      _logger.debug('解析epg完成，共${epgList.length}个频道，耗时：${DateTime.now().millisecondsSinceEpoch - startAt}ms');
      return epgList;
    } catch (e, st) {
      _logger.handle(e, st);
      return [];
    }
  }

  /// 获取缓存文件
  static Future<File> _getCacheFile() async {
    return File('${(await getTemporaryDirectory()).path}/epg.json');
  }

  /// 获取缓存epg
  static Future<List<Epg>?> _getCache() async {
    try {
      final cacheFile = await _getCacheFile();
      if (await cacheFile.exists()) {
        final str = await cacheFile.readAsString();
        List<dynamic> jsonList = jsonDecode(str);
        return jsonList.map((e) => Epg.fromJson(e)).toList();
      }

      return null;
    } catch (e, st) {
      _logger.handle(e, st);
      return null;
    }
  }

  /// 仅从缓存获取epg（无网络请求）
  static Future<List<Epg>?> getCachedOnly(List<String> filteredChannels) async {
    if (!IptvSettings.epgEnable) return null;
    if (filteredChannels.isEmpty) return null;

    final hashcode = _cacheHash(filteredChannels);
    if (IptvSettings.epgCacheHash == hashcode) {
      return await _getCache();
    }
    return null;
  }

  /// 刷新并获取epg
  static Future<List<Epg>> refreshAndGet(List<String> filteredChannels) async {
    if (!IptvSettings.epgEnable || filteredChannels.isEmpty) return [];

    final hashcode = _cacheHash(filteredChannels);
    final merged = <String, Map<String, EpgProgramme>>{};
    var successfulSources = 0;

    // Загружаем EPG из заголовка пользовательского M3U и из встроенного источника.
    // Данные объединяются по XMLTV channel id, поэтому один источник дополняет другой.
    for (final url in _sourceUrls()) {
      try {
        final xml = await _fetchXml(url);
        if (xml.isEmpty) {
          _logger.warning('Источник EPG вернул пустой ответ: $url');
          continue;
        }
        final parsed = await _parseFromXml(xml, filteredChannels);
        successfulSources++;
        for (final epg in parsed) {
          final programmes = merged.putIfAbsent(epg.channel, () => <String, EpgProgramme>{});
          for (final programme in epg.programmes) {
            final key = '${programme.start}|${programme.stop}|${programme.title}';
            programmes[key] = programme;
          }
        }
        _logger.debug('Источник $url: найдено каналов ${parsed.length}');
      } catch (e, st) {
        _logger.handle(e, st);
      }
    }

    final epgList = merged.entries.map((entry) {
      final programmes = entry.value.values.toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      return Epg(channel: entry.key, programmes: programmes);
    }).where((epg) => epg.programmes.isNotEmpty).toList();

    if (epgList.isEmpty && successfulSources == 0) {
      final cache = await _getCache();
      if (cache != null && cache.isNotEmpty) return cache;
      return [];
    }

    final cacheFile = await _getCacheFile();
    await cacheFile.writeAsString(jsonEncode(epgList.map((e) => e.toJson()).toList()));
    IptvSettings.epgCacheHash = hashcode;
    IptvSettings.epgXmlCacheTime = DateTime.now().millisecondsSinceEpoch;
    IptvSettings.epgXmlCacheSource = _sourceUrls().join('|');
    return epgList;
  }
}

/// compute 要求的顶层函数，在 isolate 中解析 EPG XML
List<Epg> _parseEpgInIsolate(List<dynamic> message) {
  final xml = message[0] as String;
  final filteredChannels = message[1] as List<String>;

  int parseTime(String? value) {
    if (value == null) return 0;
    // XMLTV: yyyyMMddHHmmss +0300 (или без смещения).
    final match = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\s*([+-])(\d{2})(\d{2})?)?').firstMatch(value.trim());
    if (match == null) return 0;
    final date = DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6)!),
    );
    final sign = match.group(7) == '-' ? -1 : 1;
    final offsetHours = int.tryParse(match.group(8) ?? '0') ?? 0;
    final offsetMinutes = int.tryParse(match.group(9) ?? '0') ?? 0;
    final offset = Duration(hours: offsetHours, minutes: offsetMinutes) * sign;
    return date.subtract(offset).millisecondsSinceEpoch;
  }

  final doc = XmlDocument.parse(xml);
  final tv = doc.getElement('tv');
  if (tv == null) return [];

  final channelKeys = filteredChannels
      .map((value) => value.trim().toLowerCase())
      .where((value) => value.isNotEmpty)
      .toSet();
  final epgMap = <String, Epg>{};

  // Сначала читаем описание каналов и сопоставляем tvg-id с XMLTV id.
  for (final element in tv.findElements('channel')) {
    final id = element.getAttribute('id')?.trim();
    if (id == null || id.isEmpty) continue;
    final names = element.findElements('display-name')
        .map((node) => node.innerText.trim())
        .where((name) => name.isNotEmpty)
        .toList();
    final matched = channelKeys.contains(id.toLowerCase()) ||
        names.any((name) => channelKeys.contains(name.toLowerCase()));
    if (!matched) continue;
    epgMap[id] = Epg(channel: id, programmes: []);
  }

  // Затем добавляем передачи. В отличие от старого парсера, не зависим
  // от порядка элементов в XML и используем именно XMLTV channel id.
  for (final element in tv.findElements('programme')) {
    final channelId = element.getAttribute('channel')?.trim();
    if (channelId == null || !epgMap.containsKey(channelId)) continue;
    final start = parseTime(element.getAttribute('start'));
    final stop = parseTime(element.getAttribute('stop'));
    final title = element.getElement('title')?.innerText.trim() ?? '';
    if (start == 0 || stop <= start || title.isEmpty) continue;
    epgMap[channelId]!.programmes.add(
      EpgProgramme(start: start, stop: stop, title: title),
    );
  }

  for (final epg in epgMap.values) {
    epg.programmes.sort((a, b) => a.start.compareTo(b.start));
  }
  return epgMap.values.where((epg) => epg.programmes.isNotEmpty).toList();
}
