import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_example/common/index.dart';

void main() {
  test('ExoPlayer store starts without a native player', () async {
    final store = PlayerStore();
    expect(store.player, isNull);
    expect(store.state, PlayerState.waiting);
    await store.disposePlayer();
    expect(store.player, isNull);
  });

  test('player can be reinitialized after disposal', () async {
    final store = PlayerStore();
    await store.disposePlayer();
    await store.reinitPlayer();
    expect(store.state, PlayerState.waiting);
    await store.disposePlayer();
  });
}
