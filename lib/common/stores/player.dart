import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobx/mobx.dart';
import 'package:video_player/video_player.dart';

import '../models/iptv.dart';
import '../utils/logger.dart';
import '../utils/source_health.dart';

part 'player.g.dart';

class PlayerStore = PlayerStoreBase with _$PlayerStore;

enum PlayerState { waiting, playing, failed }

final _logger = LoggerUtil.create(['ExoPlayer']);

abstract class PlayerStoreBase with Store {
  @observable
  VideoPlayerController? player;

  @observable
  double? aspectRatio;

  @observable
  Size resolution = Size.zero;

  @observable
  PlayerState state = PlayerState.waiting;

  @observable
  String errorInfo = '';

  Timer? _watchdogTimer;
  Timer? _freezeTimer;
  Timer? _bufferTimer;
  VoidCallback? _onFreezeCallback;
  VoidCallback? _onErrorCallback;
  bool isSwitching = false;
  bool isPlayback = false;
  bool _disposed = false;
  bool _rendered = false;
  int _playSeq = 0;
  String currentUrl = '';
  Duration _lastPosition = Duration.zero;
  int _stalledChecks = 0;

  static Duration startWatchdogTimeout = const Duration(seconds: 15);
  static Duration freezeGraceTimeout = const Duration(seconds: 4);

  VoidCallback? onPlaybackEnd;

  void initPlayer({VoidCallback? onFreeze, VoidCallback? onError}) {
    _onFreezeCallback = onFreeze;
    _onErrorCallback = onError;
    _disposed = false;
  }

  Future<void> warmUp() async {
    // ExoPlayer is initialized per media item by video_player.
  }

  Future<void> playIptv(Iptv iptv) async {
    await _startPlay(iptv, SourceHealthUtil.pickBest(iptv.url), playback: false);
  }

  Future<void> playCatchup(Iptv source, {required String url}) async {
    await _startPlay(source, url, playback: true);
  }

  Future<void> _startPlay(Iptv iptv, String url, {required bool playback}) async {
    final seq = ++_playSeq;
    _cancelTimers();
    final old = player;
    player = null;
    if (old != null) {
      old.removeListener(_onPlayerChanged);
      await old.dispose();
    }
    if (_disposed || seq != _playSeq) return;

    currentUrl = playback ? '' : url;
    isPlayback = playback;
    _rendered = false;
    _stalledChecks = 0;
    _lastPosition = Duration.zero;
    state = PlayerState.waiting;
    errorInfo = '';

    try {
      final uri = Uri.parse(url);
      if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
        throw FormatException('Неподдерживаемый адрес потока');
      }

      final controller = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36',
        },
      );
      player = controller;
      controller.addListener(_onPlayerChanged);

      _watchdogTimer = Timer(startWatchdogTimeout, () {
        if (_disposed || seq != _playSeq || _rendered) return;
        _fail('Превышено время ожидания HLS-потока');
      });

      await controller.initialize();
      if (_disposed || seq != _playSeq) return;
      await controller.setLooping(false);
      await controller.play();
      if (_disposed || seq != _playSeq) return;

      runInAction(() {
        final size = controller.value.size;
        if (size.width > 0 && size.height > 0) {
          resolution = size;
          aspectRatio = size.width / size.height;
        }
        state = PlayerState.playing;
      });
      _watchdogTimer?.cancel();
      _startFreezeCheck(seq);
      _logger.debug('ExoPlayer запустил поток: $url');
    } catch (e) {
      if (seq == _playSeq && !_disposed) {
        _logger.warning('Ошибка ExoPlayer: $e');
        _fail(e.toString());
      }
    }
  }

  void _onPlayerChanged() {
    final controller = player;
    if (controller == null || _disposed) return;
    final value = controller.value;

    if (value.hasError) {
      _fail(value.errorDescription ?? 'Ошибка воспроизведения');
      return;
    }

    if (value.isInitialized && !_rendered && value.isPlaying) {
      _rendered = true;
      _watchdogTimer?.cancel();
      SourceHealthUtil.recordSuccess(currentUrl);
      runInAction(() {
        final size = value.size;
        if (size.width > 0 && size.height > 0) {
          resolution = size;
          aspectRatio = size.width / size.height;
        }
      });
    }

    if (value.isBuffering && _rendered && _bufferTimer == null) {
      _bufferTimer = Timer(freezeGraceTimeout, () {
        _bufferTimer = null;
        if (controller.value.isBuffering && !_disposed) {
          _onFreezeCallback?.call();
        }
      });
    } else if (!value.isBuffering) {
      _bufferTimer?.cancel();
      _bufferTimer = null;
    }

    if (value.isCompleted && isPlayback) {
      onPlaybackEnd?.call();
    }
  }

  void _startFreezeCheck(int seq) {
    _freezeTimer?.cancel();
    _freezeTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      final controller = player;
      if (_disposed || seq != _playSeq || controller == null) {
        timer.cancel();
        return;
      }
      final value = controller.value;
      if (value.hasError) {
        timer.cancel();
        _fail(value.errorDescription ?? 'Ошибка воспроизведения');
        return;
      }
      if (value.isPlaying && !value.isBuffering) {
        if (value.position == _lastPosition) {
          _stalledChecks++;
          if (_stalledChecks >= 2) {
            timer.cancel();
            _onFreezeCallback?.call();
            return;
          }
        } else {
          _stalledChecks = 0;
        }
        _lastPosition = value.position;
      }
    });
  }

  void _fail(String message) {
    if (_disposed || state == PlayerState.failed) return;
    _cancelTimers();
    state = PlayerState.failed;
    errorInfo = message;
    if (currentUrl.isNotEmpty) SourceHealthUtil.recordFailure(currentUrl);
    _onErrorCallback?.call();
  }

  void _cancelTimers() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _freezeTimer?.cancel();
    _freezeTimer = null;
    _bufferTimer?.cancel();
    _bufferTimer = null;
  }

  Future<void> reinitPlayer() async {
    _disposed = false;
    final old = player;
    player = null;
    if (old != null) {
      old.removeListener(_onPlayerChanged);
      await old.dispose();
    }
  }

  @action
  Future<void> disposePlayer() async {
    if (_disposed) return;
    _disposed = true;
    _playSeq++;
    _cancelTimers();
    final old = player;
    player = null;
    if (old != null) {
      old.removeListener(_onPlayerChanged);
      await old.dispose();
    }
    currentUrl = '';
    state = PlayerState.waiting;
    aspectRatio = null;
    resolution = Size.zero;
    isSwitching = false;
    isPlayback = false;
  }
}
