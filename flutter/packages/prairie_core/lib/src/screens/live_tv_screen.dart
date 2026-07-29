import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

enum _LiveTvTab { channels, guide, recordings }

const _minutesPerPixel = 2.0; // 1 minute of program = 2px wide in the guide.
const _guideRowHeight = 72.0;
const _guideChannelColumnWidth = 180.0;
const _guideWindowHours = 6;

/// Mirrors LiveTvScreen.tsx's Channels/Guide/Recordings tabs, including
/// Record now / Record next scheduling from the guide.
class LiveTvScreen extends ConsumerStatefulWidget {
  const LiveTvScreen({super.key});

  @override
  ConsumerState<LiveTvScreen> createState() => _LiveTvScreenState();
}

class _LiveTvScreenState extends ConsumerState<LiveTvScreen> {
  List<LiveTvChannel> _channels = [];
  List<LiveTvProgram> _programs = [];
  List<LiveTvRecording> _recordings = [];
  bool _loading = true;
  String? _error;
  String? _status;
  String? _recordingBusyId;
  String? _cancelBusyId;
  _LiveTvTab _tab = _LiveTvTab.guide;
  late DateTime _windowStart;

  @override
  void initState() {
    super.initState();
    _windowStart = DateTime.now();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final client = ref.read(apiClientProvider);
      final session = ref.read(sessionProvider)!;
      final channels = await fetchLiveTvChannels(client, session);
      final programs = channels.isEmpty
          ? <LiveTvProgram>[]
          : await fetchLiveTvGuide(client, session, channels.map((c) => c.id).toList());
      if (!mounted) return;
      setState(() {
        _channels = channels;
        _programs = programs;
        _windowStart = DateTime.now();
      });
      _loadRecordings();
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiError ? e.message : 'Could not load Live TV');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRecordings() async {
    try {
      final recordings = await fetchLiveTvRecordings(ref.read(apiClientProvider), ref.read(sessionProvider)!);
      if (mounted) setState(() => _recordings = recordings);
    } catch (_) {
      // Recordings are optional — an absent endpoint must not fail the screen.
    }
  }

  void _tune(LiveTvChannel channel) {
    ref.read(routeProvider.notifier).go(LiveTvPlayerRoute(channel: channel, back: const LiveTvRoute()));
  }

  Future<void> _record(LiveTvProgram program) async {
    final programId = program.id.trim();
    if (programId.isEmpty || _recordingBusyId != null) return;
    if (!program.stop.isAfter(DateTime.now())) {
      setState(() => _status = 'Program already ended');
      return;
    }
    setState(() {
      _recordingBusyId = programId;
      _status = null;
      _error = null;
    });
    try {
      await scheduleLiveTvRecording(ref.read(apiClientProvider), ref.read(sessionProvider)!, programId);
      if (!mounted) return;
      setState(() => _status = 'Recording scheduled');
      await _loadRecordings();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiError ? e.message : 'Could not schedule recording');
      }
    } finally {
      if (mounted) setState(() => _recordingBusyId = null);
    }
  }

  Future<void> _cancelRecording(LiveTvRecording recording) async {
    final id = recording.id.trim();
    if (id.isEmpty || _cancelBusyId != null) return;
    setState(() {
      _cancelBusyId = id;
      _status = null;
      _error = null;
    });
    try {
      await cancelLiveTvRecording(ref.read(apiClientProvider), ref.read(sessionProvider)!, id);
      if (!mounted) return;
      setState(() {
        _recordings = _recordings.where((r) => r.id != id).toList();
        _status = 'Recording cancelled';
      });
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is ApiError ? e.message : 'Could not cancel recording');
      }
    } finally {
      if (mounted) setState(() => _cancelBusyId = null);
    }
  }

  Future<void> _showProgramActions(LiveTvChannel channel, LiveTvProgram program) async {
    final now = DateTime.now();
    final canRecord = program.id.trim().isNotEmpty && program.stop.isAfter(now);
    final isNow = !program.start.isAfter(now) && program.stop.isAfter(now);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: PrairieColors.bgElevated,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(program.title, style: const TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink)),
              const SizedBox(height: 4),
              Text(
                '${channelDisplayLabel(channel)} · ${_formatClock(program.start)} – ${_formatClock(program.stop)}',
                style: const TextStyle(color: PrairieColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _tune(channel);
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Watch'),
              ),
              if (canRecord) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _recordingBusyId != null
                      ? null
                      : () {
                          Navigator.of(context).pop();
                          _record(program);
                        },
                  icon: const Icon(Icons.fiber_manual_record, color: PrairieColors.danger),
                  label: Text(
                    _recordingBusyId == program.id
                        ? 'Scheduling…'
                        : (isNow ? 'Record now' : 'Record'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatClock(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final index = indexProgramsByChannel(_programs);
    return ShellScaffold(
      active: ShellTab.livetv,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: SegmentedButton<_LiveTvTab>(
              segments: const [
                ButtonSegment(value: _LiveTvTab.channels, label: Text('Channels')),
                ButtonSegment(value: _LiveTvTab.guide, label: Text('Guide')),
                ButtonSegment(value: _LiveTvTab.recordings, label: Text('Recordings')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) {
                final next = s.first;
                setState(() => _tab = next);
                if (next == _LiveTvTab.recordings) _loadRecordings();
              },
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_status!, style: const TextStyle(color: PrairieColors.amber)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(_error!, style: const TextStyle(color: PrairieColors.danger)),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: PrairieColors.amber))
                : switch (_tab) {
                    _LiveTvTab.channels => _ChannelsList(
                      channels: _channels,
                      index: index,
                      recordingBusyId: _recordingBusyId,
                      onTune: _tune,
                      onRecord: _record,
                    ),
                    _LiveTvTab.guide => _GuideGrid(
                      channels: _channels,
                      index: index,
                      windowStart: _windowStart,
                      onTune: _tune,
                      onProgramTap: _showProgramActions,
                    ),
                    _LiveTvTab.recordings => _RecordingsList(
                      recordings: _recordings,
                      cancelBusyId: _cancelBusyId,
                      onCancel: _cancelRecording,
                    ),
                  },
          ),
        ],
      ),
    );
  }
}

