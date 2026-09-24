import '../../models/health.dart';
import '../../models/queue.dart';
import '../../models/room.dart';
import '../../models/session.dart';
import '../../models/track.dart';
import 'api_client.dart';
import 'api_failure.dart';
import 'api_paths.dart';

class CrowdBeatsApi {
  const CrowdBeatsApi(this._client);

  final ApiClient _client;

  Future<ApiResponse<ReadinessDto>> readiness() => _client.get(
    ApiPaths.readiness,
    additionalDataStatuses: const {503},
    decode: ReadinessDto.fromJson,
  );

  Future<ApiResponse<JoinRoomResponseDto>> joinRoom(
    JoinRoomRequestDto request,
  ) => _client.post(
    ApiPaths.joinByQr,
    body: request.toJson(),
    decode: JoinRoomResponseDto.fromJson,
  );

  Future<ApiResponse<RoomDto>> getRoom(String roomId) =>
      _client.get(ApiPaths.room(roomId), decode: RoomDto.fromJson);

  Future<ApiResponse<CurrentSessionResponseDto>> getCurrentSession({
    required String token,
  }) => _client.get(
    ApiPaths.currentSession,
    bearerToken: token,
    decode: CurrentSessionResponseDto.fromJson,
  );

  Future<ApiResponse<HeartbeatResponseDto>> heartbeat({
    required String token,
    HeartbeatRequestDto request = const HeartbeatRequestDto(),
  }) => _client.post(
    ApiPaths.heartbeat,
    bearerToken: token,
    body: request.toJson(),
    decode: HeartbeatResponseDto.fromJson,
  );

  Future<ApiResponse<LeaveResponseDto>> leave({required String token}) =>
      _client.post(
        ApiPaths.leave,
        bearerToken: token,
        decode: LeaveResponseDto.fromJson,
      );

  Future<ApiResponse<QueueSnapshotDto>> getQueue(String roomId) =>
      _client.get(ApiPaths.queue(roomId), decode: QueueSnapshotDto.fromJson);

  Future<ApiResponse<SpotifySearchResponseDto>> searchSpotify({
    required String token,
    required String query,
  }) => _client.get(
    ApiPaths.spotifySearch,
    bearerToken: token,
    queryParameters: {'q': query},
    decode: SpotifySearchResponseDto.fromJson,
  );

  Future<ApiResponse<TrackProposalResponseDto>> proposeTrack({
    required String roomId,
    required String token,
    required TrackProposalRequestDto request,
  }) => _client.post(
    ApiPaths.tracks(roomId),
    bearerToken: token,
    body: request.toJson(),
    decode: TrackProposalResponseDto.fromJson,
  );

  Future<ApiResponse<VoteResponseDto>> vote({
    required String roomId,
    required String token,
    required VoteRequestDto request,
  }) async {
    final response = await _client.post(
      ApiPaths.votes(roomId),
      bearerToken: token,
      body: request.toJson(),
      decode: VoteResponseDto.fromJson,
    );
    final vote = response.data;
    if (!vote.voteAdded || vote.roomTrackId != request.roomTrackId) {
      throw ApiFailure(
        ApiFailureCategory.protocol,
        statusCode: response.statusCode,
        meta: response.meta,
        cause: const FormatException('Invalid vote confirmation'),
      );
    }
    return response;
  }
}
