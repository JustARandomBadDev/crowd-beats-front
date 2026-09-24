import 'json_fields.dart';
import 'room.dart';

class JoinRoomRequestDto {
  const JoinRoomRequestDto({
    required this.qrCode,
    required this.nickname,
    this.sessionToken,
  });

  final String qrCode;
  final String nickname;
  final String? sessionToken;

  Map<String, dynamic> toJson() => {
    'qr_code': qrCode,
    'nickname': nickname,
    if (sessionToken != null) 'session_token': sessionToken,
  };
}

class JoinedSessionDto {
  const JoinedSessionDto({
    required this.id,
    required this.nickname,
    required this.role,
    required this.token,
  });

  final String id;
  final String nickname;
  final String role;
  final String token;

  factory JoinedSessionDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'session');
    return JoinedSessionDto(
      id: JsonFields.string(json, 'id'),
      nickname: JsonFields.string(json, 'nickname'),
      role: JsonFields.string(json, 'role'),
      token: JsonFields.string(json, 'token'),
    );
  }
}

class WebSocketLocationDto {
  const WebSocketLocationDto({required this.url});

  final String url;

  factory WebSocketLocationDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'ws');
    return WebSocketLocationDto(url: JsonFields.string(json, 'url'));
  }
}

class JoinRoomResponseDto {
  const JoinRoomResponseDto({
    required this.room,
    required this.session,
    required this.ws,
  });

  final RoomDto room;
  final JoinedSessionDto session;
  final WebSocketLocationDto ws;

  factory JoinRoomResponseDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'join');
    return JoinRoomResponseDto(
      room: RoomDto.fromJson(JsonFields.nested(json, 'room')),
      session: JoinedSessionDto.fromJson(JsonFields.nested(json, 'session')),
      ws: WebSocketLocationDto.fromJson(JsonFields.nested(json, 'ws')),
    );
  }
}

class CurrentSessionDto {
  const CurrentSessionDto({
    required this.id,
    required this.roomId,
    required this.nickname,
    required this.role,
    required this.status,
    required this.lastSeenAt,
  });

  final String id;
  final String roomId;
  final String nickname;
  final String role;
  final String status;
  final DateTime lastSeenAt;

  factory CurrentSessionDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'session');
    return CurrentSessionDto(
      id: JsonFields.string(json, 'id'),
      roomId: JsonFields.string(json, 'room_id'),
      nickname: JsonFields.string(json, 'nickname'),
      role: JsonFields.string(json, 'role'),
      status: JsonFields.string(json, 'status'),
      lastSeenAt: JsonFields.dateTime(json, 'last_seen_at'),
    );
  }
}

class CurrentSessionResponseDto {
  const CurrentSessionResponseDto({required this.session});

  final CurrentSessionDto session;

  factory CurrentSessionResponseDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'current session response');
    return CurrentSessionResponseDto(
      session: CurrentSessionDto.fromJson(JsonFields.nested(json, 'session')),
    );
  }
}

class HeartbeatRequestDto {
  const HeartbeatRequestDto({this.roomId});

  final String? roomId;

  Map<String, dynamic> toJson() => {if (roomId != null) 'room_id': roomId};
}

class HeartbeatResponseDto {
  const HeartbeatResponseDto({required this.updated});

  final bool updated;

  factory HeartbeatResponseDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'heartbeat');
    return HeartbeatResponseDto(updated: JsonFields.boolean(json, 'updated'));
  }
}

class LeaveResponseDto {
  const LeaveResponseDto({required this.left});

  final bool left;

  factory LeaveResponseDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'leave');
    return LeaveResponseDto(left: JsonFields.boolean(json, 'left'));
  }
}
