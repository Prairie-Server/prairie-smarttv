import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
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
  /// One node per tab pill — the first row of each list explicitly hands
  /// Up off to its tab's node (see [_EscapeUpToTab]) rather than trusting
  /// geometric directional search, which on real hardware skips right past
  /// this pill row and lands on the ShellNav header above it instead.
  final _tabFocusNodes = {for (final t in _LiveTvTab.values) t: FocusNode()};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final node in _tabFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
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
    final serverUrl = ref.watch(sessionProvider)!.serverUrl;
    return ShellScaffold(
      active: ShellTab.livetv,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                for (final (tab, label) in const [
                  (_LiveTvTab.channels, 'Channels'),
                  (_LiveTvTab.guide, 'Guide'),
                  (_LiveTvTab.recordings, 'Recordings'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _LiveTvTabPill(
                      label: label,
                      active: _tab == tab,
                      focusNode: _tabFocusNodes[tab],
                      onTap: () {
                        setState(() => _tab = tab);
                        if (tab == _LiveTvTab.recordings) _loadRecordings();
                      },
                    ),
                  ),
              ],
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
                      serverUrl: serverUrl,
                      onTune: _tune,
                      escapeUpFocusNode: _tabFocusNodes[_tab],
                    ),
                    _LiveTvTab.guide => _GuideList(
                      channels: _channels,
                      index: index,
                      serverUrl: serverUrl,
                      recordingBusyId: _recordingBusyId,
                      onTune: _tune,
                      onRecord: _record,
                      escapeUpFocusNode: _tabFocusNodes[_tab],
                    ),
                    _LiveTvTab.recordings => _RecordingsList(
                      recordings: _recordings,
                      cancelBusyId: _cancelBusyId,
                      onCancel: _cancelRecording,
                      escapeUpFocusNode: _tabFocusNodes[_tab],
                    ),
                  },
          ),
        ],
      ),
    );
  }
}

/// Channels/Guide/Recordings tab selector — replaces the default
/// `SegmentedButton`, whose focus indicator was nearly invisible on TV.
class _LiveTvTabPill extends StatefulWidget {
  const _LiveTvTabPill({required this.label, required this.active, required this.onTap, this.focusNode});

  final String label;
  final bool active;
  final VoidCallback onTap;
  final FocusNode? focusNode;

  @override
  State<_LiveTvTabPill> createState() => _LiveTvTabPillState();
}

