import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'package:privatestream/core/theme.dart';
import 'package:privatestream/models/media_item.dart';
import 'package:privatestream/services/offline_sync_service.dart';

enum AspectRatioMode {
  original,
  ratio16x9,
  ratio9x16,
  ratio4x3,
  ratio3x4,
  ratio21x9,
  fitContain,
  cropCover,
  stretchFill,
}

enum OrientationLockMode {
  auto,
  portrait,
  landscape,
}

class PlayerScreen extends ConsumerStatefulWidget {
  final MediaItem media;
  final String playbackSourceUrl;
  final bool isOffline;
  final double initialPositionSeconds;

  const PlayerScreen({
    super.key,
    required this.media,
    required this.playbackSourceUrl,
    this.isOffline = false,
    this.initialPositionSeconds = 0.0,
  });

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  late final Player _player;
  late final VideoController _videoController;

  bool _showControls = true;
  Timer? _hideControlsTimer;
  Timer? _progressSyncTimer;

  // Aspect ratio & orientation state
  AspectRatioMode _aspectRatioMode = AspectRatioMode.original;
  OrientationLockMode _orientationLockMode = OrientationLockMode.auto;
  String _badgeMessage = '';
  Timer? _badgeTimer;

  // Gesture state
  double _volumeLevel = 1.0;
  double _brightnessLevel = 0.8;
  bool _isDraggingVolume = false;
  bool _isDraggingBrightness = false;
  bool _isFastForwarding = false;

