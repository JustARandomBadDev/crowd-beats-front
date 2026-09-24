import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_failure.dart';
import '../../core/api/crowd_beats_api.dart';
import '../../core/config/app_providers.dart';
import '../../models/track.dart';
import '../session/session_controller.dart';

class TrackSearchSession {
  const TrackSearchSession({required this.roomId, required this.token});

  final String roomId;
  final String token;

  @override
  bool operator ==(Object other) =>
      other is TrackSearchSession &&
      other.roomId == roomId &&
      other.token == token;

  @override
  int get hashCode => Object.hash(roomId, token);
}

enum SearchPhase { initial, loading, results, error }

enum ProposalPhase { idle, submitting, accepted, duplicate, error }

class TrackSearchState {
  const TrackSearchState({
    this.searchPhase = SearchPhase.initial,
    this.query = '',
    this.results = const [],
    this.searchMessage,
    this.searchFailure,
    this.proposalPhase = ProposalPhase.idle,
    this.proposingSpotifyTrackId,
    this.proposalMessage,
    this.proposalFailure,
    this.proposal,
  });

  final SearchPhase searchPhase;
  final String query;
  final List<SpotifyTrackDto> results;
  final String? searchMessage;
  final ApiFailure? searchFailure;
  final ProposalPhase proposalPhase;
  final String? proposingSpotifyTrackId;
  final String? proposalMessage;
  final ApiFailure? proposalFailure;
  final TrackProposalResponseDto? proposal;

  bool get searching => searchPhase == SearchPhase.loading;
  bool get proposing => proposalPhase == ProposalPhase.submitting;

  TrackSearchState copyWith({
    SearchPhase? searchPhase,
    String? query,
    List<SpotifyTrackDto>? results,
    Object? searchMessage = _unchanged,
    Object? searchFailure = _unchanged,
    ProposalPhase? proposalPhase,
    Object? proposingSpotifyTrackId = _unchanged,
    Object? proposalMessage = _unchanged,
    Object? proposalFailure = _unchanged,
    Object? proposal = _unchanged,
  }) {
    return TrackSearchState(
      searchPhase: searchPhase ?? this.searchPhase,
      query: query ?? this.query,
      results: results ?? this.results,
      searchMessage: identical(searchMessage, _unchanged)
          ? this.searchMessage
          : searchMessage as String?,
      searchFailure: identical(searchFailure, _unchanged)
          ? this.searchFailure
          : searchFailure as ApiFailure?,
      proposalPhase: proposalPhase ?? this.proposalPhase,
      proposingSpotifyTrackId: identical(proposingSpotifyTrackId, _unchanged)
          ? this.proposingSpotifyTrackId
          : proposingSpotifyTrackId as String?,
      proposalMessage: identical(proposalMessage, _unchanged)
          ? this.proposalMessage
          : proposalMessage as String?,
      proposalFailure: identical(proposalFailure, _unchanged)
          ? this.proposalFailure
          : proposalFailure as ApiFailure?,
      proposal: identical(proposal, _unchanged)
          ? this.proposal
          : proposal as TrackProposalResponseDto?,
    );
  }
}

const _unchanged = Object();

final trackSearchControllerProvider = NotifierProvider.autoDispose
    .family<TrackSearchController, TrackSearchState, TrackSearchSession>(
      TrackSearchController.new,
    );

class TrackSearchController extends Notifier<TrackSearchState> {
  TrackSearchController(this.session);

  final TrackSearchSession session;

  late CrowdBeatsApi _api;
  bool _disposed = false;
  bool _proposalInFlight = false;
  int _searchGeneration = 0;

  @override
  TrackSearchState build() {
    _api = ref.read(crowdBeatsApiProvider);
    ref.onDispose(() {
      _disposed = true;
      _searchGeneration++;
    });
    return const TrackSearchState();
  }

  Future<void> search(String rawQuery) async {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      state = state.copyWith(
        searchPhase: SearchPhase.initial,
        query: '',
        results: const [],
        searchMessage: 'Enter a song, artist, or album.',
        searchFailure: null,
      );
      return;
    }
    if (state.searching && state.query == query) return;

