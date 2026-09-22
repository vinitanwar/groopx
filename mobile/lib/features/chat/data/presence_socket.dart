import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../auth/data/auth_api.dart';

class PresenceSocket {
  PresenceSocket._();
  static final instance=PresenceSocket._();
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _retry;
  bool _stopped=false;

  Future<void> start() async {
    _stopped=false;
    await _connect();
  }
  Future<void> _connect() async {
    _retry?.cancel();
    final token=await AuthSession.instance.accessToken;
    if(token==null||_stopped)return;
    final base=const String.fromEnvironment('WS_BASE_URL',defaultValue:'ws://10.0.2.2:8080');
    final uri=Uri.parse('$base/api/v1/ws').replace(queryParameters:{'access_token':token});
    try{
      final channel=WebSocketChannel.connect(uri);await channel.ready;
      _channel=channel;
      _subscription=channel.stream.listen((_) {},onError:(_)=>_schedule(),onDone:_schedule,cancelOnError:true);
    }catch(_){_schedule();}
  }
  void _schedule(){if(_stopped)return;_retry?.cancel();_retry=Timer(const Duration(seconds:3),_connect);}
  Future<void> stop() async{_stopped=true;_retry?.cancel();await _subscription?.cancel();await _channel?.sink.close();_channel=null;}
}
