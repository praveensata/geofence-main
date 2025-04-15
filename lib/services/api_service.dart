import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

class ApiService {
  final logger = Logger();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Check if user has already marked attendance today
  Future<Map<String, dynamic>?> getTodayAttendance(String userId) async {
    try {
      // Get today's start and end time
      final DateTime now = DateTime.now();
      final DateTime todayStart = DateTime(now.year, now.month, now.day, 0, 0, 0);
      final DateTime todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59);
      
      // Query Firestore for today's attendance
      final QuerySnapshot attendanceQuery = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(todayEnd))
          .where('isEntering', isEqualTo: true)
          .limit(1)
          .get();
      
      if (attendanceQuery.docs.isNotEmpty) {
        final doc = attendanceQuery.docs.first;
        return {
          'id': doc.id,
          'data': doc.data() as Map<String, dynamic>,
        };
      }
      return null;
    } catch (e) {
      logger.e('Error checking today\'s attendance: $e');
      return null;
    }
  }

  // Log attendance entry (only if not already entered today)
  Future<bool> logAttendance(String userId, DateTime timestamp, bool isEntering) async {
    try {
      // If this is an entry record, check if user already has an entry today
      if (isEntering) {
        final existingAttendance = await getTodayAttendance(userId);
        if (existingAttendance != null) {
          logger.i('User already has attendance entry for today. Skipping duplicate entry.');
          return false;
        }
      }
      
      // Add the attendance record
      await _firestore.collection('attendance').add({
        'userId': userId,
        'timestamp': Timestamp.fromDate(timestamp),
        'isEntering': isEntering,
        'recordedAt': FieldValue.serverTimestamp(),
      });
      
      logger.i('Attendance ${isEntering ? "entry" : "exit"} logged successfully');
      return true;
    } catch (e) {
      logger.e('Error logging attendance: $e');
      return false;
    }
  }
  
  // Record exit event (update the day's attendance record)
  Future<bool> recordExit(String userId, DateTime exitTime) async {
    try {
      // Find today's entry record
      final existingAttendance = await getTodayAttendance(userId);
      
      if (existingAttendance == null) {
        logger.w('No entry record found for today. Cannot record exit.');
        return false;
      }
      
      // Get the entry timestamp
      final data = existingAttendance['data'] as Map<String, dynamic>;
      final entryTimestamp = data['timestamp'] as Timestamp;
      final entryTime = entryTimestamp.toDate();
      
      // Calculate duration (in hours and minutes)
      final duration = exitTime.difference(entryTime);
      
      // Create an exit record
      await _firestore.collection('attendance').add({
        'userId': userId,
        'timestamp': Timestamp.fromDate(exitTime),
        'isEntering': false,
        'entryRecordId': existingAttendance['id'],
        'entryTime': Timestamp.fromDate(entryTime),
        'durationMinutes': duration.inMinutes,
        'recordedAt': FieldValue.serverTimestamp(),
      });
      
      // Also update the daily attendance summary
      await _updateDailySummary(userId, entryTime, exitTime, duration);
      
      logger.i('Exit recorded successfully. Duration: ${duration.inHours}h ${duration.inMinutes % 60}m');
      return true;
    } catch (e) {
      logger.e('Error recording exit: $e');
      return false;
    }
  }
  
  // Update daily attendance summary
  Future<bool> _updateDailySummary(String userId, DateTime entryTime, DateTime exitTime, Duration duration) async {
    try {
      // Get user name for better display
      final userDoc = await _firestore.collection('users').doc(userId).get();
      String userName = 'Unknown User';
      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        userName = userData['name'] as String? ?? 'Unknown User';
      }
      
      // Create date string for document ID (YYYY-MM-DD)
      final date = DateTime(entryTime.year, entryTime.month, entryTime.day);
      final dateStr = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      final docId = '${userId}_$dateStr';
      
      // Get or create daily summary document
      final docRef = _firestore.collection('attendance_summary').doc(docId);
      final doc = await docRef.get();
      
      if (doc.exists) {
        // Update existing summary
        await docRef.update({
          'exitTime': Timestamp.fromDate(exitTime),
          'durationMinutes': duration.inMinutes,
          'isComplete': true,
          'formattedDuration': _formatDuration(duration),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new summary
        await docRef.set({
          'userId': userId,
          'userName': userName,
          'date': Timestamp.fromDate(date),
          'entryTime': Timestamp.fromDate(entryTime),
          'exitTime': Timestamp.fromDate(exitTime),
          'durationMinutes': duration.inMinutes,
          'formattedDuration': _formatDuration(duration),
          'isComplete': true,
          'created': FieldValue.serverTimestamp(),
          'lastUpdated': FieldValue.serverTimestamp(),
        });
      }
      
      return true;
    } catch (e) {
      logger.e('Error updating daily summary: $e');
      return false;
    }
  }
  
  // Format duration in a readable way
  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    if (hours > 0) {
      return '$hours hour${hours != 1 ? 's' : ''} $minutes minute${minutes != 1 ? 's' : ''}';
    } else {
      return '$minutes minute${minutes != 1 ? 's' : ''}';
    }
  }
  
  // Get attendance summary for a specific date range
  Future<List<Map<String, dynamic>>> getAttendanceSummary(String userId, DateTime startDate, DateTime endDate) async {
    try {
      final startDateOnly = DateTime(startDate.year, startDate.month, startDate.day);
      final endDateOnly = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      
      final QuerySnapshot summaryQuery = await _firestore
          .collection('attendance_summary')
          .where('userId', isEqualTo: userId)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startDateOnly))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endDateOnly))
          .orderBy('date', descending: true)
          .get();
      
      return summaryQuery.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'id': doc.id,
          'date': (data['date'] as Timestamp).toDate(),
          'entryTime': (data['entryTime'] as Timestamp).toDate(),
          'exitTime': data['exitTime'] != null ? (data['exitTime'] as Timestamp).toDate() : null,
          'durationMinutes': data['durationMinutes'] ?? 0,
          'formattedDuration': data['formattedDuration'] ?? 'N/A',
          'isComplete': data['isComplete'] ?? false,
        };
      }).toList();
    } catch (e) {
      logger.e('Error getting attendance summary: $e');
      return [];
    }
  }
  
  // Get today's attendance summary
  Future<Map<String, dynamic>?> getTodayAttendanceSummary(String userId) async {
    try {
      final DateTime now = DateTime.now();
      final DateTime today = DateTime(now.year, now.month, now.day);
      final dateStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final docId = '${userId}_$dateStr';
      
      final docRef = await _firestore.collection('attendance_summary').doc(docId).get();
      
      if (docRef.exists) {
        final data = docRef.data() as Map<String, dynamic>;
        return {
          'id': docRef.id,
          'date': (data['date'] as Timestamp).toDate(),
          'entryTime': (data['entryTime'] as Timestamp).toDate(),
          'exitTime': data['exitTime'] != null ? (data['exitTime'] as Timestamp).toDate() : null,
          'durationMinutes': data['durationMinutes'] ?? 0,
          'formattedDuration': data['formattedDuration'] ?? 'N/A',
          'isComplete': data['isComplete'] ?? false,
        };
      }
      
      return null;
    } catch (e) {
      logger.e('Error getting today\'s attendance summary: $e');
      return null;
    }
  }
}