class _ChannelsList extends StatelessWidget {
  const _ChannelsList({
    required this.channels,
    required this.index,
    required this.recordingBusyId,
    required this.onTune,
    required this.onRecord,
  });

  final List<LiveTvChannel> channels;
  final Map<String, List<LiveTvProgram>> index;
  final String? recordingBusyId;
  final void Function(LiveTvChannel) onTune;
  final void Function(LiveTvProgram) onRecord;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Center(child: Text('No channels available', style: TextStyle(color: PrairieColors.muted)));
    }
    return ListView.builder(
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final channel = channels[i];
        final current = currentProgramInIndex(index, channel.id);
        final next = nextProgramInIndex(index, channel.id);
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: PrairieColors.bgElevated,
            child: Text(channel.numberOverride ?? channel.number, style: const TextStyle(color: PrairieColors.amber, fontSize: 12)),
          ),
          title: Text(channelDisplayLabel(channel), style: const TextStyle(color: PrairieColors.ink)),
          subtitle: Text(current?.title ?? 'No guide data', style: const TextStyle(color: PrairieColors.muted)),
          trailing: Wrap(
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Watch',
                icon: const Icon(Icons.play_circle_outline, color: PrairieColors.amber),
                onPressed: () => onTune(channel),
              ),
              if (current?.id.trim().isNotEmpty == true)
                IconButton(
                  tooltip: 'Record now',
                  icon: Icon(
                    Icons.fiber_manual_record,
                    color: recordingBusyId == current!.id ? PrairieColors.muted : PrairieColors.danger,
                  ),
                  onPressed: recordingBusyId != null ? null : () => onRecord(current),
                ),
              if (next?.id.trim().isNotEmpty == true)
                IconButton(
                  tooltip: 'Record next',
                  icon: Icon(
                    Icons.fiber_smart_record,
                    color: recordingBusyId == next!.id ? PrairieColors.muted : PrairieColors.danger,
                  ),
                  onPressed: recordingBusyId != null ? null : () => onRecord(next),
                ),
            ],
          ),
          onTap: () => onTune(channel),
        );
      },
    );
  }
}

class _GuideGrid extends StatelessWidget {
  const _GuideGrid({
    required this.channels,
    required this.index,
    required this.windowStart,
    required this.onTune,
    required this.onProgramTap,
  });

  final List<LiveTvChannel> channels;
  final Map<String, List<LiveTvProgram>> index;
  final DateTime windowStart;
  final void Function(LiveTvChannel) onTune;
  final void Function(LiveTvChannel, LiveTvProgram) onProgramTap;

