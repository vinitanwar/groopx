import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/chat_models.dart';
import 'chat_api.dart';

class LiveLocationService extends ChangeNotifier {
  LiveLocationService._();
  static final instance=LiveLocationService._();

  final Map<String,LiveLocationSession> _sessions={};
  StreamSubscription<Position>? _positionSubscription;
  Timer? _expiryTimer;
  Timer? _trackingRetryTimer;
  Timer? _initializationRetryTimer;
  Position? _pendingPosition;
  bool _syncing=false;
  bool _initialized=false;
  Completer<void>? _initialization;
  int _generation=0;
  String? _trackingKey;

  List<LiveLocationSession> get sessions=>List.unmodifiable(_sessions.values);
  bool isSharingMessage(String messageId)=>_sessions.values.any((item)=>item.messageId==messageId&&item.active);

  Future<void> initialize()async{
    if(_initialized)return;
    final pending=_initialization;
    if(pending!=null){await pending.future;if(!_initialized)await initialize();return;}
    final completion=Completer<void>();
    final generation=_generation;
    _initialization=completion;
    try{
      final trackingKey=await _deviceTrackingKey();
      final active=await ChatApi.instance.activeLiveLocations(trackingKey);
      if(generation!=_generation)return;
      _replaceSessions(active);
      if(_sessions.isNotEmpty)await _ensureTracking();
      if(generation==_generation){_initialized=true;_initializationRetryTimer?.cancel();_initializationRetryTimer=null;}
    }catch(_){if(generation==_generation)_scheduleInitializationRetry();}
    finally{if(identical(_initialization,completion))_initialization=null;if(!completion.isCompleted)completion.complete();}
  }

  Future<LiveLocationStartResult> start(String conversationId,int durationSeconds)async{
    await initialize();
    if(!_initialized)throw StateError('Live location service connect nahi hui. Retry karein.');
    final generation=_generation;
    await _ensureLocationPermission();
    final position=await Geolocator.getCurrentPosition(locationSettings:const LocationSettings(accuracy:LocationAccuracy.high,timeLimit:Duration(seconds:20)));
    final trackingKey=await _deviceTrackingKey();
    final result=await ChatApi.instance.startLiveLocation(conversationId,latitude:position.latitude,longitude:position.longitude,accuracyMeters:position.accuracy,durationSeconds:durationSeconds,trackingKey:trackingKey);
    if(generation!=_generation){try{await ChatApi.instance.stopLiveLocation(result.session.id);}catch(_){}throw StateError('Session change hone ki wajah se live location start nahi hui.');}
    _sessions.removeWhere((_,item)=>item.conversationId==conversationId);
    _sessions[result.session.id]=result.session;
    _initialized=true;
    _armExpiryTimer();
    try{
      await _ensureTracking();
    }catch(failure){
      try{await ChatApi.instance.stopLiveLocation(result.session.id);}catch(_){}
      _sessions.remove(result.session.id);
      _armExpiryTimer();
      rethrow;
    }
    notifyListeners();
    return result;
  }

  Future<void> suspend({bool stopSharing=false})async{
    final trackingKey=stopSharing?await _deviceTrackingKey():null;
    _generation++;
    _initialization=null;
    _expiryTimer?.cancel();
    _expiryTimer=null;
    _pendingPosition=null;
    _trackingRetryTimer?.cancel();
    _trackingRetryTimer=null;
    _initializationRetryTimer?.cancel();
    _initializationRetryTimer=null;
    _sessions.clear();
    await _positionSubscription?.cancel();
    _positionSubscription=null;
    if(trackingKey!=null){try{await ChatApi.instance.stopActiveLiveLocations(trackingKey);}catch(_){}}
    _sessions.clear();
    _initialized=false;
    notifyListeners();
  }

  Future<void> stop(String id)async{
    await ChatApi.instance.stopLiveLocation(id);
    _sessions.remove(id);
    await _stopTrackingWhenIdle();
    _armExpiryTimer();
    notifyListeners();
  }

  void handleRealtimeEvent(Map<String,dynamic> event){
    if(event['type']!='live_location_update'||event['mine']!=true)return;
    final id=event['live_location_id']?.toString()??'';
    final attachment=event['attachment'];
    if(id.isEmpty||attachment is! Map)return;
    final active=attachment['active']==true;
    final expiresAt=DateTime.tryParse(attachment['expires_at']?.toString()??'')?.toLocal();
    if(!active||expiresAt==null||!expiresAt.isAfter(DateTime.now())){
      _sessions.remove(id);
      unawaited(_stopTrackingWhenIdle());
      _armExpiryTimer();
      notifyListeners();
      return;
    }
    final current=_sessions[id];
    if(current!=null){
      _sessions[id]=LiveLocationSession(id:id,messageId:current.messageId,conversationId:current.conversationId,expiresAt:expiresAt,updatedAt:DateTime.tryParse(attachment['updated_at']?.toString()??'')?.toLocal()??DateTime.now());
      _armExpiryTimer();
      notifyListeners();
    }
  }

