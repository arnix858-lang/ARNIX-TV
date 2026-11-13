import 'package:flutter/material.dart';

import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';
import 'package:video_player_example/common/index.dart';

class PanelIptvInfo extends StatelessWidget {
  PanelIptvInfo({this.epgShowFull = true, super.key});

  late final epgShowFull;

  final iptvStore = GetIt.I<IptvStore>();
  final playerStore = GetIt.I<PlayerStore>();

  @override
  Widget build(BuildContext context) {
    // 同一个 build 里这四个文本要用的颜色是一致的，先取一次
    final fg = AppTheme.fg(context);
    final programmeColor = AppTheme.fgFaded(context, AppTheme.oSecondary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 频道名称
            Observer(
              builder: (_) => Row(mainAxisSize: MainAxisSize.min, children: [
                if (iptvStore.currentIptv.logoUrl.isNotEmpty)
                  Padding(padding: EdgeInsets.only(right: 18.w),
                    child: Image.network(iptvStore.currentIptv.logoUrl, width: 82.w, height: 62.h, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(Icons.live_tv, color: fg, size: 48.sp))),
                Text(iptvStore.currentIptv.name, style: AppTheme.text(fg, 60.sp, weight: FontWeight.bold)),
              ]),
            ),
            SizedBox(width: 40.w),
            // 播放状态：正常时不渲染任何东西。
            // 原来放着个空 Text('')，每次 Observer 重建都要走一遍文本排版。
            Observer(
              builder: (_) {
                if (playerStore.state != PlayerState.failed) return const SizedBox.shrink();
                return Text(
                  '${playerStore.errorInfo}Ошибка воспроизведения!',
                  style: AppTheme.text(AppTheme.error(context), 20.sp, weight: FontWeight.bold),
                );
              },
            ),
            ],
        ),
        // 节目单
        Observer(
          builder: (_) => Text(
            'Сейчас: ${iptvStore.currentIptvProgrammes.current.isNotEmpty ? iptvStore.currentIptvProgrammes.current : 'Нет программы'}',
            style: AppTheme.text(programmeColor, 30.sp),
          ),
        ),
        Observer(
          builder: (_) => Text(
            'Далее: ${iptvStore.currentIptvProgrammes.next.isNotEmpty ? iptvStore.currentIptvProgrammes.next : 'Нет программы'}',
            style: AppTheme.text(programmeColor, 30.sp),
          ),
        ),
      ],
    );
  }
}
