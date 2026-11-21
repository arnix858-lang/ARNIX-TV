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
        SizedBox(height: 8.h),
        Observer(
          builder: (_) {
            final status = iptvStore.epgStatus.value;
            final String statusText;
            final Widget statusIndicator;
            switch (status) {
              case EpgLoadStatus.loading:
                statusText = 'Загрузка телепрограммы…';
                statusIndicator = SizedBox(
                  width: 17.w,
                  height: 17.w,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                );
                break;
              case EpgLoadStatus.loaded:
                statusText = 'Телепрограмма загружена';
                statusIndicator = Icon(
                  Icons.check_circle_rounded,
                  color: Colors.white,
                  size: 19.sp,
                );
                break;
              case EpgLoadStatus.failed:
                statusText = 'Ошибка загрузки телепрограммы';
                statusIndicator = Icon(
                  Icons.error_outline_rounded,
                  color: Colors.white,
                  size: 19.sp,
                );
                break;
              case EpgLoadStatus.disabled:
                statusText = 'Телепрограмма отключена';
                statusIndicator = Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                  size: 19.sp,
                );
                break;
              case EpgLoadStatus.idle:
                statusText = 'Ожидание загрузки телепрограммы';
                statusIndicator = Icon(
                  Icons.hourglass_empty_rounded,
                  color: Colors.white,
                  size: 19.sp,
                );
                break;
            }
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: Colors.white.withOpacity(0.22)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  statusIndicator,
                  SizedBox(width: 9.w),
                  Text(
                    statusText,
                    style: AppTheme.text(Colors.white, 18.sp, weight: FontWeight.w600),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