  Future<void> _ensureLocationPermission()async{
    if(!await Geolocator.isLocationServiceEnabled())throw StateError('Phone location service off hai.');
    var permission=await Geolocator.checkPermission();
    if(permission==LocationPermission.denied)permission=await Geolocator.requestPermission();
    if(permission==LocationPermission.denied)throw StateError('Location permission deny hui.');
    if(permission==LocationPermission.deniedForever)throw StateError('Settings se location permission allow karein.');
  }

  LocationSettings get _streamSettings{
    if(defaultTargetPlatform==TargetPlatform.android){
      return AndroidSettings(
        accuracy:LocationAccuracy.high,
        distanceFilter:10,
        intervalDuration:Duration(seconds:12),
        foregroundNotificationConfig:ForegroundNotificationConfig(
          notificationTitle:'GroopX live location',
          notificationText:'Your live location is being shared',
          enableWakeLock:true,
          setOngoing:true,
        ),
      );
    }
    return const LocationSettings(accuracy:LocationAccuracy.high,distanceFilter:10);
  }

  Future<void> _ensureTracking()async{
    if(_sessions.isEmpty||_positionSubscription!=null)return;
    _trackingRetryTimer?.cancel();
    _trackingRetryTimer=null;
    await _ensureLocationPermission();
    _positionSubscription=Geolocator.getPositionStream(locationSettings:_streamSettings).listen(_queuePosition,onError:(Object error)=>_trackingStreamEnded(error),onDone:()=>_trackingStreamEnded(),cancelOnError:true);
  }

  void _trackingStreamEnded([Object? _]){
    final subscription=_positionSubscription;
    _positionSubscription=null;
    if(subscription!=null)unawaited(subscription.cancel());
    _scheduleTrackingRetry();
  }

  void _scheduleTrackingRetry(){
    if(_sessions.isEmpty||_trackingRetryTimer?.isActive==true)return;
    _trackingRetryTimer=Timer(const Duration(seconds:15),()async{
      _trackingRetryTimer=null;
      try{await _ensureTracking();}catch(_){_scheduleTrackingRetry();}
    });
  }

  void _scheduleInitializationRetry(){
    if(_initialized||_initializationRetryTimer?.isActive==true)return;
    _initializationRetryTimer=Timer(const Duration(seconds:15),(){
      _initializationRetryTimer=null;
      unawaited(initialize());
    });
  }

  void _queuePosition(Position position){
    if(_sessions.isEmpty)return;
    _pendingPosition=position;
    if(!_syncing)unawaited(_flushPositions());
  }

  Future<void> _flushPositions()async{
    _syncing=true;
    try{
      while(_pendingPosition!=null&&_sessions.isNotEmpty){
        final position=_pendingPosition!;
        _pendingPosition=null;
        final generation=_generation;
        try{
          final trackingKey=await _deviceTrackingKey();
          final active=await ChatApi.instance.updateActiveLiveLocations(latitude:position.latitude,longitude:position.longitude,accuracyMeters:position.accuracy,trackingKey:trackingKey);
          if(generation!=_generation)return;
          _replaceSessions(active);
        }catch(failure){
          if(failure is DioException&&(failure.response?.statusCode==401||failure.response?.statusCode==403)){
            _sessions.clear();
            _armExpiryTimer();
            await _stopTrackingWhenIdle();
            notifyListeners();
          }
        }
      }
    }finally{_syncing=false;}
  }

  void _replaceSessions(List<LiveLocationSession> values){
    _sessions
      ..clear()
      ..addEntries(values.where((item)=>item.active).map((item)=>MapEntry(item.id,item)));
    _armExpiryTimer();
    if(_sessions.isEmpty)unawaited(_stopTrackingWhenIdle());
    notifyListeners();
  }

  void _armExpiryTimer(){
    _expiryTimer?.cancel();
    if(_sessions.isEmpty)return;
    final next=_sessions.values.map((item)=>item.expiresAt).reduce((first,second)=>first.isBefore(second)?first:second);
    final delay=next.difference(DateTime.now());
    _expiryTimer=Timer(delay.isNegative?Duration.zero:delay,(){
      _sessions.removeWhere((_,item)=>!item.active);
      unawaited(_stopTrackingWhenIdle());
      _armExpiryTimer();
      notifyListeners();
    });
  }

  Future<void> _stopTrackingWhenIdle()async{
    if(_sessions.isNotEmpty)return;
    _pendingPosition=null;
    _trackingRetryTimer?.cancel();
    _trackingRetryTimer=null;
    await _positionSubscription?.cancel();
    _positionSubscription=null;
  }

  Future<String> _deviceTrackingKey()async{
    if(_trackingKey!=null)return _trackingKey!;
    final preferences=await SharedPreferences.getInstance();
    final saved=preferences.getString('live_location_device_key');
    if(saved!=null&&RegExp(r'^[A-Za-z0-9_-]{16,128}$').hasMatch(saved)){_trackingKey=saved;return saved;}
    final random=Random.secure();
    final value=List<int>.generate(24,(_)=>random.nextInt(256)).map((item)=>item.toRadixString(16).padLeft(2,'0')).join();
    await preferences.setString('live_location_device_key',value);
    _trackingKey=value;
    return value;
  }
}
