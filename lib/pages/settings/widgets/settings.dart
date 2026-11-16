import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:video_player_example/common/index.dart';

import '../../../common/widgets/two_dimension_list_view.dart';

class SettingGroup {
  final String name;
  final List<SettingItem> items;

  SettingGroup({required this.name, required this.items});
}

class SettingItem {
  final String title;
  final String Function() value;
  final String Function() description;
  final void Function() onTap;
  final void Function()? onLongTap;

  SettingItem({
    required this.title,
    required this.value,
    required this.description,
    required this.onTap,
    this.onLongTap,
  });
}

class SettingsMain extends StatefulWidget {
  const SettingsMain({super.key});

  @override
  State<SettingsMain> createState() => _SettingsMainState();
}

class _SettingsMainState extends State<SettingsMain> {
  final iptvStore = GetIt.I<IptvStore>();
  final updateStore = GetIt.I<UpdateStore>();

  late final List<SettingItem> _settingItemList;

  String _formatDuration(int ms) {
    if (ms < 60000) {
      return '${ms ~/ 1000}сек.';
    } else if (ms < 3600000) {
      return '${ms ~/ 60000}мин.';
    } else {
      return '${ms ~/ 3600000}ч.';
    }
  }

  void _showAssignUserDialog() {
    _showTvTextEditDialog(
      title: 'Параметры пользователя',
      hint: 'Введите параметры',
      initialValue: PrefsUtil.getString('assign_user') ?? '',
      maxWidth: 500,
      fontSize: 16,
      onSave: (value) {
        PrefsUtil.setString('assign_user', value);
        IptvSettings.iptvSourceCacheTime = 0;
        iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
      },
    );
  }

  /// 电视端文本编辑弹窗
  ///
  /// Flutter 的按键分发顺序是「叶子节点 → 根」(focus_manager.dart:1995)，
  /// 而 EditableText 在最内层就把上下方向键映射成了光标移动
  /// (editable_text.dart:4835)。输入框一旦拿到焦点，外层 Focus 便再也收不到方向键，
  /// 「保存」按钮因此不可达；电视端又没有输入法，onSubmitted 同样不会触发。
  /// 所以改由容器层统一托管按键：方向键在各元素间移动焦点，OK 键执行当前元素。
  /// 具体实现对所有文本文件复用同一份，见 TvTextEditDialog。
  void _showTvTextEditDialog({
    required String title,
    required String hint,
    required String initialValue,
    required ValueChanged<String> onSave,
    String? subtitle,
    List<TvDialogButton> extraButtons = const <TvDialogButton>[],
    double maxWidth = 500,
    double fontSize = 24,
  }) {
    showDialog(
      context: context,
      builder: (_) => TvTextEditDialog(
        title: title,
        subtitle: subtitle,
        hint: hint,
        initialValue: initialValue,
        onSave: onSave,
        extraButtons: extraButtons,
        maxWidth: maxWidth,
        fontSize: fontSize,
      ),
    );
  }

  void _showChannelSelectDialog() async {
    final allChannels = await IptvUtil.getAllChannelNames();
    if (!mounted) return;
    if (allChannels.isEmpty) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Нет доступных каналов. Сначала загрузите плейлист')));
      return;
    }

    final initialSelected = Set<String>.from(IptvSettings.allowedChannels.isNotEmpty
        ? IptvSettings.allowedChannels
        : allChannels.where((n) => n.toLowerCase().startsWith('cctv') || n.endsWith('卫视')));

    final result = await ChannelSelectDialog.show(
      context,
      allChannels: allChannels,
      selected: initialSelected,
    );

