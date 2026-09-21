import 'package:flutter_test/flutter_test.dart';
import 'package:groopx/features/calls/data/call_api.dart';
import 'package:groopx/features/chat/domain/chat_models.dart';

void main(){
  test('shared media parses server payload',(){final item=SharedMediaItem.fromJson({'id':'media-1','kind':'image','attachment':{'url':'https://cdn.example/photo.jpg','file_name':'photo.jpg'},'created_at':'2026-09-21T10:00:00Z'});expect(item.name,'photo.jpg');expect(item.url,contains('photo.jpg'));});
  test('call history parses server payload',(){final item=CallHistoryItem.fromJson({'id':'call-1','conversation_id':'conversation-1','title':'Design Team','kind':'video','status':'ended','avatar_url':'','started_at':'2026-09-21T10:00:00Z'});expect(item.kind,'video');expect(item.title,'Design Team');});
}
