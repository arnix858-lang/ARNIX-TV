// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'player.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

mixin _$PlayerStore on PlayerStoreBase, Store {
  late final _$playerAtom = Atom(name: 'PlayerStoreBase.player', context: context);
  @override
  VideoPlayerController? get player {
    _$playerAtom.reportRead();
    return super.player;
  }
  @override
  set player(VideoPlayerController? value) {
    _$playerAtom.reportWrite(value, super.player, () { super.player = value; });
  }

  late final _$aspectRatioAtom = Atom(name: 'PlayerStoreBase.aspectRatio', context: context);
  @override
  double? get aspectRatio {
    _$aspectRatioAtom.reportRead();
    return super.aspectRatio;
  }
  @override
  set aspectRatio(double? value) {
    _$aspectRatioAtom.reportWrite(value, super.aspectRatio, () { super.aspectRatio = value; });
  }

  late final _$resolutionAtom = Atom(name: 'PlayerStoreBase.resolution', context: context);
  @override
  Size get resolution {
    _$resolutionAtom.reportRead();
    return super.resolution;
  }
  @override
  set resolution(Size value) {
    _$resolutionAtom.reportWrite(value, super.resolution, () { super.resolution = value; });
  }

  late final _$stateAtom = Atom(name: 'PlayerStoreBase.state', context: context);
  @override
  PlayerState get state {
    _$stateAtom.reportRead();
    return super.state;
  }
  @override
  set state(PlayerState value) {
    _$stateAtom.reportWrite(value, super.state, () { super.state = value; });
  }

  late final _$playIptvAsyncAction = AsyncAction('PlayerStoreBase.playIptv', context: context);
  @override
  Future<void> playIptv(Iptv iptv) => _$playIptvAsyncAction.run(() => super.playIptv(iptv));

  @override
  String toString() => 'player: ${player}, aspectRatio: ${aspectRatio}, resolution: ${resolution}, state: ${state}';
}
