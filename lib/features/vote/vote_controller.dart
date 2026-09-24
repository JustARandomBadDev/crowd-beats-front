import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_failure.dart';
import '../../core/api/crowd_beats_api.dart';
import '../../core/config/app_providers.dart';
import '../../models/track.dart';
import '../room/room_controller.dart';
import '../session/session_controller.dart';

enum VotePhase {
  submitting,
  accepted,
  alreadyVoted,
  limitReached,
  trackInactive,
  error,
}

class TrackVoteState {
  const TrackVoteState({
    required this.phase,
    required this.message,
    this.response,
    this.failure,
  });

  final VotePhase phase;
  final String message;
  final VoteResponseDto? response;
  final ApiFailure? failure;

  bool get submitting => phase == VotePhase.submitting;
  bool get voteConfirmed => phase == VotePhase.accepted;
}

class VoteState {
  const VoteState({this.actions = const {}, this.votesRemaining});

  final Map<String, TrackVoteState> actions;
  final int? votesRemaining;

  TrackVoteState? actionFor(String roomTrackId) => actions[roomTrackId];

  VoteState withAction(
    String roomTrackId,
    TrackVoteState action, {
    int? votesRemaining,
    bool replaceVotesRemaining = false,
  }) {
    return VoteState(
      actions: Map.unmodifiable({...actions, roomTrackId: action}),
      votesRemaining: replaceVotesRemaining
          ? votesRemaining
          : this.votesRemaining,
    );
  }
}

final voteControllerProvider = NotifierProvider.autoDispose
    .family<VoteController, VoteState, RoomSessionKey>(VoteController.new);

class VoteController extends Notifier<VoteState> {
  VoteController(this.key);

  final RoomSessionKey key;

  late CrowdBeatsApi _api;
  final Set<String> _inFlight = {};
  bool _disposed = false;
  bool _waveHadConcurrency = false;
  int? _waveVotesRemaining;

  @override
  VoteState build() {
    _api = ref.read(crowdBeatsApiProvider);
    ref.onDispose(() {
      _disposed = true;
      _inFlight.clear();
    });
    return const VoteState();
  }

  Future<void> vote(String roomTrackId) async {
    if (_inFlight.contains(roomTrackId) || !_matchesActiveSession()) return;
    if (_inFlight.isEmpty) {
      _waveHadConcurrency = false;
      _waveVotesRemaining = null;
    } else {
      _waveHadConcurrency = true;
    }
    _inFlight.add(roomTrackId);
    state = state.withAction(
      roomTrackId,
      const TrackVoteState(
        phase: VotePhase.submitting,
        message: 'Submitting vote…',
      ),
    );

    try {
      final response = await _api.vote(
        roomId: key.roomId,
        token: key.token,
        request: VoteRequestDto(roomTrackId: roomTrackId),
      );
      if (!_canApply()) return;
      final vote = response.data;
      final votesRemaining = _confirmedVotesRemaining(vote.votesRemaining);
      state = state.withAction(
        roomTrackId,
        TrackVoteState(
          phase: VotePhase.accepted,
          message: _successMessage(votesRemaining),
          response: vote,
        ),
        votesRemaining: votesRemaining,
        replaceVotesRemaining: true,
      );
    } on ApiFailure catch (failure) {
      if (!_canApply()) return;
      if (isInvalidSession(failure)) {
        await ref
            .read(sessionControllerProvider.notifier)
            .invalidateFromServer(token: key.token);
        return;
      }
      state = state.withAction(
        roomTrackId,
        TrackVoteState(
          phase: voteFailurePhase(failure),
          message: voteFailureMessage(failure),
          failure: failure,
        ),
      );
    } on Object {
      if (!_canApply()) return;
      state = state.withAction(
        roomTrackId,
        const TrackVoteState(
          phase: VotePhase.error,
          message: 'Could not submit this vote. Please retry.',
        ),
      );
    } finally {
      _inFlight.remove(roomTrackId);
      if (_inFlight.isEmpty) {
        _waveHadConcurrency = false;
        _waveVotesRemaining = null;
      }
    }
  }

  int _confirmedVotesRemaining(int incoming) {
    if (!_waveHadConcurrency) return incoming;
    _waveVotesRemaining = _waveVotesRemaining == null
        ? incoming
        : math.min(_waveVotesRemaining!, incoming);
    return _waveVotesRemaining!;
  }

  bool _canApply() => !_disposed && _matchesActiveSession();

  bool _matchesActiveSession() {
    final session = ref.read(sessionControllerProvider);
    final active = session.active;
    return session.phase == SessionPhase.active &&
        !session.switching &&
        !session.busy &&
        active?.roomId == key.roomId &&
        active?.token == key.token;
  }
}

VotePhase voteFailurePhase(ApiFailure failure) {
  return switch (failure.backendCode) {
    'ALREADY_VOTED_FOR_TRACK' => VotePhase.alreadyVoted,
    'VOTE_LIMIT_REACHED' => VotePhase.limitReached,
    'ROOM_TRACK_NOT_ACTIVE' => VotePhase.trackInactive,
    _ => VotePhase.error,
  };
}

String voteFailureMessage(ApiFailure failure) {
  switch (failure.backendCode) {
    case 'ALREADY_VOTED_FOR_TRACK':
      return 'You already voted for this track.';
    case 'VOTE_LIMIT_REACHED':
      return 'You have reached this room’s vote limit.';
    case 'ROOM_TRACK_NOT_ACTIVE':
      return 'This track is no longer available for voting.';
    case 'ROOM_NOT_ACTIVE':
      return 'This room is not accepting votes right now.';
    case 'SESSION_NOT_IN_ROOM':
      return 'Your session is no longer active in this room.';
    case 'INVALID_ID':
    case 'INVALID_JSON':
      return 'The backend rejected the vote request.';
  }
  if (failure.category == ApiFailureCategory.transport) {
    return 'Network unavailable. Check your connection and retry.';
  }
  if (failure.category == ApiFailureCategory.timeout) {
    return 'The vote request timed out. Please retry.';
  }
  if (failure.category == ApiFailureCategory.protocol ||
      failure.category == ApiFailureCategory.invalidJson) {
    return 'The backend returned an unexpected vote response.';
  }
  return 'Could not submit this vote. Please retry.';
}

String _successMessage(int votesRemaining) {
  final noun = votesRemaining == 1 ? 'vote' : 'votes';
  return 'Vote counted. $votesRemaining $noun remaining.';
}