    if (result != null && mounted) {
      IptvSettings.allowedChannels = result.toList();
      IptvSettings.iptvSourceSimplify = true;
      IptvSettings.epgCacheHash = 0;
      iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
    }
  }

  void _showCustomSourceDialog() {
    _showTvTextEditDialog(
      title: 'Пользовательский плейлист',
      subtitle: 'Поддерживаются ссылки M3U и TVBox. Отсканируйте QR-код телефоном для настройки',
      hint: 'Введите ссылку на плейлист',
      initialValue: IptvSettings.customIptvSource,
      maxWidth: 700,
      fontSize: 24,
      extraButtons: [
        TvDialogButton(label: 'QR-код', onPressed: _showServerQrcode),
      ],
      onSave: (value) {
        IptvSettings.customIptvSource = value.trim();
        IptvSettings.iptvSourceSimplify = false;
        IptvSettings.iptvSourceCacheTime = 0;
        IptvSettings.epgCacheHash = 0;
        iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
      },
    );
  }

  /// Сервис источников地址
  ///
  /// 壳源分离的关键入口：把写死的服务端地址变成可配置项。
  /// 留空 = 停用内置源，App 退化为纯播放器，只加载用户自己的订阅。
  void _showDefaultApiDialog() {
    _showTvTextEditDialog(
      title: 'Сервис источников',
      subtitle: '留空表示停用内置源，届时只加载「Пользовательский плейлист」里填写的订阅',
      hint: 'Введите адрес API',
      initialValue: IptvSettings.defaultIptvSourceApi,
      maxWidth: 700,
      fontSize: 20,
      onSave: (value) {
        IptvSettings.defaultIptvSourceApi = value.trim();
        IptvSettings.epgCacheHash = 0;
        iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
      },
    );
  }

  void _showServerQrcode() {
    final fg = AppTheme.fg(context);
    NavigatorUtil.push(
      context,
      TvModalScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '扫描QR-код设置',
                style: AppTheme.text(fg, 36.sp),
              ),
              SizedBox(height: 12.h),
              Text(
                HttpServerUtil.serverUrl,
                style: AppTheme.text(AppTheme.fgFaded(context, 0.7), 24.sp),
              ),
              SizedBox(height: 24.h),
              Container(
                decoration: BoxDecoration(
                  color: fg,
                  borderRadius: BorderRadius.circular(20).r,
                ),
                padding: const EdgeInsets.all(8),
                child: SizedBox(
                  height: 300.h,
                  width: 300.h,
                  child: PrettyQrView.data(
                    data: HttpServerUtil.serverUrl,
                    decoration: PrettyQrDecoration(
                      shape: PrettyQrSmoothSymbol(
                        color: AppTheme.bg(context),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 24.h),
              Text(
                'Нажмите вне окна или ESC, чтобы вернуться',
                style: AppTheme.text(AppTheme.fgFaded(context, 0.5), 20.sp),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Сообщество и обратная связь：展示 QQ 群QR-код
  ///
  /// 用内置图片资产而不是 qm.qq.com 的加群链接再生成QR-код——
  /// 那种链接带时效 key，会过期；官方生成的群QR-код图最稳。
  void _showCommunityQrcode() {
    final fg = AppTheme.fg(context);
    NavigatorUtil.push(
      context,
      TvModalScaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Отсканируйте QR-код, чтобы вступить в группу',
                style: AppTheme.text(fg, 36.sp),
              ),
              SizedBox(height: 12.h),
              Text(
                'Сообщения о неработающих каналах, вопросы и обсуждение приложения',
                style: AppTheme.text(AppTheme.fgFaded(context, 0.7), 24.sp),
              ),
              SizedBox(height: 24.h),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _groupQrCard('assets/images/qq-group1.jpg', 'Группа 1: 2166024531'),
                  SizedBox(width: 48.w),
                  _groupQrCard('assets/images/qq-group2.jpg', 'Группа 2: 1067526818'),
                ],
              ),
              SizedBox(height: 24.h),
              Text(
                'Нажмите вне окна или ESC, чтобы вернуться',
                style: AppTheme.text(AppTheme.fgFaded(context, 0.5), 20.sp),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupQrCard(String asset, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16).r,
          child: Image.asset(
            asset,
            height: 340.h,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(height: 12.h),
        Text(
          label,
          style: AppTheme.text(AppTheme.fg(context), 26.sp),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    refreshSettingGroupList();

    // 同样要判 mounted：init 是异步的，用户可能在服务起来前就退出了设置页
    HttpServerUtil.init().then((_) { if (mounted) setState(() {}); });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
        height: 190.w + 20.h,
        child: TwoDimensionListView(
        size: (rowHeight: 190.w, colWidth: 400.w),
        scrollOffset: (row: 0, col: -1),
        gap: (row: 20.h, col: 20.w),
        itemCount: (
        row: 1,
        col: (_) => _settingItemList.length,
        ),
        onSelect: (position) => setState(() {
          _settingItemList.elementAtOrNull(position.col)?.onTap();
        }),
        onLongSelect: (position) => setState(() {
          _settingItemList.elementAtOrNull(position.col)?.onLongTap?.call();
        }),
        itemBuilder: (context, position, isSelected) {
          final item = _settingItemList[position.col];

          return _buildSettingItem(item, isSelected);
        },
      ),
    );
  }

  Widget _buildSettingItem(SettingItem item, bool isSelected) {
    final textColor = AppTheme.tileText(context, isSelected);

    return Container(
      padding: const EdgeInsets.all(30).r,
      decoration: BoxDecoration(
        color: isSelected
            ? AppTheme.fg(context)
            : AppTheme.bgFaded(context, 0.8),
        borderRadius: BorderRadius.circular(20).r,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                item.title,
                style: AppTheme.text(textColor, 30.sp),
              ),
              Text(
                item.value(),
                style: AppTheme.text(textColor, 30.sp),
              ),
            ],
          ),
          Text(
            item.description(),
            style: AppTheme.text(textColor, 24.sp),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          )
        ],
      ),
    );
  }

  void refreshSettingGroupList() {
    final groupList = [
      SettingGroup(name: 'Приложение', items: [
        SettingItem(
          title: 'Параметры пользователя',
          value: () {
            final v = PrefsUtil.getString('assign_user') ?? '';
            return v.length > 8 ? '${v.substring(0, 8)}...' : v;
          },
          description: () => 'Нажмите, чтобы изменить',
          onTap: () => _showAssignUserDialog(),
        ),
        SettingItem(
          title: 'Автозапуск',
          value: () => AppSettings.bootLaunch ? 'Включено' : 'Выключено',
          description: () => 'Вступит в силу после перезапуска',
          onTap: () {
            AppSettings.bootLaunch = !AppSettings.bootLaunch;
            // 这类开关不走网络请求，没有异步回调替我们刷新，
            // 少了这句点击后界面纹丝不动，用户会以为没点上。
            setState(() {});
          },
        ),
      ]),
      SettingGroup(name: 'Управление', items: [
        SettingItem(
          title: 'Обратное переключение каналов',
          value: () => IptvSettings.channelChangeFlip ? 'Обратный порядок' : 'Обычный порядок',
          description: () => IptvSettings.channelChangeFlip ? 'Вверх: следующий канал\nВниз: предыдущий канал' : 'Вверх: предыдущий канал\nВниз: следующий канал',
          onTap: () {
            IptvSettings.channelChangeFlip = !IptvSettings.channelChangeFlip;
            // 同「Автозапуск」：纯开关，靠手动 rebuild 让同一个 item 重新求值 value/description
            setState(() {});
          },
        ),
      ]),
      SettingGroup(name: 'Источники каналов', items: [
        SettingItem(
          title: 'Сервис источников',
          value: () {
            final api = IptvSettings.defaultIptvSourceApi;
            if (api.isEmpty) return 'Отключено';
            return api.length > 28 ? '${api.substring(0, 28)}...' : api;
          },
          description: () => IptvSettings.defaultIptvSourceApi.isEmpty
              ? 'Сейчас загружается только пользовательский плейлист. Нажмите для настройки, удерживайте для сброса'
              : 'Нажмите, чтобы изменить адрес сервиса (пустое поле отключает встроенный источник)',
          onTap: () => _showDefaultApiDialog(),
          onLongTap: () {
            IptvSettings.defaultIptvSourceApi = Constants.defaultIptvSourceApi;
            IptvSettings.epgCacheHash = 0;
            iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: 'Источники каналов精简',
          value: () {
            if (!IptvSettings.iptvSourceSimplify) return 'Выключено';
            final count = IptvSettings.allowedChannels.length;
            return count > 0 ? 'Включено ($count каналов)' : 'Включено';
          },
          description: () {
            if (!IptvSettings.iptvSourceSimplify) return '显示完整Источники каналов';
            final count = IptvSettings.allowedChannels.length;
            if (count > 0) return 'Показывать только выбранные каналы; нажмите для настройки';
            return 'Показывать сокращённый список (федеральные и региональные каналы)';
          },
          onTap: () {
            if (IptvSettings.iptvSourceSimplify) {
              _showChannelSelectDialog();
            } else {
              IptvSettings.iptvSourceSimplify = true;
              IptvSettings.epgCacheHash = 0;
              iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
            }
          },
          onLongTap: () {
            if (!IptvSettings.iptvSourceSimplify) return;
            IptvSettings.iptvSourceSimplify = false;
            IptvSettings.epgCacheHash = 0;
            iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: 'Пользовательский плейлист',
          value: () => IptvSettings.customIptvSource.isNotEmpty ? '已Включено' : '未Включено',
          description: () {
            if (IptvSettings.customIptvSource.isEmpty) return 'Нажмите, чтобы указать ссылку на плейлист';
            final src = IptvSettings.customIptvSource;
            return src.length > 35 ? '${src.substring(0, 35)}...' : src;
          },
          onTap: () => _showCustomSourceDialog(),
          onLongTap: () {
            IptvSettings.customIptvSource = '';
            IptvSettings.iptvSourceCacheTime = 0;
            IptvSettings.epgCacheHash = 0;
            iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: 'Источники каналов缓存',
          value: () => _formatDuration(IptvSettings.iptvSourceCacheKeepTime),
          description: () => IptvSettings.iptvSourceCacheTime > 0 ? "Кэш сохранён (нажмите, чтобы очистить)" : "Кэш отсутствует",
          onTap: () {
            if (IptvSettings.iptvSourceCacheTime > 0) {
              IptvSettings.iptvSourceCacheTime = 0;
              iptvStore.refreshIptvList().then((_) { if (mounted) setState(() {}); });
            }
          },
        ),
      ]),
      SettingGroup(name: 'Телепрограмма', items: [
        SettingItem(
          title: 'Телепрограмма',
          value: () => IptvSettings.epgEnable ? 'Включено' : 'Выключено',
          description: () => 'При первой загрузке возможны кратковременные пропуски кадров',
          onTap: () {
            IptvSettings.epgEnable = !IptvSettings.epgEnable;
            iptvStore.refreshEpgList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: '自定义Телепрограмма',
          value: () => IptvSettings.customEpgXml.isNotEmpty ? '已Включено' : '未Включено',
          description: () => IptvSettings.customEpgXml.isNotEmpty ? 'Удерживайте, чтобы восстановить настройки по умолчанию' : 'Нажмите, чтобы показать QR-код адреса',
          onTap: () => _showServerQrcode(),
          onLongTap: () {
            IptvSettings.customEpgXml = '';
            IptvSettings.epgXmlCacheTime = 0;
            IptvSettings.epgCacheHash = 0;
            iptvStore.refreshEpgList().then((_) { if (mounted) setState(() {}); });
          },
        ),
        SettingItem(
          title: 'Телепрограмма缓存',
          value: () => 'Сегодня',
          description: () => IptvSettings.epgXmlCacheTime > 0 ? "Кэш сохранён (нажмите, чтобы очистить)" : "Кэш отсутствует",
          onTap: () {
            if (IptvSettings.epgXmlCacheTime > 0) {
              IptvSettings.epgXmlCacheTime = 0;
              IptvSettings.epgCacheHash = 0;
              iptvStore.refreshEpgList().then((_) { if (mounted) setState(() {}); });
            }
          },
        ),
        SettingItem(
          title: 'Проверка архива',
          value: () => 'Смещение ${IptvSettings.catchupUtcOffsetHours} ч',
          description: () => 'Проверить доступность архива для текущего канала; удерживайте, чтобы изменить часовой пояс',
          onTap: () => _runCatchupProbe(),
          onLongTap: () {
            IptvSettings.catchupUtcOffsetHours =
                IptvSettings.catchupUtcOffsetHours == 8 ? 0 : 8;
            setState(() {});
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(SnackBar(
                content: Text('Смещение часового пояса архива изменено: ${IptvSettings.catchupUtcOffsetHours} ч'),
                duration: const Duration(seconds: 2),
              ));
          },
        ),
      ]),
      SettingGroup(name: 'Сообщество и обратная связь', items: [
        SettingItem(
          title: 'Группы QQ',
          value: () => '2166024531 / 1067526818',
          description: () => 'Сообщения о неработающих каналах и помощь. Нажмите, чтобы открыть QR-код',
          onTap: () => _showCommunityQrcode(),
        ),
        SettingItem(
          title: 'Сообщить о проблеме',
          value: () => '',
          description: () => 'Также можно оставить сообщение в GitHub Discussions',
          onTap: () {
            _showProbeResult(
              'GitHub Discussions',
              'github.com/arnix858-lang/ARNIX-TV → Обсуждения\nВ сообщении укажите канал, описание проблемы, регион/сеть и версию приложения',
            );
          },
        ),
      ]),
      SettingGroup(name: 'Дополнительно', items: [
        SettingItem(
          title: 'Дополнительно设置',
          value: () => '',
          description: () => 'Откройте адрес для настройки: ${HttpServerUtil.serverUrl}',
          onTap: () => _showServerQrcode(),
        ),
      ]),
    ];

    _settingItemList = groupList.expand((element) => element.items).toList();
  }

  void _showProbeResult(String title, String detail) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text('$title\n$detail'),
        duration: const Duration(seconds: 6),
      ));
  }

  /// 拉取播放列表正文（原始字节），用于回看与直播逐字节比对
  Future<({int status, List<int> bytes})> _fetchPlaylist(String url) async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
      final req =
          await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 10));
      final resp = await req.close().timeout(const Duration(seconds: 10));
      final bytes = <int>[];
      await resp.forEach(bytes.addAll);
      return (status: resp.statusCode, bytes: bytes);
    } catch (e) {
      return (status: -1, bytes: const <int>[]);
    } finally {
      client?.close(force: true);
    }
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 源类型说明，用来解释"Почему архив этого канала недоступен"
  ///
  /// 这几条都是实测结论：给地址追加回看参数后，服务端返回的播放列表
  /// 与直播逐字节相同，即参数被直接忽略。
  String _sourceKind(Iptv iptv) {
    final url = iptv.url.split(';').first.trim().toLowerCase();
    if (url.isEmpty) return 'Адрес потока пуст';
    if (url.contains('key=txiptv') || url.contains('/tsfile/live/')) {
      return 'Публичный поток оператора (txiptv): параметр playseek не поддерживается';
    }
    if (url.contains('cctvnews.cctv.com')) {
      return 'Официальный HLS: параметр lbacks не поддерживается';
    }
    return 'Обычный поток без поддержки архива на стороне сервера';
  }

  /// 回看能力探测
  ///
  /// 先确认源是否声明了 catchup，再用最近一个已播完的节目拼地址。
  /// 关键一步是**与直播地址逐字节比对**：很多服务端只是忽略未知参数、
  /// 照样返回直播列表，那时"HTTP 200"是假象，放出来的还是直播流。
  Future<void> _runCatchupProbe() async {
    final playerStore = GetIt.I<PlayerStore>();
    final iptv = iptvStore.currentIptv;

    if (!iptv.supportCatchup) {
      _showProbeResult(
        'Архив недоступен',
        '${iptv.name}：${_sourceKind(iptv)}\nВ плейлисте нет параметра catchup, приложение не может сформировать ссылку архива',
      );
      return;
    }

    final programmes = iptvStore.getProgrammes(iptv);
    final target = CatchupUtil.pickProbeProgramme(programmes);
    if (target == null) {
      _showProbeResult(
        'Нет программ для просмотра в архиве',
        programmes.isEmpty ? 'В EPG нет данных для ${iptv.name}' : 'У ${iptv.name} сегодня нет завершённых программ',
      );
      return;
    }

    final urls =
        CatchupUtil.buildUrls(iptv, startMs: target.start, stopMs: target.stop);
    LoggerUtil.debug('Кандидаты ссылок архива: ${urls.join('  |  ')}');
    if (urls.isEmpty) {
      _showProbeResult('Не удалось сформировать ссылку архива', 'Шаблон catchup для ${iptv.name} пуст');
      return;
    }

    final liveUrl = iptv.url.split(';').first.trim();
    final live = await _fetchPlaylist(liveUrl);

    String? playUrl;
    final report = <String>[];
    for (final url in urls) {
      final r = await _fetchPlaylist(url);
      if (r.status < 0) {
        report.add('Ошибка запроса (тайм-аут или сервер недоступен)');
        continue;
      }
      if (r.status >= 400) {
        report.add('HTTP ${r.status}');
        continue;
      }
      if (live.status >= 0 && live.bytes.isNotEmpty && _sameBytes(live.bytes, r.bytes)) {
        report.add('HTTP ${r.status}, содержимое совпадает с прямым эфиром — параметры проигнорированы');
        continue;
      }
      report.add('HTTP ${r.status}, содержимое отличается от прямого эфира — возможно, это запись');
      playUrl ??= url;
    }

    if (playUrl == null) {
      _showProbeResult('Архив не работает', '《${target.title}》\n${report.join('\n')}');
      return;
    }

    await playerStore.playCatchup(iptv, url: playUrl);
    _showProbeResult(
      'Начато воспроизведение архива «${target.title}»',
      'Нажмите «Назад» для просмотра. Если идёт прямой эфир вместо записи, измените часовой пояс',
    );
  }
}
