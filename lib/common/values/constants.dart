/// 常量
class Constants {
  /// 默认源服务地址
  static const defaultIptvSourceApi = '';

  /// Плейлист ARNIX TV по умолчанию
  static const defaultPlaylistUrl = 'http://cdntv.online/hls/9n3hebsjat/mpeg.m3u';

  /// 直播源缓存时间
  static const iptvSourceCacheKeepTime = 1000 * 60 * 60;

  /// epg xml
  static const iptvEpgXml = 'https://htwmedia.dpdns.org/Home/getepg';

  /// epg 刷新时间阈值（小时）
  static const epgRefreshTimeThreshold = 6;

  /// github API 获取最新 release
  static const githubReleaseApi = 'https://api.github.com/repos/arnix858-lang/ARNIX-TV/releases/latest';
  static const githubProxy = 'https://mirror.ghproxy.com/';
  static const githubReleaseLatest = 'https://github.com/arnix858-lang/ARNIX-TV/releases/latest';
  static const httpServerPort = 10381;
  static const httpRetryCount = 10;
  static const httpRetryInterval = 3000;
}
