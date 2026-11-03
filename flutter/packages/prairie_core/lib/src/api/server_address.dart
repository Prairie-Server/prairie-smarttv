/// The typed server address on the Add server screen, with the protocol and
/// port from Advanced options. Mirrors Android's `ServerSetupAddress.kt`
/// (#758), which follows prairie-apple's `ServerSetupViewModel`: Auto tries
/// HTTPS, then HTTP, then Prairie's port 8090.
library;

enum ServerSetupScheme {
  auto('Auto', null),
  https('HTTPS', 'https'),
  http('HTTP', 'http');

  const ServerSetupScheme(this.label, this.urlScheme);

  final String label;

  /// The one scheme to try, or null for Auto.
  final String? urlScheme;
}

/// A typed address or port that can't become a server URL. [message] is
/// shown on the screen as is.
class ServerSetupValidationException implements Exception {
  const ServerSetupValidationException(this.message, {this.isPortError = false});

  final String message;

  /// The Port value is at fault: the screen opens Advanced options to show it.
  final bool isPortError;

  @override
  String toString() => message;
}

const defaultPrairieServerPort = 8090;

const serverHostRequiredMessage = 'Please enter a server host.';
const serverAddressInvalidMessage = 'Enter a valid server address.';
const serverPortInvalidMessage = 'Port must be a number between 1 and 65535.';

/// The URLs to probe, in order, for [rawInput] with Advanced options
/// [scheme] and [port] (blank = none). Throws
/// [ServerSetupValidationException] for a blank host, an address that isn't
/// one, or a bad port.
List<String> buildServerSetupCandidateUrls(
  String rawInput, {
  ServerSetupScheme scheme = ServerSetupScheme.auto,
  String port = '',
}) {
  final input = rawInput.trim();
  if (input.isEmpty) throw const ServerSetupValidationException(serverHostRequiredMessage);

  final parsed = _parseInput(input);
  final explicitPort = parsed.port ?? _parsePortField(port);
  final schemes = scheme.urlScheme != null
      ? [scheme.urlScheme!]
      : parsed.scheme != null
          ? [parsed.scheme!]
          : const ['https', 'http'];

  final candidates = [
    for (final s in schemes) _buildUrl(s, parsed.host, explicitPort, parsed.path),
  ];
  if (scheme == ServerSetupScheme.auto && parsed.scheme == null && explicitPort == null) {
    candidates.add(_buildUrl('http', parsed.host, defaultPrairieServerPort, parsed.path));
  }
  return candidates.toSet().toList();
}

/// True when the address will connect over plain HTTP: HTTP picked in
/// Advanced options, or Auto with an `http://` address. Auto with a bare
/// host tries HTTPS first, so it isn't flagged. Informational only.
bool serverSetupUsesCleartext(
  String rawInput, {
  ServerSetupScheme scheme = ServerSetupScheme.auto,
  String port = '',
}) {
  if (rawInput.trim().isEmpty) return false;
  if (scheme == ServerSetupScheme.http) return true;
  if (scheme == ServerSetupScheme.https) return false;
  try {
    final candidates = buildServerSetupCandidateUrls(rawInput, scheme: scheme, port: port);
    return candidates.length == 1 && candidates.first.startsWith('http://');
  } on ServerSetupValidationException {
    return false;
  }
}

class _ParsedInput {
  const _ParsedInput({required this.scheme, required this.host, required this.port, required this.path});

  final String? scheme;
  final String host;
  final int? port;
  final String path;
}

final _schemePrefix = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*)://');
final _hostName = RegExp(r'^[A-Za-z0-9._\-]+$');
final _ipv6Literal = RegExp(r'^[0-9A-Fa-f:.]+(%[A-Za-z0-9._\-]+)?$');
final _digits = RegExp(r'^[0-9]+$');

_ParsedInput _parseInput(String input) {
  String? scheme;
  var rest = input;
  final schemeMatch = _schemePrefix.firstMatch(input);
  if (schemeMatch != null) {
    scheme = schemeMatch.group(1)!.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const ServerSetupValidationException(serverAddressInvalidMessage);
    }
    rest = input.substring(schemeMatch.end);
  } else if (input.contains('://')) {
    throw const ServerSetupValidationException(serverAddressInvalidMessage);
  }

  // Authority ends at the path; a query or fragment is dropped.
  final end = rest.indexOf(RegExp(r'[/?#]'));
  final authority = end < 0 ? rest : rest.substring(0, end);
  var path = '';
  if (end >= 0 && rest[end] == '/') {
    final afterAuthority = rest.substring(end);
    final queryAt = afterAuthority.indexOf(RegExp(r'[?#]'));
    path = (queryAt < 0 ? afterAuthority : afterAuthority.substring(0, queryAt)).replaceFirst(RegExp(r'/+$'), '');
  }
  if (authority.isEmpty || authority.contains('@') || authority.contains(RegExp(r'\s'))) {
    throw const ServerSetupValidationException(serverAddressInvalidMessage);
  }

  String host;
  String? portText;
  if (authority.startsWith('[')) {
    final close = authority.indexOf(']');
    if (close < 0) throw const ServerSetupValidationException(serverAddressInvalidMessage);
    host = authority.substring(1, close);
    final after = authority.substring(close + 1);
    if (after.isNotEmpty) {
      if (!after.startsWith(':')) throw const ServerSetupValidationException(serverAddressInvalidMessage);
      portText = after.substring(1);
    }
    if (!_ipv6Literal.hasMatch(host)) throw const ServerSetupValidationException(serverAddressInvalidMessage);
  } else if (':'.allMatches(authority).length > 1) {
    // A bare IPv6 address: no port can be told apart from it.
    host = authority;
    if (!_ipv6Literal.hasMatch(host)) throw const ServerSetupValidationException(serverAddressInvalidMessage);
  } else {
    final colon = authority.indexOf(':');
    host = colon < 0 ? authority : authority.substring(0, colon);
    if (colon >= 0) portText = authority.substring(colon + 1);
    if (!_hostName.hasMatch(host)) throw const ServerSetupValidationException(serverAddressInvalidMessage);
  }

  int? port;
  // "host:" carries no port, as java.net.URI reads it.
  if (portText != null && portText.isNotEmpty) {
    if (!_digits.hasMatch(portText)) throw const ServerSetupValidationException(serverAddressInvalidMessage);
    // A typed `:0` is rejected, not dropped.
    port = _validPort(int.tryParse(portText));
  }
  return _ParsedInput(scheme: scheme, host: host, port: port, path: path);
}

int? _parsePortField(String port) {
  final trimmed = port.trim();
  if (trimmed.isEmpty) return null;
  if (!_digits.hasMatch(trimmed)) {
    throw const ServerSetupValidationException(serverPortInvalidMessage, isPortError: true);
  }
  return _validPort(int.tryParse(trimmed));
}

int _validPort(int? port) {
  if (port == null || port < 1 || port > 65535) {
    throw const ServerSetupValidationException(serverPortInvalidMessage, isPortError: true);
  }
  return port;
}

String _buildUrl(String scheme, String host, int? port, String path) {
  final authority = host.contains(':') ? '[$host]' : host;
  final portSuffix = port == null ? '' : ':$port';
  return '$scheme://${authority.toLowerCase()}$portSuffix$path';
}
