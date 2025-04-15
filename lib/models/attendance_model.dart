import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceSession {
  final String id;
  final String userId;
  final String userName;
  final String userEmail;
  final DateTime entryTime;
  final DateTime? exitTime;
  final Duration duration;
  final String deviceInfo;
  final bool isActive;
  final GeoPoint entryLocation;
  final GeoPoint? exitLocation;
  final String entryLocationName;
  final String? exitLocationName;
  final Map<String, dynamic>? additionalData;

  AttendanceSession({
    required this.id,
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.entryTime,
    this.exitTime,
    required this.duration,
    required this.deviceInfo,
    required this.isActive,
    required this.entryLocation,
    this.exitLocation,
    required this.entryLocationName,
    this.exitLocationName,
    this.additionalData,
  });

  factory AttendanceSession.fromMap(Map<String, dynamic> map, String docId) {
    return AttendanceSession(
      id: docId,
      userId: map['userId'] as String,
      userName: map['userName'] as String,
      userEmail: map['userEmail'] as String,
      entryTime: (map['entryTime'] as Timestamp).toDate(),
      exitTime: map['exitTime'] != null
          ? (map['exitTime'] as Timestamp).toDate()
          : null,
      duration: Duration(milliseconds: map['durationMs'] as int? ?? 0),
      deviceInfo: map['deviceInfo'] as String? ?? 'Unknown device',
      isActive: map['isActive'] as bool? ?? false,
      entryLocation: map['entryLocation'] as GeoPoint,
      exitLocation: map['exitLocation'] as GeoPoint?,
      entryLocationName: map['entryLocationName'] as String? ?? 'Unknown location',
      exitLocationName: map['exitLocationName'] as String?,
      additionalData: map['additionalData'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'userEmail': userEmail,
      'entryTime': Timestamp.fromDate(entryTime),
      'exitTime': exitTime != null ? Timestamp.fromDate(exitTime!) : null,
      'durationMs': duration.inMilliseconds,
      'deviceInfo': deviceInfo,
      'isActive': isActive,
      'entryLocation': entryLocation,
      'exitLocation': exitLocation,
      'entryLocationName': entryLocationName,
      'exitLocationName': exitLocationName,
      'additionalData': additionalData,
    };
  }

  AttendanceSession copyWith({
    String? id,
    String? userId,
    String? userName,
    String? userEmail,
    DateTime? entryTime,
    DateTime? exitTime,
    Duration? duration,
    String? deviceInfo,
    bool? isActive,
    GeoPoint? entryLocation,
    GeoPoint? exitLocation,
    String? entryLocationName,
    String? exitLocationName,
    Map<String, dynamic>? additionalData,
  }) {
    return AttendanceSession(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      userEmail: userEmail ?? this.userEmail,
      entryTime: entryTime ?? this.entryTime,
      exitTime: exitTime ?? this.exitTime,
      duration: duration ?? this.duration,
      deviceInfo: deviceInfo ?? this.deviceInfo,
      isActive: isActive ?? this.isActive,
      entryLocation: entryLocation ?? this.entryLocation,
      exitLocation: exitLocation ?? this.exitLocation,
      entryLocationName: entryLocationName ?? this.entryLocationName,
      exitLocationName: exitLocationName ?? this.exitLocationName,
      additionalData: additionalData ?? this.additionalData,
    );
  }
}

class DailyAttendanceSummary {
  final String id;
  final String userId;
  final String userName;
  final DateTime date;
  final Duration totalDuration;
  final int sessionCount;
  final DateTime firstEntryTime;
  final DateTime? lastExitTime;
  final List<String> sessionIds;

  DailyAttendanceSummary({
    required this.id,
    required this.userId,
    required this.userName,
    required this.date,
    required this.totalDuration,
    required this.sessionCount,
    required this.firstEntryTime,
    this.lastExitTime,
    required this.sessionIds,
  });

  factory DailyAttendanceSummary.fromMap(Map<String, dynamic> map, String docId) {
    return DailyAttendanceSummary(
      id: docId,
      userId: map['userId'] as String,
      userName: map['userName'] as String,
      date: (map['date'] as Timestamp).toDate(),
      totalDuration: Duration(milliseconds: map['totalDurationMs'] as int),
      sessionCount: map['sessionCount'] as int,
      firstEntryTime: (map['firstEntryTime'] as Timestamp).toDate(),
      lastExitTime: map['lastExitTime'] != null
          ? (map['lastExitTime'] as Timestamp).toDate()
          : null,
      sessionIds: List<String>.from(map['sessionIds'] as List<dynamic>),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'date': Timestamp.fromDate(DateTime(date.year, date.month, date.day)),
      'totalDurationMs': totalDuration.inMilliseconds,
      'sessionCount': sessionCount,
      'firstEntryTime': Timestamp.fromDate(firstEntryTime),
      'lastExitTime': lastExitTime != null ? Timestamp.fromDate(lastExitTime!) : null,
      'sessionIds': sessionIds,
    };
  }

  DailyAttendanceSummary copyWith({
    String? id,
    String? userId,
    String? userName,
    DateTime? date,
    Duration? totalDuration,
    int? sessionCount,
    DateTime? firstEntryTime,
    DateTime? lastExitTime,
    List<String>? sessionIds,
  }) {
    return DailyAttendanceSummary(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      date: date ?? this.date,
      totalDuration: totalDuration ?? this.totalDuration,
      sessionCount: sessionCount ?? this.sessionCount,
      firstEntryTime: firstEntryTime ?? this.firstEntryTime,
      lastExitTime: lastExitTime ?? this.lastExitTime,
      sessionIds: sessionIds ?? this.sessionIds,
    );
  }
}

class MonthlyAttendanceSummary {
  final String id;
  final String userId;
  final String userName;
  final int year;
  final int month;
  final Duration totalDuration;
  final int totalDays;
  final Map<String, int> durationByDay;

  MonthlyAttendanceSummary({
    required this.id,
    required this.userId,
    required this.userName,
    required this.year,
    required this.month,
    required this.totalDuration,
    required this.totalDays,
    required this.durationByDay,
  });

  factory MonthlyAttendanceSummary.fromMap(Map<String, dynamic> map, String docId) {
    return MonthlyAttendanceSummary(
      id: docId,
      userId: map['userId'] as String,
      userName: map['userName'] as String,
      year: map['year'] as int,
      month: map['month'] as int,
      totalDuration: Duration(milliseconds: map['totalDurationMs'] as int),
      totalDays: map['totalDays'] as int,
      durationByDay: Map<String, int>.from(map['durationByDay'] as Map),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'year': year,
      'month': month,
      'totalDurationMs': totalDuration.inMilliseconds,
      'totalDays': totalDays,
      'durationByDay': durationByDay,
    };
  }
}

class GeofenceEvent {
  final String id;
  final String userId;
  final String userName;
  final DateTime timestamp;
  final String eventType; // 'ENTER' or 'EXIT'
  final GeoPoint location;
  final String locationName;
  final String deviceInfo;
  final Map<String, dynamic>? additionalData;

  GeofenceEvent({
    required this.id,
    required this.userId,
    required this.userName,
    required this.timestamp,
    required this.eventType,
    required this.location,
    required this.locationName,
    required this.deviceInfo,
    this.additionalData,
  });

  factory GeofenceEvent.fromMap(Map<String, dynamic> map, String docId) {
    return GeofenceEvent(
      id: docId,
      userId: map['userId'] as String,
      userName: map['userName'] as String,
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      eventType: map['eventType'] as String,
      location: map['location'] as GeoPoint,
      locationName: map['locationName'] as String,
      deviceInfo: map['deviceInfo'] as String,
      additionalData: map['additionalData'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'timestamp': Timestamp.fromDate(timestamp),
      'eventType': eventType,
      'location': location,
      'locationName': locationName,
      'deviceInfo': deviceInfo,
      'additionalData': additionalData,
    };
  }
}

// Helper methods for attendance data management
class AttendanceHelper {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Create a new attendance session
  static Future<String> createAttendanceSession(AttendanceSession session) async {
    try {
      final docRef = await _firestore.collection('attendance_sessions').add(session.toMap());
      return docRef.id;
    } catch (e) {
      print('Error creating attendance session: $e');
      return '';
    }
  }

  // Update an existing attendance session
  static Future<bool> updateAttendanceSession(AttendanceSession session) async {
    try {
      await _firestore.collection('attendance_sessions').doc(session.id).update(session.toMap());
      return true;
    } catch (e) {
      print('Error updating attendance session: $e');
      return false;
    }
  }

  // Get all active sessions for a user
  static Future<List<AttendanceSession>> getActiveSessionsForUser(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('attendance_sessions')
          .where('userId', isEqualTo: userId)
          .where('isActive', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => AttendanceSession.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('Error getting active sessions: $e');
      return [];
    }
  }

  // Record a geofence event
  static Future<String> recordGeofenceEvent(GeofenceEvent event) async {
    try {
      final docRef = await _firestore.collection('geofence_events').add(event.toMap());
      return docRef.id;
    } catch (e) {
      print('Error recording geofence event: $e');
      return '';
    }
  }

  // Update or create daily attendance summary
  static Future<bool> updateDailySummary(AttendanceSession session) async {
    try {
      // Get date string for the session date (YYYY-MM-DD)
      final date = DateTime(
        session.entryTime.year,
        session.entryTime.month,
        session.entryTime.day,
      );
      
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final docId = '${session.userId}_$dateStr';
      
      // Check if summary exists
      final docRef = _firestore.collection('daily_attendance').doc(docId);
      final doc = await docRef.get();
      
      if (doc.exists) {
        // Update existing summary
        final summary = DailyAttendanceSummary.fromMap(doc.data()!, doc.id);
        
        final updatedSummary = summary.copyWith(
          totalDuration: Duration(milliseconds: summary.totalDuration.inMilliseconds + session.duration.inMilliseconds),
          sessionCount: summary.sessionCount + 1,
          lastExitTime: session.exitTime ?? summary.lastExitTime,
          sessionIds: [...summary.sessionIds, session.id],
        );
        
        await docRef.update(updatedSummary.toMap());
      } else {
        // Create new summary
        final newSummary = DailyAttendanceSummary(
          id: docId,
          userId: session.userId,
          userName: session.userName,
          date: date,
          totalDuration: session.duration,
          sessionCount: 1,
          firstEntryTime: session.entryTime,
          lastExitTime: session.exitTime,
          sessionIds: [session.id],
        );
        
        await docRef.set(newSummary.toMap());
      }
      
      return true;
    } catch (e) {
      print('Error updating daily summary: $e');
      return false;
    }
  }
  
  // Get a user's attendance summary for a specific month
  static Future<MonthlyAttendanceSummary?> getMonthlyAttendance(
    String userId,
    int year,
    int month,
  ) async {
    try {
      final docId = '${userId}_${year}_${month.toString().padLeft(2, '0')}';
      final doc = await _firestore.collection('monthly_attendance').doc(docId).get();
      
      if (doc.exists) {
        return MonthlyAttendanceSummary.fromMap(doc.data()!, doc.id);
      }
      
      // If monthly summary doesn't exist, generate it from daily summaries
      final startDate = DateTime(year, month, 1);
      final endDate = DateTime(year, month + 1, 0); // Last day of month
      
      final dailySummaries = await _firestore
          .collection('daily_attendance')
          .where('userId', isEqualTo: userId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();
      
      if (dailySummaries.docs.isEmpty) {
        return null;
      }
      
      int totalDurationMs = 0;
      final durationByDay = <String, int>{};
      
      for (final doc in dailySummaries.docs) {
        final summary = DailyAttendanceSummary.fromMap(doc.data(), doc.id);
        final dayStr = summary.date.day.toString();
        
        totalDurationMs += summary.totalDuration.inMilliseconds;
        durationByDay[dayStr] = summary.totalDuration.inMilliseconds;
      }
      
      final monthlySummary = MonthlyAttendanceSummary(
        id: docId,
        userId: userId,
        userName: dailySummaries.docs.first.data()['userName'] as String,
        year: year,
        month: month,
        totalDuration: Duration(milliseconds: totalDurationMs),
        totalDays: dailySummaries.docs.length,
        durationByDay: durationByDay,
      );
      
      // Store the summary for future use
      await _firestore.collection('monthly_attendance').doc(docId).set(monthlySummary.toMap());
      
      return monthlySummary;
    } catch (e) {
      print('Error getting monthly attendance: $e');
      return null;
    }
  }
  
  // Format duration for display (e.g., "2h 30m")
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${minutes}m';
    }
  }
} 