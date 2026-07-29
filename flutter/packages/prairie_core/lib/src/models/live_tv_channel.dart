/// Mirrors `LiveTvChannel` from src/api/livetv.ts.
class LiveTvChannel {
  const LiveTvChannel({
    required this.id,
    required this.tunerId,
    required this.number,
    this.numberOverride,
    required this.callsign,
    required this.name,
    this.logoUrl,
    required this.hd,
    required this.enabled,
    this.streamUrl,
    this.guideStationId,
  });

  final String id;
  final String tunerId;
  final String number;
  final String? numberOverride;
  final String callsign;
  final String name;
  final String? logoUrl;
  final bool hd;
  final bool enabled;
  final String? streamUrl;
  final String? guideStationId;
}
