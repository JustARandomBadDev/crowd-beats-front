import 'json_fields.dart';

class ReadinessDto {
  const ReadinessDto({required this.status});

  final String status;

  factory ReadinessDto.fromJson(Object? value) {
    final json = JsonFields.object(value, 'readiness');
    return ReadinessDto(status: JsonFields.string(json, 'status'));
  }
}
