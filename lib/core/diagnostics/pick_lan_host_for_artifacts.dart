/// Picks a LAN host for diagnostics artifact upload.
///
/// The LAN TCP port may be reachable while the artifact HTTP endpoint is served
/// by a different process (e.g. port collision), leading to 404. To avoid this,
/// prefer hosts that pass `/artifact/info` probe.
Future<String?> pickLanHostForArtifacts({
  required List<String> rankedHosts,
  required Map<String, bool> reachable,
  required Future<bool> Function(String host) probeArtifacts,
}) async {
  for (final host in rankedHosts) {
    if (reachable[host] != true) continue;
    if (await probeArtifacts(host)) return host;
  }

  for (final host in rankedHosts) {
    if (reachable[host] == true) return host;
  }
  return rankedHosts.isEmpty ? null : rankedHosts.first;
}

