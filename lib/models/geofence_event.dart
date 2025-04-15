import 'package:cloud_firestore/cloud_firestore.dart';

class GeofenceEvent {
  final String id;
  final String userId;
  final String userName;
  final String geofenceId;
  final String geofenceName;
  final DateTime timestamp;
  final String eventType; // 'entry' or 'exit'
  final GeoPoint location;
  final String sessionId; // To link entry and exit events
  final bool isProcessed;
  
  // Optional: Exit-specific fields
  final DateTime? entryTime;
  final Duration? duration; // Time spent inside the geofence
  
  GeofenceEvent({
    required this.id,
    required this.userId,
    required this.userName,
    required this.geofenceId,
    required this.geofenceName,
    required this.timestamp,
    required this.eventType,
    required this.location,
    required this.sessionId,
    this.isProcessed = false,
    this.entryTime,
    this.duration,
  });
  
  // Factory constructor to create from Firestore document
  factory GeofenceEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return GeofenceEvent(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      geofenceId: data['geofenceId'] ?? '',
      geofenceName: data['geofenceName'] ?? '',
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      eventType: data['eventType'] ?? '',
      location: data['location'] as GeoPoint,
      sessionId: data['sessionId'] ?? '',
      isProcessed: data['isProcessed'] ?? false,
      entryTime: data['entryTime'] != null 
          ? (data['entryTime'] as Timestamp).toDate() 
          : null,
      duration: data['durationSeconds'] != null 
          ? Duration(seconds: data['durationSeconds']) 
          : null,
    );
  }
  
  // Convert to map for Firestore
  Map<String, dynamic> toMap() {
    final map = {
      'userId': userId,
      'userName': userName,
      'geofenceId': geofenceId,
      'geofenceName': geofenceName,
      'timestamp': Timestamp.fromDate(timestamp),
      'eventType': eventType,
      'location': location,
      'sessionId': sessionId,
      'isProcessed': isProcessed,
    };
    
    // Add optional fields if they exist
    if (entryTime != null) {
      map['entryTime'] = Timestamp.fromDate(entryTime!);
    }
    
    if (duration != null) {
      map['durationSeconds'] = duration!.inSeconds;
    }
    
    return map;
  }
  
  // Create a copy with some fields changed
  GeofenceEvent copyWith({
    String? id,
    String? userId,
    String? userName,
    String? geofenceId,
    String? geofenceName,
    DateTime? timestamp,
    String? eventType,
    GeoPoint? location,
    String? sessionId,
    bool? isProcessed,
    DateTime? entryTime,
    Duration? duration,
  }) {
    return GeofenceEvent(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      geofenceId: geofenceId ?? this.geofenceId,
      geofenceName: geofenceName ?? this.geofenceName,
      timestamp: timestamp ?? this.timestamp,
      eventType: eventType ?? this.eventType,
      location: location ?? this.location,
      sessionId: sessionId ?? this.sessionId,
      isProcessed: isProcessed ?? this.isProcessed,
      entryTime: entryTime ?? this.entryTime,
      duration: duration ?? this.duration,
    );
  }
}

// Class to represent a complete geofence session (entry and exit)
class GeofenceSession {
  final String id; // Same as sessionId in GeofenceEvent
  final String userId;
  final String userName;
  final String geofenceId;
  final String geofenceName;
  final DateTime entryTime;
  final DateTime? exitTime;
  final Duration? duration;
  final bool isActive; // true if user is still inside (no exit event)
  
  GeofenceSession({
    required this.id,
    required this.userId,
    required this.userName,
    required this.geofenceId,
    required this.geofenceName,
    required this.entryTime,
    this.exitTime,
    this.duration,
    required this.isActive,
  });
  
  // Factory constructor to create from Firestore document
  factory GeofenceSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    return GeofenceSession(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? '',
      geofenceId: data['geofenceId'] ?? '',
      geofenceName: data['geofenceName'] ?? '',
      entryTime: (data['entryTime'] as Timestamp).toDate(),
      exitTime: data['exitTime'] != null 
          ? (data['exitTime'] as Timestamp).toDate() 
          : null,
      duration: data['durationSeconds'] != null 
          ? Duration(seconds: data['durationSeconds']) 
          : null,
      isActive: data['isActive'] ?? true,
    );
  }
  
  // Convert to map for Firestore
  Map<String, dynamic> toMap() {
    final map = {
      'userId': userId,
      'userName': userName,
      'geofenceId': geofenceId,
      'geofenceName': geofenceName,
      'entryTime': Timestamp.fromDate(entryTime),
      'isActive': isActive,
    };
    
    // Add optional fields if they exist
    if (exitTime != null) {
      map['exitTime'] = Timestamp.fromDate(exitTime!);
    }
    
    if (duration != null) {
      map['durationSeconds'] = duration!.inSeconds;
    }
    
    return map;
  }
  
  // Create a session from entry event
  factory GeofenceSession.fromEntryEvent(GeofenceEvent entryEvent) {
    return GeofenceSession(
      id: entryEvent.sessionId,
      userId: entryEvent.userId,
      userName: entryEvent.userName,
      geofenceId: entryEvent.geofenceId,
      geofenceName: entryEvent.geofenceName,
      entryTime: entryEvent.timestamp,
      isActive: true,
    );
  }
  
  // Create a completed session from entry and exit events
  factory GeofenceSession.fromEvents(GeofenceEvent entryEvent, GeofenceEvent exitEvent) {
    final duration = exitEvent.timestamp.difference(entryEvent.timestamp);
    
    return GeofenceSession(
      id: entryEvent.sessionId,
      userId: entryEvent.userId,
      userName: entryEvent.userName,
      geofenceId: entryEvent.geofenceId,
      geofenceName: entryEvent.geofenceName,
      entryTime: entryEvent.timestamp,
      exitTime: exitEvent.timestamp,
      duration: duration,
      isActive: false,
    );
  }
  
  // Close a session with an exit event
  GeofenceSession closeWithExit(DateTime exitTime) {
    final duration = exitTime.difference(entryTime);
    
    return GeofenceSession(
      id: id,
      userId: userId,
      userName: userName,
      geofenceId: geofenceId,
      geofenceName: geofenceName,
      entryTime: entryTime,
      exitTime: exitTime,
      duration: duration,
      isActive: false,
    );
  }
  
  // Create a copy with some fields changed
  GeofenceSession copyWith({
    String? id,
    String? userId,
    String? userName,
    String? geofenceId,
    String? geofenceName,
    DateTime? entryTime,
    DateTime? exitTime,
    Duration? duration,
    bool? isActive,
  }) {
    return GeofenceSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      geofenceId: geofenceId ?? this.geofenceId,
      geofenceName: geofenceName ?? this.geofenceName,
      entryTime: entryTime ?? this.entryTime,
      exitTime: exitTime ?? this.exitTime,
      duration: duration ?? this.duration,
      isActive: isActive ?? this.isActive,
    );
  }
} 