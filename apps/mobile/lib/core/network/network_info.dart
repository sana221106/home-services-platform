import 'dart:async';

import 'package:dio/dio.dart';

/// Reachability of the backend, inferred from real request outcomes.
///
/// Deliberately not built on a connectivity plugin: a device can be attached to
/// a Wi-Fi network with no internet, so the only honest signal is whether a
/// request actually failed. `connectivity_plus` would report "connected" while
/// every call still times out, which is exactly the case the customer needs to
/// be told about (§30).
class NetworkInfo {
  NetworkInfo({Duration? probeInterval})
    : _probeInterval = probeInterval ?? const Duration(minutes: 2);

  final Duration _probeInterval;

  bool _online = true;
  bool _probeInFlight = false;
  DateTime? _lastCheckedAt;
  Stream<bool>? _changes;

  /// Last known reachability. Starts optimistic so the first screen is not
  /// gated behind a probe.
  bool get isOnline => _online;

  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// Emits on every offline/online transition.
  Stream<bool> get onStatusChange => _changes ??= _controller.stream;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  /// Records the outcome of a real request.
  ///
  /// Every data source calls this from its error path, so connectivity stays
  /// correct without an extra HTTP call or a plugin.
  void recordResult(Object error) {
    _lastCheckedAt = DateTime.now();
    _emit(!_isDefinitelyOffline(error));
  }

  /// Re-checks reachability after a failure, without waiting out [_probeInterval]
  /// when the caller already knows the network dropped.
  void markOffline() {
    _lastCheckedAt = DateTime.now();
    _emit(false);
  }

  void markOnline() {
    _lastCheckedAt = DateTime.now();
    _emit(true);
  }

  /// Whether the last result is stale enough to justify another probe.
  bool get isStale {
    final DateTime? checked = _lastCheckedAt;
    if (checked == null) return true;
    return DateTime.now().difference(checked) >= _probeInterval;
  }

  /// Reserved for an explicit connectivity check; guarded so concurrent callers
  /// share one probe instead of stampeding the backend (§30).
  Future<bool> probe(Future<bool> Function() request) async {
    if (_probeInFlight) return _online;
    _probeInFlight = true;
    try {
      final bool reachable = await request();
      markOnline();
      return reachable;
    } catch (_) {
      markOffline();
      return false;
    } finally {
      _probeInFlight = false;
    }
  }

  static bool _isDefinitelyOffline(Object error) =>
      error is DioException &&
      (error.type == DioExceptionType.connectionError ||
          error.type == DioExceptionType.connectionTimeout);

  void _emit(bool value) {
    if (_online == value) return;
    _online = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  void dispose() {
    _controller.close();
  }
}
