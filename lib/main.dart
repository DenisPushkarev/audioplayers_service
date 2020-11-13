import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(new MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Audio Service Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: AudioServiceWidget(child: MainScreen()),
    );
  }
}

class MainScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Audio Service Demo'),
      ),
      body: Center(
        child: StreamBuilder<bool>(
          stream: AudioService.runningStream,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.active) {
              // Don't show anything until we've ascertained whether or not the
              // service is running, since we want to show a different UI in
              // each case.
              return SizedBox();
            }
            final running = snapshot.data ?? false;
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!running) ...[
                  // UI to show when we're not running, i.e. a menu.
                  audioPlayerButton(),
                ] else ...[
                  // UI to show when we're running, i.e. player state/controls.
                  // Play/pause/stop buttons.
                  StreamBuilder<bool>(
                    stream: AudioService.playbackStateStream
                        .map((state) => state.playing)
                        .distinct(),
                    builder: (context, snapshot) {
                      final playing = snapshot.data ?? false;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (playing) pauseButton() else playButton(),
                          stopButton(),
                        ],
                      );
                    },
                  ),
                  // Display the processing state.
                  StreamBuilder<AudioProcessingState>(
                    stream: AudioService.playbackStateStream
                        .map((state) => state.processingState)
                        .distinct(),
                    builder: (context, snapshot) {
                      final processingState =
                          snapshot.data ?? AudioProcessingState.none;
                      return Text(
                          "Processing state: ${describeEnum(processingState)}");
                    },
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  RaisedButton audioPlayerButton() => startButton(
        'AudioPlayer',
        () {
          AudioService.start(
            backgroundTaskEntrypoint: _audioPlayerTaskEntrypoint,
            androidNotificationChannelName: 'Audio Service Demo',
            // Enable this if you want the Android service to exit the foreground state on pause.
            //androidStopForegroundOnPause: true,
            androidNotificationColor: 0xFF2196f3,
            androidNotificationIcon: 'mipmap/ic_launcher',
          );
        },
      );

  RaisedButton startButton(String label, VoidCallback onPressed) =>
      RaisedButton(
        child: Text(label),
        onPressed: onPressed,
      );

  IconButton playButton() => IconButton(
        icon: Icon(Icons.play_arrow),
        iconSize: 64.0,
        onPressed: AudioService.play,
      );

  IconButton pauseButton() => IconButton(
        icon: Icon(Icons.pause),
        iconSize: 64.0,
        onPressed: AudioService.pause,
      );

  IconButton stopButton() => IconButton(
        icon: Icon(Icons.stop),
        iconSize: 64.0,
        onPressed: AudioService.stop,
      );
}

// NOTE: Your entrypoint MUST be a top-level function.
void _audioPlayerTaskEntrypoint() async {
  AudioServiceBackground.run(() => AudioPlayerTask());
}

/// This task defines logic for playing a list of podcast episodes.
class AudioPlayerTask extends BackgroundAudioTask {
  AudioPlayer _player = new AudioPlayer();
  AudioPlayerState _playerState = AudioPlayerState.STOPPED;
  MediaItem mediaItem = MediaItem(
    id: "http://159.8.16.16:7074/stream.mp3",
    album: "Some song",
    title: "Our Emirates Radion",
  );

  @override
  Future<void> onStart(Map<String, dynamic> params) async {
    // We configure the audio session for speech since we're playing a podcast.
    // You can also put this in your app's initialisation if your app doesn't
    // switch between two types of audio as this example does.
    final session = await AudioSession.instance;
    await session.configure(AudioSessionConfiguration.music());
    _player.onPlayerStateChanged.listen((AudioPlayerState s) {
      _playerState = s;
      _broadcastState(s);
    });

    try {
      await onPlay();
      await AudioServiceBackground.setMediaItem(mediaItem);
    } catch (e) {
      print("Error: $e");
      onStop();
    }
  }

  @override
  Future<void> onPlay() => _player.play(mediaItem.id);

  @override
  Future<void> onPause() => _player.pause();

  @override
  Future<void> onStop() async {
    await _player.pause();
    await _player.dispose();
    await _broadcastState(AudioPlayerState.COMPLETED);
    // Shut down this task
    await super.onStop();
  }

  /// Broadcasts the current state to all clients.
  Future<void> _broadcastState(_playerState) async {
    await AudioServiceBackground.setState(
      controls: [
        if (_playerState == AudioPlayerState.PLAYING)
          MediaControl.pause
        else
          MediaControl.play,
        MediaControl.stop,
      ],
      systemActions: [
        if (_playerState == AudioPlayerState.PLAYING)
          MediaAction.pause
        else
          MediaAction.pause,
        MediaAction.stop,
      ],
      processingState: _getProcessingState(),
      playing: _playerState == AudioPlayerState.PLAYING,
    );
  }

  AudioProcessingState _getProcessingState() {
    switch (_playerState) {
      case AudioPlayerState.STOPPED:
        return AudioProcessingState.stopped;
      case AudioPlayerState.PAUSED:
        return AudioProcessingState.ready;
      case AudioPlayerState.PLAYING:
        return AudioProcessingState.ready;
      case AudioPlayerState.COMPLETED:
        return AudioProcessingState.completed;
      default:
        throw Exception("Invalid state: $_playerState");
    }
  }
}
