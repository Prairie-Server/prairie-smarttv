import 'package:flutter/material.dart' hide Route;
import 'package:prairie_core/prairie_core.dart';

/// What the season picker answers: the seasons to send, or null for the
/// server to choose (see [requestSeasonsToSend]).
class RequestSeasonsPick {
  const RequestSeasonsPick(this.seasons);

  final List<int>? seasons;
}

/// Picks the seasons of [title] (a series with its seasons loaded) to
/// request. Seasons in the library or already requested show but can't be
/// picked; aired missing seasons start picked. Null when the viewer backs
/// out. The web's `RequestSeasonsDialog`, as a remote-friendly list.
Future<RequestSeasonsPick?> showRequestSeasonsDialog(
  BuildContext context, {
  required RequestTitle title,
  required String confirmLabel,
  DateTime? now,
}) => showDialog<RequestSeasonsPick>(
  context: context,
  builder: (_) => _RequestSeasonsDialog(title: title, confirmLabel: confirmLabel, now: now ?? DateTime.now()),
);

class _RequestSeasonsDialog extends StatefulWidget {
  const _RequestSeasonsDialog({required this.title, required this.confirmLabel, required this.now});

  final RequestTitle title;
  final String confirmLabel;
  final DateTime now;

  @override
  State<_RequestSeasonsDialog> createState() => _RequestSeasonsDialogState();
}

class _RequestSeasonsDialogState extends State<_RequestSeasonsDialog> {
  late final List<RequestSeason> _choices = widget.title.seasons.where((s) => s.requestable).toList();
  late Set<int> _picked = defaultRequestSeasons(widget.title.seasons, widget.now).toSet();
  bool _untouched = true;

  List<int>? get _toSend => requestSeasonsToSend(
    title: widget.title,
    picked: _picked,
    untouched: _untouched,
    now: widget.now,
  );

  void _set(Set<int> next) => setState(() {
    _picked = next;
    _untouched = false;
  });

  @override
  Widget build(BuildContext context) {
    final toSend = _toSend;
    final canSend = toSend == null || toSend.isNotEmpty;
    final allPicked = _choices.isNotEmpty && _choices.every((s) => _picked.contains(s.seasonNumber));
    final hint = _untouched && _picked.isEmpty && _choices.isNotEmpty
        ? (widget.title.inLibrary
              ? 'Pick the upcoming seasons to request.'
              : 'No season has aired yet, so the request covers the whole series unless you pick seasons.')
        : null;
    return AlertDialog(
      backgroundColor: PrairieColors.bgElevated,
      title: const Text('Request seasons', style: TextStyle(color: PrairieColors.ink)),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose the seasons of ${widget.title.title} to request.',
              style: const TextStyle(color: PrairieColors.muted),
            ),
            if (hint != null) ...[
              const SizedBox(height: 8),
              Text(hint, style: const TextStyle(color: PrairieColors.muted, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  if (_choices.length > 1)
                    CheckboxListTile(
                      autofocus: true,
                      value: allPicked,
                      onChanged: (on) => _set(on == true ? {for (final s in _choices) s.seasonNumber} : {}),
                      title: const Text('All seasons', style: TextStyle(color: PrairieColors.ink, fontWeight: FontWeight.w600)),
                    ),
                  for (final (index, season) in widget.title.seasons.indexed)
                    CheckboxListTile(
                      autofocus: _choices.length <= 1 && index == 0,
                      value: season.requestable ? _picked.contains(season.seasonNumber) : season.requested,
                      onChanged: season.requestable
                          ? (on) => _set(
                              on == true ? {..._picked, season.seasonNumber} : (_picked.toSet()..remove(season.seasonNumber)),
                            )
                          : null,
                      title: Text(
                        season.label,
                        style: TextStyle(color: season.requestable ? PrairieColors.ink : PrairieColors.muted),
                      ),
                      subtitle: Text(
                        [season.metaLabel, ?season.statusLabel(widget.now)].join(' · '),
                        style: const TextStyle(color: PrairieColors.muted, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          autofocus: _choices.isEmpty,
          onPressed: canSend ? () => Navigator.pop(context, RequestSeasonsPick(toSend)) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