  // Seek animation indicators
  bool _showLeftSeekRipple = false;
  bool _showRightSeekRipple = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);

    _initPlayer();
    _startPeriodicProgressSync();
    _resetHideControlsTimer();
  }

  Future<void> _initPlayer() async {
    // If media is natively vertical (9:16 or 3:4), default mode to 9:16
    if (widget.media.isVertical) {
      _aspectRatioMode = AspectRatioMode.ratio9x16;
    }

    await _player.open(Media(widget.playbackSourceUrl));

    if (widget.initialPositionSeconds > 0) {
      await _player.seek(Duration(seconds: widget.initialPositionSeconds.toInt()));
    }

    _player.stream.volume.listen((v) {
      if (mounted) setState(() => _volumeLevel = (v / 100).clamp(0.0, 1.0));
    });
  }

  void _startPeriodicProgressSync() {
    _progressSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveCurrentProgress();
    });
  }

  void _saveCurrentProgress() {
    final pos = _player.state.position.inSeconds.toDouble();
    final dur = _player.state.duration.inSeconds.toDouble();
    if (dur > 0 && pos > 0) {
      final isCompleted = (pos / dur) >= 0.92;
      ref.read(offlineServiceProvider).recordWatchProgress(
        mediaId: widget.media.id,
        positionSeconds: pos,
        durationSeconds: dur,
        completed: isCompleted,
      );
    }
  }

  void _resetHideControlsTimer() {
    _hideControlsTimer?.cancel();
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showControls = false);
      });
    }
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _resetHideControlsTimer();
    }
  }

  void _showNotificationBadge(String message) {
    _badgeTimer?.cancel();
    setState(() => _badgeMessage = message);
    _badgeTimer = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _badgeMessage = '');
    });
  }

  // --------------------------------------------------------------------------
  // Aspect Ratio & Orientation Handlers
  // --------------------------------------------------------------------------

  void _cycleAspectRatio() {
    setState(() {
      final nextIndex = (_aspectRatioMode.index + 1) % AspectRatioMode.values.length;
      _aspectRatioMode = AspectRatioMode.values[nextIndex];
    });

    String name = 'Original';
    switch (_aspectRatioMode) {
      case AspectRatioMode.original:
        name = 'Original (${widget.media.aspectRatio})';
        break;
      case AspectRatioMode.ratio16x9:
        name = '16:9 Widescreen';
        break;
      case AspectRatioMode.ratio9x16:
        name = '9:16 Vertical';
        break;
      case AspectRatioMode.ratio4x3:
        name = '4:3 Standard';
        break;
      case AspectRatioMode.ratio3x4:
        name = '3:4 Vertical';
        break;
      case AspectRatioMode.ratio21x9:
        name = '21:9 Ultrawide';
        break;
      case AspectRatioMode.fitContain:
        name = 'Fit (Letterbox)';
        break;
      case AspectRatioMode.cropCover:
        name = 'Crop / Fill (No Bars)';
        break;
      case AspectRatioMode.stretchFill:
        name = 'Stretch to Screen';
        break;
    }
    _showNotificationBadge('Ratio: $name');
    _resetHideControlsTimer();
  }

  void _cycleOrientationLock() {
    setState(() {
      final nextIndex = (_orientationLockMode.index + 1) % OrientationLockMode.values.length;
      _orientationLockMode = OrientationLockMode.values[nextIndex];
    });

    switch (_orientationLockMode) {
      case OrientationLockMode.auto:
        SystemChrome.setPreferredOrientations(DeviceOrientation.values);
        _showNotificationBadge('Orientation: Auto-Rotate');
        break;
      case OrientationLockMode.portrait:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
        _showNotificationBadge('Orientation: Portrait Locked');
        break;
      case OrientationLockMode.landscape:
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
        _showNotificationBadge('Orientation: Landscape Locked');
        break;
    }
    _resetHideControlsTimer();
  }

  BoxFit _getCurrentBoxFit() {
    switch (_aspectRatioMode) {
      case AspectRatioMode.cropCover:
        return BoxFit.cover;
      case AspectRatioMode.stretchFill:
        return BoxFit.fill;
      default:
        return BoxFit.contain;
    }
  }

  double? _getCurrentAspectRatio() {
    switch (_aspectRatioMode) {
      case AspectRatioMode.original:
        return widget.media.aspectRatioValue;
      case AspectRatioMode.ratio16x9:
        return 16 / 9;
      case AspectRatioMode.ratio9x16:
        return 9 / 16;
      case AspectRatioMode.ratio4x3:
        return 4 / 3;
      case AspectRatioMode.ratio3x4:
        return 3 / 4;
      case AspectRatioMode.ratio21x9:
        return 21 / 9;
      case AspectRatioMode.fitContain:
      case AspectRatioMode.cropCover:
      case AspectRatioMode.stretchFill:
        return null;
    }
  }

  // --------------------------------------------------------------------------
  // Gestures: Brightness, Volume, Seeking & 2x Speed
  // --------------------------------------------------------------------------

  void _onLeftVerticalDrag(DragUpdateDetails details) {
    setState(() {
      _isDraggingBrightness = true;
      _brightnessLevel = (_brightnessLevel - (details.primaryDelta! / 300)).clamp(0.0, 1.0);
    });
  }

  void _onRightVerticalDrag(DragUpdateDetails details) {
    setState(() {
      _isDraggingVolume = true;
      _volumeLevel = (_volumeLevel - (details.primaryDelta! / 300)).clamp(0.0, 1.0);
    });
    _player.setVolume(_volumeLevel * 100);
  }

  void _onDoubleTapLeft() {
    final current = _player.state.position;
    final target = current - const Duration(seconds: 10);
    _player.seek(target < Duration.zero ? Duration.zero : target);
    setState(() => _showLeftSeekRipple = true);
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showLeftSeekRipple = false);
    });
  }

  void _onDoubleTapRight() {
    final current = _player.state.position;
    final total = _player.state.duration;
    final target = current + const Duration(seconds: 10);
    _player.seek(target > total ? total : target);
    setState(() => _showRightSeekRipple = true);
    Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _showRightSeekRipple = false);
    });
  }

  void _onLongPressStart() {
    _player.setRate(2.0);
    setState(() => _isFastForwarding = true);
  }

  void _onLongPressEnd() {
    _player.setRate(1.0);
    setState(() => _isFastForwarding = false);
  }

  @override
  void dispose() {
    _saveCurrentProgress();
    _progressSyncTimer?.cancel();
    _hideControlsTimer?.cancel();
    _badgeTimer?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final customRatio = _getCurrentAspectRatio();
    final boxFit = _getCurrentBoxFit();

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Video Surface with Dynamic Aspect Ratio & Fit
          Center(
            child: customRatio != null
                ? AspectRatio(
                    aspectRatio: customRatio,
                    child: Video(
                      controller: _videoController,
                      fit: boxFit,
                      controls: NoVideoControls,
                    ),
                  )
                : SizedBox.expand(
                    child: Video(
                      controller: _videoController,
                      fit: boxFit,
                      controls: NoVideoControls,
                    ),
                  ),
          ),

          // 2. Gesture Detector Layer (Left=Brightness, Right=Volume, Center=Tap)
          Row(
            children: [
              // Left half
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTap: _onDoubleTapLeft,
                  onVerticalDragUpdate: _onLeftVerticalDrag,
                  onVerticalDragEnd: (_) => setState(() => _isDraggingBrightness = false),
                  onLongPressStart: (_) => _onLongPressStart(),
                  onLongPressEnd: (_) => _onLongPressEnd(),
                ),
              ),
              // Right half
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  onDoubleTap: _onDoubleTapRight,
                  onVerticalDragUpdate: _onRightVerticalDrag,
                  onVerticalDragEnd: (_) => setState(() => _isDraggingVolume = false),
                  onLongPressStart: (_) => _onLongPressStart(),
                  onLongPressEnd: (_) => _onLongPressEnd(),
                ),
              ),
            ],
          ),

          // 3. Double-tap Ripple Indicators
          if (_showLeftSeekRipple)
            Positioned(
              left: 50,
              top: size.height / 2 - 50,
              child: _buildSeekFeedback(Icons.replay_10_rounded, '-10s'),
            ),
          if (_showRightSeekRipple)
            Positioned(
              right: 50,
              top: size.height / 2 - 50,
              child: _buildSeekFeedback(Icons.forward_10_rounded, '+10s'),
            ),

          // 4. Volume / Brightness Indicator Overlays
          if (_isDraggingVolume)
            Center(
              child: _buildSliderHUD(Icons.volume_up_rounded, (_volumeLevel * 100).toInt(), '%'),
            ),
          if (_isDraggingBrightness)
            Center(
              child: _buildSliderHUD(Icons.brightness_6_rounded, (_brightnessLevel * 100).toInt(), '%'),
            ),

          // 5. 2x Speed Indicator Overlay
          if (_isFastForwarding)
            Positioned(
              top: 40,
              left: size.width / 2 - 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.cyberCyan.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fast_forward_rounded, color: Colors.black, size: 18),
                    SizedBox(width: 6),
                    Text(
                      '2X SPEED',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // 6. Toast Notification Badge (Aspect Ratio / Orientation Changes)
          if (_badgeMessage.isNotEmpty)
            Positioned(
              top: 50,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(25),
                    border: Border.all(color: AppTheme.cyberCyan, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.cyberCyan.withValues(alpha: 0.3),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Text(
                    _badgeMessage,
                    style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ),
            ),

          // 7. Full Player HUD Overlay (Top Bar, Center Play, Bottom Progress Bar)
          if (_showControls) _buildHUD(context),
        ],
      ),
    );
  }

  Widget _buildSeekFeedback(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.black54,
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.cyberCyan.withValues(alpha: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.cyberCyan, size: 36),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSliderHUD(IconData icon, int value, String unit) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.surfaceBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppTheme.cyberCyan, size: 36),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: (value / 100).clamp(0.0, 1.0),
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.cyberCyan),
            minHeight: 6,
          ),
          const SizedBox(height: 8),
          Text('$value$unit', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHUD(BuildContext context) {
    return Container(
      color: Colors.black45,
      child: SafeArea(
        child: Column(
          children: [
            // Top Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.media.title,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.isOffline)
                          const Row(
                            children: [
                              Icon(Icons.offline_pin_rounded, color: AppTheme.accentGreen, size: 14),
                              SizedBox(width: 4),
                              Text('Offline Mode (Local Storage)', style: TextStyle(color: AppTheme.accentGreen, fontSize: 11)),
                            ],
                          ),
                      ],
                    ),
                  ),
                  // Orientation Lock Toggle Button
                  IconButton(
                    tooltip: 'Orientation Lock',
                    icon: Icon(
                      _orientationLockMode == OrientationLockMode.auto
                          ? Icons.screen_rotation_rounded
                          : _orientationLockMode == OrientationLockMode.portrait
                              ? Icons.stay_current_portrait_rounded
                              : Icons.stay_current_landscape_rounded,
                      color: _orientationLockMode == OrientationLockMode.auto ? Colors.white : AppTheme.cyberCyan,
                    ),
                    onPressed: _cycleOrientationLock,
                  ),
                  // Real-Time Aspect Ratio & Fit Cycling Button
                  IconButton(
                    tooltip: 'Aspect Ratio & Fit',
                    icon: const Icon(Icons.aspect_ratio_rounded, color: AppTheme.cyberCyan),
                    onPressed: _cycleAspectRatio,
                  ),
                ],
              ),
            ),

            const Spacer(),

            // Center Play / Pause
            StreamBuilder<bool>(
              stream: _player.stream.playing,
              builder: (context, snapshot) {
                final isPlaying = snapshot.data ?? true;
                return Center(
                  child: IconButton(
                    iconSize: 64,
                    icon: Icon(
                      isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                      color: Colors.white,
                    ),
                    onPressed: () {
                      if (isPlaying) {
                        _player.pause();
                      } else {
                        _player.play();
                      }
                      _resetHideControlsTimer();
                    },
                  ),
                );
              },
            ),

            const Spacer(),

            // Bottom Timeline & Progress Slider
            StreamBuilder<Duration>(
              stream: _player.stream.position,
              builder: (context, posSnapshot) {
                final position = posSnapshot.data ?? Duration.zero;
                final duration = _player.state.duration;

                final currentSec = position.inSeconds.toDouble();
                final totalSec = duration.inSeconds.toDouble();
                final clampedSec = currentSec.clamp(0.0, totalSec > 0 ? totalSec : 1.0);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: AppTheme.netflixRed,
                          inactiveTrackColor: Colors.white30,
                          thumbColor: AppTheme.netflixRed,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          value: totalSec > 0 ? clampedSec : 0.0,
                          max: totalSec > 0 ? totalSec : 1.0,
                          onChanged: (val) {
                            _resetHideControlsTimer();
                            _player.seek(Duration(seconds: val.toInt()));
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(position),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                            Text(
                              _formatDuration(duration),
                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final int hours = d.inHours;
    final int minutes = d.inMinutes % 60;
    final int seconds = d.inSeconds % 60;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
