import 'package:flutter/material.dart' hide Route;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prairie_core/prairie_core.dart';

enum _LiveTvTab { channels, guide, recordings }

/// Mirrors LiveTvScreen.tsx's Channels/Guide/Recordings tabs, including
/// Record now / Record next scheduling from the guide (Now/Next rows, not an
/// EPG timeline).
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

  @override
  void initState() {
    super.initState();
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
                ? const Center(child: PrairieLoadingIndicator())
                : switch (_tab) {
                    _LiveTvTab.channels => _ChannelsList(
                      channels: _channels,
                      index: index,
                      onTune: _tune,
                    ),
                    _LiveTvTab.guide => _GuideList(
                      channels: _channels,
                      index: index,
                      recordingBusyId: _recordingBusyId,
                      onTune: _tune,
                      onRecord: _record,
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

String _formatGuideClock(DateTime dt) {
  final local = dt.toLocal();
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final suffix = local.hour >= 12 ? 'PM' : 'AM';
  return '$hour12:$minute $suffix';
}

String _programLine(LiveTvProgram? program, String fallback) {
  if (program == null) return fallback;
  final when = '${_formatGuideClock(program.start)} – ${_formatGuideClock(program.stop)}';
  return '${program.title} · $when';
}

class _ChannelsList extends StatelessWidget {
  const _ChannelsList({
    required this.channels,
    required this.index,
    required this.onTune,
  });

  final List<LiveTvChannel> channels;
  final Map<String, List<LiveTvProgram>> index;
  final void Function(LiveTvChannel) onTune;

  @override
  Widget build(BuildContext context) {
    if (channels.isEmpty) {
      return const Center(child: Text('No channels available', style: TextStyle(color: PrairieColors.muted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final channel = channels[i];
        final current = currentProgramInIndex(index, channel.id);
        final number = channel.numberOverride ?? channel.number;
        final hdSuffix = channel.hd ? ' HD' : '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: PrairieColors.bgElevated.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              autofocus: i == 0,
              borderRadius: BorderRadius.circular(14),
              onTap: () => onTune(channel),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        '$number$hdSuffix',
                        style: const TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(channelDisplayLabel(channel), style: const TextStyle(color: PrairieColors.ink, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            _programLine(current, 'No guide data'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: PrairieColors.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Mirrors the TS Guide tab: Now/Next rows with inline Watch / Record now /
/// Record next — not a horizontal EPG timeline.
class _GuideList extends StatelessWidget {
  const _GuideList({
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      itemCount: channels.length,
      itemBuilder: (context, i) {
        final channel = channels[i];
        final now = currentProgramInIndex(index, channel.id);
        final next = nextProgramInIndex(index, channel.id);
        final number = channel.numberOverride ?? channel.number;
        final hdSuffix = channel.hd ? ' HD' : '';
        final recordingBusy = recordingBusyId != null;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: PrairieColors.bgElevated.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.transparent),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final channelCol = Row(
                    children: [
                      SizedBox(
                        width: 72,
                        child: Text(
                          '$number$hdSuffix',
                          style: const TextStyle(color: PrairieColors.amber, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          channelDisplayLabel(channel),
                          style: const TextStyle(color: PrairieColors.ink, fontWeight: FontWeight.w600, fontSize: 16),
                        ),
                      ),
                    ],
                  );
                  final programsCol = wide
                      ? Row(
                          children: [
                            Expanded(child: _NowNextBlock(label: 'Now', line: _programLine(now, 'Nothing listed'))),
                            const SizedBox(width: 16),
                            Expanded(child: _NowNextBlock(label: 'Next', line: _programLine(next, 'Nothing listed'))),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _NowNextBlock(label: 'Now', line: _programLine(now, 'Nothing listed')),
                            const SizedBox(height: 12),
                            _NowNextBlock(label: 'Next', line: _programLine(next, 'Nothing listed')),
                          ],
                        );
                  final actions = Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ElevatedButton.icon(
                        autofocus: i == 0,
                        onPressed: () => onTune(channel),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Watch'),
                      ),
                      if (now?.id.trim().isNotEmpty == true)
                        OutlinedButton.icon(
                          onPressed: recordingBusy ? null : () => onRecord(now!),
                          icon: const Icon(Icons.fiber_manual_record, color: PrairieColors.danger, size: 18),
                          label: Text(recordingBusyId == now!.id ? 'Scheduling…' : 'Record now'),
                        ),
                      if (next?.id.trim().isNotEmpty == true)
                        OutlinedButton.icon(
                          onPressed: recordingBusy ? null : () => onRecord(next!),
                          icon: const Icon(Icons.fiber_manual_record, color: PrairieColors.danger, size: 18),
                          label: Text(recordingBusyId == next!.id ? 'Scheduling…' : 'Record next'),
                        ),
                    ],
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(flex: 9, child: channelCol),
                        const SizedBox(width: 16),
                        Expanded(flex: 14, child: programsCol),
                        const SizedBox(width: 16),
                        actions,
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      channelCol,
                      const SizedBox(height: 12),
                      programsCol,
                      const SizedBox(height: 12),
                      actions,
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NowNextBlock extends StatelessWidget {
  const _NowNextBlock({required this.label, required this.line});

  final String label;
  final String line;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(color: PrairieColors.amber, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1.2),
        ),
        const SizedBox(height: 4),
        Text(line, style: const TextStyle(color: PrairieColors.ink, height: 1.35)),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        if (active.isNotEmpty) ...[
          const Text('Scheduled & in progress', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink)),
          const SizedBox(height: 8),
          for (final recording in active) _recordingTile(recording, canCancel: true),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('History', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink)),
          const SizedBox(height: 8),
          for (final recording in history) _recordingTile(recording, canCancel: false),
        ],
      ],
    );
  }

  Widget _recordingTile(LiveTvRecording recording, {required bool canCancel}) {
    final busy = cancelBusyId == recording.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: PrairieColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recording.title.trim().isNotEmpty ? recording.title : 'Untitled recording',
                      style: const TextStyle(fontFamily: 'Fraunces', fontSize: 17, color: PrairieColors.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_formatGuideClock(recording.start)} – ${_formatGuideClock(recording.stop)}',
                      style: const TextStyle(color: PrairieColors.muted, fontSize: 13),
                    ),
                    Text(recording.status, style: const TextStyle(color: PrairieColors.muted, fontSize: 13)),
                  ],
                ),
              ),
              if (canCancel)
                TextButton.icon(
                  onPressed: busy ? null : () => onCancel(recording),
                  icon: Icon(busy ? Icons.hourglass_top : Icons.close, color: PrairieColors.muted),
                  label: Text(busy ? 'Cancelling…' : 'Cancel', style: const TextStyle(color: PrairieColors.muted)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
