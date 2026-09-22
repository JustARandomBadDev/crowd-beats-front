import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_failure.dart';
import '../../core/api/crowd_beats_api.dart';
import '../../core/config/app_providers.dart';
import '../../core/storage/session_storage.dart';
import '../../models/session.dart';

enum SessionPhase { checking, none, invalid, active, error }

class ActiveSession {
  const ActiveSession({
    required this.token,
    required this.id,
    required this.roomId,
    required this.nickname,
    this.roomName,
  });

  final String token;
  final String id;
  final String roomId;
  final String nickname;
  final String? roomName;
}

class SessionState {
  const SessionState({
    required this.phase,
    this.active,
    this.switching = false,
    this.busy = false,
    this.message,
    this.pendingJoin,
  });

  final SessionPhase phase;
  final ActiveSession? active;
  final bool switching;
  final bool busy;
  final String? message;
  final ActiveSession? pendingJoin;
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);

class SessionController extends Notifier<SessionState> {
  static const heartbeatInterval = Duration(seconds: 45);

  late CrowdBeatsApi _api;
  late SessionStorage _storage;
  Timer? _heartbeatTimer;
  bool _heartbeatInFlight = false;
  bool _disposed = false;
  int _heartbeatGeneration = 0;

  bool get heartbeatScheduled => _heartbeatTimer?.isActive ?? false;

  @override
  SessionState build() {
    _api = ref.read(crowdBeatsApiProvider);
    _storage = ref.read(sessionStorageProvider);
    ref.onDispose(() {
      _disposed = true;
      _stopHeartbeat();
    });
    return const SessionState(phase: SessionPhase.checking);
  }

  Future<void> bootstrap() async {
    if (state.busy) return;
    _stopHeartbeat();
    state = const SessionState(phase: SessionPhase.checking, busy: true);
    try {
      final token = await _storage.readToken();
      if (_disposed) return;
      if (token == null) {
        state = const SessionState(phase: SessionPhase.none);
        return;
      }
      if (token.isEmpty) {
        await _clearInvalidSession();
        return;
      }
      try {
        final response = await _api.getCurrentSession(token: token);
        if (_disposed) return;
        final session = response.data.session;
        final active = ActiveSession(
          token: token,
          id: session.id,
          roomId: session.roomId,
          nickname: session.nickname,
        );
        state = SessionState(phase: SessionPhase.active, active: active);
        _startHeartbeat();
      } on ApiFailure catch (failure) {
        if (_disposed) return;
        if (isInvalidSession(failure)) {
          await _clearInvalidSession();
        } else {
          state = SessionState(
            phase: SessionPhase.error,
            message: sessionErrorMessage(failure),
          );
        }
      }
    } on Object {
      if (_disposed) return;
      state = const SessionState(
        phase: SessionPhase.error,
        message: 'Could not access the saved session. Please retry.',
      );
    }
  }

  Future<void> join({required String qrCode, required String nickname}) async {
    if (state.busy || state.pendingJoin != null) return;
    final trimmedName = nickname.trim();
    if (qrCode.isEmpty) {
      state = SessionState(
        phase: state.phase,
        active: state.active,
        switching: state.switching,
        message: 'Scan the venue QR code first.',
      );
      return;
    }
    if (trimmedName.runes.isEmpty || trimmedName.runes.length > 32) {
      state = SessionState(
        phase: state.phase,
        active: state.active,
        switching: state.switching,
        message: 'Enter a nickname of 1 to 32 characters.',
      );
      return;
    }
    final previous = state;
    state = SessionState(
      phase: previous.phase,
      active: previous.active,
      switching: previous.switching,
      busy: true,
    );
    try {
      final response = await _api.joinRoom(
        JoinRoomRequestDto(
          qrCode: qrCode,
          nickname: trimmedName,
          sessionToken: previous.active?.token,
        ),
      );
      if (_disposed) return;
      final joined = response.data;
      final next = ActiveSession(
        token: joined.session.token,
        id: joined.session.id,
        roomId: joined.room.id,
        roomName: joined.room.name,
        nickname: joined.session.nickname,
      );
      // A successful switch can invalidate the old server session immediately.
      _stopHeartbeat();
      await _persistJoinedSession(next);
    } on ApiFailure catch (failure) {
      if (_disposed) return;
      state = SessionState(
        phase: previous.phase,
        active: previous.active,
        switching: previous.switching,
        message: joinErrorMessage(failure),
      );
      if (previous.active != null) _startHeartbeat();
    } on Object {
      if (_disposed) return;
      state = SessionState(
        phase: previous.phase,
        active: previous.active,
        switching: previous.switching,
        message: 'Could not join. Please retry.',
      );
      if (previous.active != null) _startHeartbeat();
    }
  }

