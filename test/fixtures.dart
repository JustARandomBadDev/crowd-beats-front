import 'dart:convert';

import 'package:http/http.dart' as http;

final roomJson = <String, dynamic>{
  'id': '11111111-1111-4111-8111-111111111111',
  'name': 'Le Bar',
  'slug': null,
  'status': 'active',
  'queue_limit': 20,
  'max_votes_per_user': 5,
  'qr_ttl_seconds': 14400,
  'recalc_interval_seconds': 10,
  'created_at': '2026-09-21T08:00:00Z',
  'updated_at': '2026-09-21T08:00:00Z',
};

final spotifyTrackJson = <String, dynamic>{
  'spotify_track_id': '0123456789ABCDEFGHIJKL',
  'title': 'Exemple',
  'artist_names': 'Artiste',
  'album_name': 'Album',
  'duration_ms': 180000,
  'image_url': '',
  'preview_url': '',
  'uri': 'spotify:track:0123456789ABCDEFGHIJKL',
};

http.Response apiResponse(Object? data, {int status = 200}) {
  return http.Response(
    jsonEncode({'data': data, 'error': null, 'meta': {}}),
    status,
  );
}

http.Response apiError(String code, {int status = 400}) {
  return http.Response(
    jsonEncode({
      'data': null,
      'error': {'code': code, 'message': 'backend detail'},
      'meta': {'request_id': 'test'},
    }),
    status,
  );
}