    final generation = ++_searchGeneration;
    state = state.copyWith(
      searchPhase: SearchPhase.loading,
      query: query,
      searchMessage: null,
      searchFailure: null,
    );
    try {
      final response = await _api.searchSpotify(
        token: session.token,
        query: query,
      );
      if (!_canApply(generation)) return;
      state = state.copyWith(
        searchPhase: SearchPhase.results,
        results: response.data.items,
        searchMessage: null,
        searchFailure: null,
      );
    } on ApiFailure catch (failure) {
      if (_disposed || !_matchesActiveSession()) return;
      if (isInvalidSession(failure)) {
        await ref
            .read(sessionControllerProvider.notifier)
            .invalidateFromServer(token: session.token);
        return;
      }
      if (generation != _searchGeneration) return;
      state = state.copyWith(
        searchPhase: SearchPhase.error,
        searchMessage: searchFailureMessage(failure),
        searchFailure: failure,
      );
    } on Object {
      if (!_canApply(generation)) return;
      state = state.copyWith(
        searchPhase: SearchPhase.error,
        searchMessage: 'Could not search right now. Please retry.',
        searchFailure: null,
      );
    }
  }

  Future<void> retrySearch() => search(state.query);

  Future<void> propose(SpotifyTrackDto track) async {
    if (_proposalInFlight || !_matchesActiveSession()) return;
    _proposalInFlight = true;
    state = state.copyWith(
      proposalPhase: ProposalPhase.submitting,
      proposingSpotifyTrackId: track.spotifyTrackId,
      proposalMessage: null,
      proposalFailure: null,
      proposal: null,
    );
    try {
      final response = await _api.proposeTrack(
        roomId: session.roomId,
        token: session.token,
        request: TrackProposalRequestDto(spotifyTrackId: track.spotifyTrackId),
      );
      if (_disposed || !_matchesActiveSession()) return;
      final proposal = response.data;
      if (proposal.duplicate) {
        state = state.copyWith(
          proposalPhase: ProposalPhase.duplicate,
          proposingSpotifyTrackId: null,
          proposalMessage: 'This track is already in the queue.',
          proposalFailure: null,
          proposal: proposal,
        );
      } else {
        state = state.copyWith(
          proposalPhase: ProposalPhase.accepted,
          proposingSpotifyTrackId: null,
          proposalMessage:
              'Track proposed. The queue will update when the room syncs.',
          proposalFailure: null,
          proposal: proposal,
        );
      }
    } on ApiFailure catch (failure) {
      if (_disposed || !_matchesActiveSession()) return;
      if (isInvalidSession(failure)) {
        await ref
            .read(sessionControllerProvider.notifier)
            .invalidateFromServer(token: session.token);
        return;
      }
      state = state.copyWith(
        proposalPhase: ProposalPhase.error,
        proposingSpotifyTrackId: null,
        proposalMessage: proposalFailureMessage(failure),
        proposalFailure: failure,
        proposal: null,
      );
    } on Object {
      if (_disposed || !_matchesActiveSession()) return;
      state = state.copyWith(
        proposalPhase: ProposalPhase.error,
        proposingSpotifyTrackId: null,
        proposalMessage: 'Could not propose this track. Please retry.',
        proposalFailure: null,
        proposal: null,
      );
    } finally {
      _proposalInFlight = false;
    }
  }

  bool _canApply(int generation) =>
      !_disposed && generation == _searchGeneration && _matchesActiveSession();

  bool _matchesActiveSession() {
    final active = ref.read(sessionControllerProvider).active;
    return active?.roomId == session.roomId && active?.token == session.token;
  }
}

String searchFailureMessage(ApiFailure failure) {
  switch (failure.backendCode) {
    case 'SPOTIFY_RATE_LIMITED':
      return 'Music search is temporarily busy. Please retry shortly.';
    case 'SPOTIFY_UNAVAILABLE':
      return 'Music search is temporarily unavailable. Please retry.';
    case 'VALIDATION_ERROR':
      return 'Enter a search term and try again.';
  }
  if (failure.category == ApiFailureCategory.transport) {
    return 'Network unavailable. Check your connection and retry.';
  }
  if (failure.category == ApiFailureCategory.timeout) {
    return 'The search timed out. Please retry.';
  }
  if (failure.category == ApiFailureCategory.protocol ||
      failure.category == ApiFailureCategory.invalidJson) {
    return 'The backend returned an unexpected search response.';
  }
  return 'Could not search right now. Please retry.';
}

String proposalFailureMessage(ApiFailure failure) {
  switch (failure.backendCode) {
    case 'QUEUE_FULL':
      return 'The queue is full. Try again after a track leaves the queue.';
    case 'ROOM_NOT_ACTIVE':
      return 'This room is not accepting tracks right now.';
    case 'SESSION_NOT_IN_ROOM':
      return 'Your session is no longer active in this room.';
    case 'INVALID_SPOTIFY_TRACK_ID':
    case 'SPOTIFY_TRACK_NOT_FOUND':
      return 'This track is no longer available to propose.';
    case 'SPOTIFY_RATE_LIMITED':
      return 'Spotify is temporarily busy. Please retry shortly.';
    case 'SPOTIFY_UNAVAILABLE':
      return 'Spotify is temporarily unavailable. Please retry.';
    case 'NOT_FOUND':
      return 'This room is no longer available.';
    case 'INVALID_ID':
    case 'INVALID_JSON':
      return 'The backend rejected the proposal request.';
  }
  if (failure.category == ApiFailureCategory.transport) {
    return 'Network unavailable. Check your connection and retry.';
  }
  if (failure.category == ApiFailureCategory.timeout) {
    return 'The proposal timed out. Please retry.';
  }
  if (failure.category == ApiFailureCategory.protocol ||
      failure.category == ApiFailureCategory.invalidJson) {
    return 'The backend returned an unexpected proposal response.';
  }
  return 'Could not propose this track. Please retry.';
}
