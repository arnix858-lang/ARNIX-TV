import 'dart:convert';

import '../models/iptv.dart';
import 'catchup.dart';

enum IptvSourceFormat { inline, m3u, tvbox }

IptvSourceFormat detectSourceFormat(String source) {
  final trimmed = source.trimLeft();
  if (trimmed.startsWith('[')) return IptvSourceFormat.inline;
  if (trimmed.startsWith('#EXTM3U')) return IptvSourceFormat.m3u;
  return IptvSourceFormat.tvbox;
}

Future<List<IptvGroup>> parseM3uSource(String source) async {
  final lines = source.replaceAll('\r', '').split('\n');
  final groupList = <IptvGroup>[];
  var m3uHead = '';
  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('#EXTM3U')) {
      m3uHead = line;
      break;
    }
  }

  var channel = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (!line.startsWith('#EXTINF:')) continue;

    String? url;
    for (var j = i + 1; j < lines.length; j++) {
      final candidate = lines[j].trim();
      if (candidate.isEmpty || candidate.startsWith('#')) continue;
      url = candidate;
      i = j;
      break;
    }
    if (url == null) continue;

    final comma = line.lastIndexOf(',');
    final name = comma >= 0 && comma + 1 < line.length
        ? line.substring(comma + 1).trim()
        : 'Канал ${channel + 1}';
    final groupName =
        RegExp('group-title="(.*?)"').firstMatch(line)?.group(1) ?? 'Другие';

    final group = groupList.firstWhere(
      (it) => it.name == groupName,
      orElse: () {
        final created = IptvGroup(idx: groupList.length, name: groupName, list: []);
        groupList.add(created);
        return created;
      },
    );
    final catchupInfo = CatchupUtil.resolve(m3uHead, line);
    group.list.add(Iptv(
      idx: group.list.length,
      channel: ++channel,
      groupIdx: group.idx,
      name: name,
      url: url,
      tvgName: RegExp('tvg-name="(.*?)"').firstMatch(line)?.group(1) ?? name,
      catchup: catchupInfo.type,
      catchupSource: catchupInfo.source,
      catchupDays: catchupInfo.days,
    ));
  }
  return groupList;
}

Future<List<IptvGroup>> parseTvboxSource(String source) async {
  final groupList = <IptvGroup>[];
  final lines = source.replaceAll('\r', '').split('\n');
  var channel = 0;
  IptvGroup? group;
  for (final raw in lines) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    if (line.endsWith('#genre#')) {
      final groupName = line.split(',')[0];
      group = IptvGroup(idx: groupList.length, name: groupName, list: []);
      groupList.add(group);
      continue;
    }

    // TVBox 支持中文逗号和英文逗号作为频道名/地址分隔符
    final normalized = line.replaceAll('，', ',');
    final comma = normalized.indexOf(',');
    if (comma < 1 || group == null) continue;
    final name = normalized.substring(0, comma).trim();
    final url = normalized.substring(comma + 1).trim();
    if (url.isEmpty) continue;
    group.list.add(Iptv(
      idx: group.list.length,
      channel: ++channel,
      groupIdx: group.idx,
      name: name,
      url: url,
      tvgName: name,
    ));
  }
  return groupList;
}

Future<List<IptvGroup>> parseInlineSource(String source) async {
  final groupList = <IptvGroup>[];
  final items = jsonDecode(source) as List;
  var channel = 0;
  for (final raw in items) {
    final item = raw as Map;
    final groupName = item['grouptitle']?.toString().trim() ?? 'Другие';
    final name = item['title']?.toString().trim() ?? 'Канал';
    String? pick(List<String> keys) {
      for (final key in keys) {
        final value = item[key];
        if (value == null) continue;
        final result = value.toString().trim();
        if (result.isNotEmpty) return result;
      }
      return null;
    }

    final group = groupList.firstWhere(
      (it) => it.name == groupName,
      orElse: () {
        final created = IptvGroup(idx: groupList.length, name: groupName, list: []);
        groupList.add(created);
        return created;
      },
    );
    group.list.add(Iptv(
      idx: group.list.length,
      channel: ++channel,
      groupIdx: group.idx,
      name: name,
      url: item['url'].toString().trim(),
      tvgName: name,
      catchup: pick(['catchup', 'catchUp']) ?? '',
      catchupSource: pick(['catchupSource', 'catchupsource', 'catchup_source']) ?? '',
      catchupDays: int.tryParse(pick(['catchupDays', 'catchupdays', 'catchup_days']) ?? '1') ?? 1,
    ));
  }
  return groupList;
}

Future<List<IptvGroup>> parseIptvSource(String source) async {
  switch (detectSourceFormat(source)) {
    case IptvSourceFormat.inline:
      return parseInlineSource(source);
    case IptvSourceFormat.m3u:
      return parseM3uSource(source);
    case IptvSourceFormat.tvbox:
      return parseTvboxSource(source);
  }
}