class _LiveTvTabPillState extends State<_LiveTvTabPill> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    final active = widget.active;
    return Material(
      color: focused
          ? PrairieColors.focusFill
          : active
              ? PrairieColors.amber
              : PrairieColors.bgElevated.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        focusNode: widget.focusNode,
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        onFocusChange: (value) => setState(() => _focused = value),
        focusColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: focused ? PrairieColors.ink.withValues(alpha: 0.85) : Colors.transparent,
              width: focused ? 3 : 1,
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              color: (active && !focused) ? PrairieColors.bg : PrairieColors.ink,
              fontWeight: focused || active ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
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

/// Small rounded logo tile used by the Channels/Guide tabs — falls back to
/// the channel number when there's no logo (On Now, on the home dashboard,
/// shows the program's content poster instead; this is channel art only).
class _ChannelBadge extends StatelessWidget {
  const _ChannelBadge({required this.channel, required this.serverUrl});

  final LiveTvChannel channel;
  final String serverUrl;

  @override
  Widget build(BuildContext context) {
    final logoUrl = channel.logoUrl;
    final number = channel.numberOverride ?? channel.number;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        height: 64,
        padding: const EdgeInsets.all(6),
        // Broadcast logo art is almost always designed for a light/white
        // backdrop (often with dark or transparent-only strokes) — showing
        // it directly on the app's dark surfaces made many logos unreadable.
        color: Colors.white,
        alignment: Alignment.center,
        child: logoUrl != null
            ? Image.network(
                resolveAssetUrl(serverUrl, logoUrl),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Text(number, style: const TextStyle(color: PrairieColors.bg, fontWeight: FontWeight.w600)),
              )
            : Text(number, style: const TextStyle(color: PrairieColors.bg, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// Always redirects D-pad Up straight to [target] — used only on a list's
/// first row. Geometric directional search (`focusInDirection`) technically
/// "succeeds" from there, but on real hardware it lands past the tab pill
/// row entirely and on the ShellNav header above it, so this bypasses that
/// search rather than merely falling back when it fails (contrast with
/// `MediaRow`'s `escapeUpFocusNode`, whose search genuinely fails to find
/// anything and only then needs a fallback).
class _EscapeUpToTab extends StatelessWidget {
  const _EscapeUpToTab({required this.child, required this.target});

  final Widget child;
  final FocusNode? target;

  @override
  Widget build(BuildContext context) {
    final target = this.target;
    if (target == null) return child;
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.arrowUp) {
          return KeyEventResult.ignored;
        }
        target.requestFocus();
        return KeyEventResult.handled;
      },
      child: child,
    );
  }
}

class _ChannelsList extends StatelessWidget {
  const _ChannelsList({
    required this.channels,
    required this.index,
    required this.serverUrl,
    required this.onTune,
    this.escapeUpFocusNode,
  });

  final List<LiveTvChannel> channels;
  final Map<String, List<LiveTvProgram>> index;
  final String serverUrl;
  final void Function(LiveTvChannel) onTune;
  final FocusNode? escapeUpFocusNode;

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
        final row = _FocusableRow(
          autofocus: i == 0,
          onTap: () => onTune(channel),
          child: Row(
            children: [
              _ChannelBadge(channel: channel, serverUrl: serverUrl),
              const SizedBox(width: 12),
              SizedBox(
                width: 60,
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
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: i == 0 ? _EscapeUpToTab(target: escapeUpFocusNode, child: row) : row,
        );
      },
    );
  }
}

/// Shared focus-aware row shell for Channels/Guide/Recordings — a visible
/// amber-ring highlight, matching the rest of the app's TV focus language,
/// instead of InkWell's barely-there default focus overlay.
class _FocusableRow extends StatefulWidget {
  const _FocusableRow({required this.child, this.onTap, this.autofocus = false});

  final Widget child;
  final VoidCallback? onTap;
  final bool autofocus;

  @override
  State<_FocusableRow> createState() => _FocusableRowState();
}

class _FocusableRowState extends State<_FocusableRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final focused = _focused;
    return Material(
      // Settings-style darker focus fill — bright amberDeep washed out text.
      color: focused ? PrairieColors.focusFill : PrairieColors.bgElevated.withValues(alpha: 0.72),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        autofocus: widget.autofocus,
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        onFocusChange: (value) => setState(() => _focused = value),
        focusColor: Colors.transparent,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? PrairieColors.ink.withValues(alpha: 0.85) : Colors.transparent,
              width: focused ? 3 : 1,
            ),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Mirrors the TS Guide tab: Now/Next rows with inline Watch / Record now /
/// Record next — not a horizontal EPG timeline.
class _GuideList extends StatelessWidget {
  const _GuideList({
    required this.channels,
    required this.index,
    required this.serverUrl,
    required this.recordingBusyId,
    required this.onTune,
    required this.onRecord,
    this.escapeUpFocusNode,
  });

  final List<LiveTvChannel> channels;
  final Map<String, List<LiveTvProgram>> index;
  final String serverUrl;
  final String? recordingBusyId;
  final void Function(LiveTvChannel) onTune;
  final void Function(LiveTvProgram) onRecord;
  final FocusNode? escapeUpFocusNode;

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
        final shell = _GuideRowShell(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final channelCol = Row(
                  children: [
                    _ChannelBadge(channel: channel, serverUrl: serverUrl),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 60,
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
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: i == 0 ? _EscapeUpToTab(target: escapeUpFocusNode, child: shell) : shell,
        );
      },
    );
  }
}

/// Highlights the whole guide row when any of its action buttons has focus
/// (a `FocusScope` aggregates descendant focus, unlike a bare `Focus` node).
class _GuideRowShell extends StatefulWidget {
  const _GuideRowShell({required this.child});

  final Widget child;

  @override
  State<_GuideRowShell> createState() => _GuideRowShellState();
}

class _GuideRowShellState extends State<_GuideRowShell> {
  // A plain marker node (never itself focused, never part of traversal) —
  // FocusScope was tried here first but it created a traversal boundary per
  // row, which broke D-pad down from moving past the first row's buttons.
  // Membership-testing the focus manager's ancestor chain avoids that
  // entirely since no new scope is introduced.
  final _node = FocusNode(debugLabel: 'guide-row-marker', skipTraversal: true, canRequestFocus: false);
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onGlobalFocusChange);
  }

  void _onGlobalFocusChange() {
    final primary = FocusManager.instance.primaryFocus;
    final within = primary != null && (primary == _node || primary.ancestors.contains(_node));
    if (within != _focused) setState(() => _focused = within);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onGlobalFocusChange);
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _node,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: _focused ? PrairieColors.focusFill : PrairieColors.bgElevated.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _focused ? PrairieColors.ink.withValues(alpha: 0.85) : Colors.transparent,
            width: _focused ? 3 : 1,
          ),
        ),
        child: widget.child,
      ),
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
    this.escapeUpFocusNode,
  });

  final List<LiveTvRecording> recordings;
  final String? cancelBusyId;
  final void Function(LiveTvRecording) onCancel;
  final FocusNode? escapeUpFocusNode;

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

    final firstOverall = active.isNotEmpty ? active.first : (history.isNotEmpty ? history.first : null);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      children: [
        if (active.isNotEmpty) ...[
          const Text('Scheduled & in progress', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink)),
          const SizedBox(height: 8),
          for (final recording in active) _recordingTile(recording, canCancel: true, isFirst: identical(recording, firstOverall)),
        ],
        if (history.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('History', style: TextStyle(fontFamily: 'Fraunces', fontSize: 22, color: PrairieColors.ink)),
          const SizedBox(height: 8),
          for (final recording in history) _recordingTile(recording, canCancel: false, isFirst: identical(recording, firstOverall)),
        ],
      ],
    );
  }

  Widget _recordingTile(LiveTvRecording recording, {required bool canCancel, bool isFirst = false}) {
    final busy = cancelBusyId == recording.id;
    final shell = _GuideRowShell(
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
                  Text(_recordingStatusLabel(recording.status), style: const TextStyle(color: PrairieColors.muted, fontSize: 13)),
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
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: isFirst ? _EscapeUpToTab(target: escapeUpFocusNode, child: shell) : shell,
    );
  }

  String _recordingStatusLabel(String status) => switch (status.trim().toLowerCase()) {
    'scheduled' => 'Scheduled',
    'recording' || 'in_progress' => 'Recording',
    'completed' => 'Completed',
    'failed' => 'Failed',
    'cancelled' || 'canceled' => 'Cancelled',
    _ => status,
  };
}
