/// 常量
class Constants {
  /// 默认源服务地址
  static const defaultIptvSourceApi = '';

  /// 直播源缓存时间
  static const iptvSourceCacheKeepTime = 1000 * 60 * 60;

  /// Основной XMLTV источник IPTVX (обычный XML).
  static const iptvEpgXml = 'https://iptvx.one/EPG';

  /// Резервный сжатый XMLTV источник IPTVX.
  static const iptvEpgXmlGzip = 'https://iptvx.one/epg/epg.xml.gz';

  /// Облегчённый резервный XMLTV источник IPTVX.
  static const iptvEpgXmlLite = 'https://iptvx.one/EPG_LITE';

  /// epg刷新时间阈值（小时）
  static const epgRefreshTimeThreshold = 6;

  /// github API 获取最新 release
  static const githubReleaseApi = 'https://api.github.com/repos/arnix858-lang/ARNIX-TV/releases/latest';
  static const githubProxy = 'https://mirror.ghproxy.com/';
  static const githubReleaseLatest = 'https://github.com/arnix858-lang/ARNIX-TV/releases/latest';
  static const httpServerPort = 10381;
  static const httpRetryCount = 10;
  static const httpRetryInterval = 3000;
}
