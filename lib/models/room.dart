import 'json_fields.dart';

class RoomDto {
  const RoomDto({
    required this.id,
    required this.name,
    required this.slug,
    required this.status,
    required this.queueLimit,
    required this.maxVotesPerUser,
    required this.qrTtlSeconds,
    required this.recalcIntervalSeconds,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String? slug;
  final String status;
  final int queueLimit;
  final int maxVotesPerUser;
  final int qrTtlSeconds;
  final int recalcIntervalSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory RoomDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'room');
    return RoomDto(
      id: JsonFields.string(json, 'id'),
      name: JsonFields.string(json, 'name'),
      slug: JsonFields.nullableString(json, 'slug'),
      status: JsonFields.string(json, 'status'),
      queueLimit: JsonFields.integer(json, 'queue_limit'),
      maxVotesPerUser: JsonFields.integer(json, 'max_votes_per_user'),
      qrTtlSeconds: JsonFields.integer(json, 'qr_ttl_seconds'),
      recalcIntervalSeconds: JsonFields.integer(
        json,
        'recalc_interval_seconds',
      ),
      createdAt: JsonFields.dateTime(json, 'created_at'),
      updatedAt: JsonFields.dateTime(json, 'updated_at'),
    );
  }
}