  Future<void> _persistJoinedSession(ActiveSession next) async {
    try {
      await _storage.saveToken(next.token);
      if (_disposed) return;
      state = SessionState(phase: SessionPhase.active, active: next);
      _startHeartbeat();
    } on Object {
      if (_disposed) return;
      state = SessionState(
        phase: SessionPhase.error,
        pendingJoin: next,
        message:
            'Joined the room, but could not save the session. Retry saving.',
      );
    }
  }

  Future<void> retrySave() async {
    final pending = state.pendingJoin;
    if (pending == null || state.busy) return;
    state = SessionState(
      phase: SessionPhase.error,
      pendingJoin: pending,
      busy: true,
    );
    await _persistJoinedSession(pending);
  }

  void startRoomSwitch() {
    if (state.phase != SessionPhase.active || state.busy) return;
    state = SessionState(
      phase: SessionPhase.active,
      active: state.active,
      switching: true,
    );
  }

  void cancelRoomSwitch() {
    if (!state.switching || state.busy) return;
    state = SessionState(phase: SessionPhase.active, active: state.active);
  }

  Future<void> leave() async {
    final active = state.active;
    if (active == null || state.busy) return;
    _stopHeartbeat();
    state = SessionState(
      phase: SessionPhase.active,
      active: active,
      busy: true,
    );
    try {
      final response = await _api.leave(token: active.token);
      if (_disposed) return;
      if (!response.data.left) {
        state = SessionState(
          phase: SessionPhase.active,
          active: active,
          message: 'Unexpected backend response. Please retry leaving.',
        );
        _startHeartbeat();
        return;
      }
      await _clearInvalidSession(expired: false);
    } on ApiFailure catch (failure) {
      if (_disposed) return;
      if (isInvalidSession(failure)) {
        await _clearInvalidSession();
      } else {
        state = SessionState(
          phase: SessionPhase.active,
          active: active,
          message: 'Could not leave right now. Please retry.',
        );
        _startHeartbeat();
      }
    } on Object {
      if (_disposed) return;
      state = SessionState(
        phase: SessionPhase.active,
        active: active,
        message: 'Could not leave right now. Please retry.',
      );
      _startHeartbeat();
    }
  }

  Future<void> heartbeatNow() async {
    final active = state.active;
    if (active == null || _heartbeatInFlight || state.busy) return;
    final generation = _heartbeatGeneration;
    _heartbeatInFlight = true;
    try {
      await _api.heartbeat(
        token: active.token,
        request: HeartbeatRequestDto(roomId: active.roomId),
      );
    } on ApiFailure catch (failure) {
      if (_disposed ||
          state.busy ||
          _heartbeatGeneration != generation ||
          state.active?.token != active.token) {
        return;
      }
      if (isInvalidSession(failure)) {
        await _clearInvalidSession();
      }
      // A transient failure is retried at the next scheduled heartbeat.
    } on Object {
      // Retain the session and retry at the next scheduled heartbeat.
    } finally {
      _heartbeatInFlight = false;
    }
  }

  Future<void> invalidateFromServer({required String token}) async {
    if (state.active?.token != token || state.busy) return;
    await _clearInvalidSession();
  }

  Future<void> _clearInvalidSession({bool expired = true}) async {
    _stopHeartbeat();
    try {
      await _storage.clearSession();
      if (_disposed) return;
      state = SessionState(
        phase: expired ? SessionPhase.invalid : SessionPhase.none,
      );
    } on Object {
      if (_disposed) return;
      state = const SessionState(
        phase: SessionPhase.error,
        message: 'Could not clear the saved session. Please retry.',
      );
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => heartbeatNow());
  }

  void _stopHeartbeat() {
    _heartbeatGeneration++;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}

bool isInvalidSession(ApiFailure failure) =>
    failure.category == ApiFailureCategory.backend &&
    failure.statusCode == 401 &&
    failure.backendCode == 'UNAUTHORIZED';

String sessionErrorMessage(ApiFailure failure) {
  if (failure.category == ApiFailureCategory.transport ||
      failure.category == ApiFailureCategory.timeout) {
    return 'Network unavailable. Check your connection and retry.';
  }
  if (failure.statusCode == 503) {
    return 'Backend unavailable. Please retry shortly.';
  }
  if (failure.statusCode != null && failure.statusCode! >= 500) {
    return 'Unexpected server error. Please retry.';
  }
  if (failure.category == ApiFailureCategory.protocol ||
      failure.category == ApiFailureCategory.invalidJson) {
    return 'Unexpected backend response. Please retry.';
  }
  return 'Could not check the session. Please retry.';
}

String joinErrorMessage(ApiFailure failure) {
  switch (failure.backendCode) {
    case 'INVALID_QR_CODE':
      return 'This QR code is invalid or expired. Scan a new code.';
    case 'VALIDATION_ERROR':
      return 'Check your nickname and scan the QR code again.';
    case 'ROOM_NOT_ACTIVE':
      return 'This room is unavailable right now.';
  }
  return sessionErrorMessage(failure);
}