  double _xFor(DateTime time) => time.difference(windowStart).inMinutes * _minutesPerPixel;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Center(child: Text('No channels available', style: TextStyle(color: PrairieColors.muted)));
    }
    final windowWidth = _guideWindowHours * 60 * _minutesPerPixel;
    final nowX = _xFor(DateTime.now());

    return SingleChildScrollView(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _guideChannelColumnWidth,
            child: Column(
              children: [
                const SizedBox(height: 28),
                const Divider(height: 1, color: PrairieColors.bgSoft),
                for (final channel in channels)
                  InkWell(
                    onTap: () => onTune(channel),
                    child: SizedBox(
                      height: _guideRowHeight,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 14,
                              backgroundColor: PrairieColors.bgElevated,
                              child: Text(channel.numberOverride ?? channel.number, style: const TextStyle(color: PrairieColors.amber, fontSize: 10)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                channelDisplayLabel(channel),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: PrairieColors.ink, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: windowWidth,
                child: Column(
                  children: [
                    SizedBox(
                      height: 28,
                      child: Stack(
                        children: [
                          for (var h = 0; h <= _guideWindowHours; h++)
                            Positioned(
                              left: h * 60 * _minutesPerPixel,
                              top: 0,
                              child: Text(_formatHour(windowStart.add(Duration(hours: h))), style: const TextStyle(color: PrairieColors.muted, fontSize: 12)),
                            ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: PrairieColors.bgSoft),
                    for (final channel in channels)
                      SizedBox(
                        height: _guideRowHeight,
                        child: Stack(
                          children: [
                            for (final program in index[channel.id] ?? const <LiveTvProgram>[])
                              Positioned(
                                left: _xFor(program.start).clamp(0, windowWidth),
                                width: (_xFor(program.stop) - _xFor(program.start)).clamp(24, windowWidth),
                                top: 4,
                                bottom: 4,
                                child: _ProgramBlock(
                                  program: program,
                                  isNow: !program.start.isAfter(DateTime.now()) && program.stop.isAfter(DateTime.now()),
                                  onTap: () => onProgramTap(channel, program),
                                ),
                              ),
                            Positioned(left: nowX, top: 0, bottom: 0, child: Container(width: 2, color: PrairieColors.amber)),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatHour(DateTime dt) {
    final local = dt.toLocal();
    final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour12 $suffix';
  }
}

class _ProgramBlock extends StatelessWidget {
  const _ProgramBlock({required this.program, required this.isNow, required this.onTap});

  final LiveTvProgram program;
  final bool isNow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isNow ? PrairieColors.amber.withValues(alpha: 0.22) : PrairieColors.bgElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isNow ? PrairieColors.amber.withValues(alpha: 0.6) : PrairieColors.ink.withValues(alpha: 0.08)),
        ),
        child: Text(
          program.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: isNow ? PrairieColors.amber : PrairieColors.ink, fontSize: 12, fontWeight: isNow ? FontWeight.w600 : FontWeight.normal),
        ),
      ),
    );
  }
}

class _RecordingsList extends StatelessWidget {
  const _RecordingsList({
    required this.recordings,
    required this.cancelBusyId,
    required this.onCancel,
  });

  final List<LiveTvRecording> recordings;
  final String? cancelBusyId;
  final void Function(LiveTvRecording) onCancel;

  @override
  Widget build(BuildContext context) {
    if (recordings.isEmpty) {
      return const Center(child: Text('No recordings scheduled', style: TextStyle(color: PrairieColors.muted)));
    }

    final active = <LiveTvRecording>[];
    final history = <LiveTvRecording>[];
    for (final recording in recordings) {
      final status = recording.status.trim().toLowerCase();
      if (status == 'scheduled' || status == 'recording' || status == 'in_progress') {
        active.add(recording);
      } else {
        history.add(recording);
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      children: [
        if (active.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Scheduled', style: TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600)),
          ),
          for (final recording in active) _recordingTile(recording, canCancel: true),
        ],
        if (history.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('History', style: TextStyle(color: PrairieColors.muted, fontWeight: FontWeight.w600)),
          ),
          for (final recording in history) _recordingTile(recording, canCancel: false),
        ],
      ],
    );
  }

  Widget _recordingTile(LiveTvRecording recording, {required bool canCancel}) {
    final busy = cancelBusyId == recording.id;
    return ListTile(
      leading: const Icon(Icons.fiber_manual_record, color: PrairieColors.danger),
      title: Text(recording.title, style: const TextStyle(color: PrairieColors.ink)),
      subtitle: Text(recording.status, style: const TextStyle(color: PrairieColors.muted)),
      trailing: canCancel
          ? IconButton(
              icon: Icon(busy ? Icons.hourglass_top : Icons.close, color: PrairieColors.muted),
              onPressed: busy ? null : () => onCancel(recording),
            )
          : null,
    );
  }
}
