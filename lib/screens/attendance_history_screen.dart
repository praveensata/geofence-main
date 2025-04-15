import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';
import '../services/api_service.dart';
import '../models/geofence_event.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  final String? userId;

  const AttendanceHistoryScreen({
    Key? key,
    required this.userId,
  }) : super(key: key);

  @override
  _AttendanceHistoryScreenState createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> with SingleTickerProviderStateMixin {
  final Logger logger = Logger();
  final ApiService _apiService = ApiService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  List<Map<String, dynamic>> _attendanceRecords = [];
  List<GeofenceSession> _geofenceSessions = [];
  bool _isLoading = true;
  DateTime _startDate = DateTime.now().subtract(Duration(days: 30));
  DateTime _endDate = DateTime.now();
  
  late TabController _tabController;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }
  
  Future<void> _loadData() async {
    await Future.wait([
      _loadAttendanceHistory(),
      _loadGeofenceSessions(),
    ]);
  }
  
  Future<void> _loadAttendanceHistory() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Get attendance summary from the API service
      final records = await _apiService.getAttendanceSummary(
        widget.userId ?? FirebaseAuth.instance.currentUser!.uid,
        _startDate,
        _endDate,
      );
      
      setState(() {
        _attendanceRecords = records;
        _isLoading = false;
      });
    } catch (e) {
      logger.e('Error loading attendance history: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading attendance history')),
      );
    }
  }
  
  Future<void> _loadGeofenceSessions() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Convert dates to Timestamps for Firestore
      final startTimestamp = Timestamp.fromDate(_startDate);
      final endTimestamp = Timestamp.fromDate(_endDate.add(Duration(days: 1)));
      
      // Get sessions for this user within the date range
      final querySnapshot = await _firestore
          .collection('geofence_sessions')
          .where('userId', isEqualTo: widget.userId ?? FirebaseAuth.instance.currentUser!.uid)
          .where('entryTime', isGreaterThanOrEqualTo: startTimestamp)
          .where('entryTime', isLessThanOrEqualTo: endTimestamp)
          .orderBy('entryTime', descending: true)
          .get();
      
      final sessions = querySnapshot.docs
          .map((doc) => GeofenceSession.fromFirestore(doc))
          .toList();
      
      setState(() {
        _geofenceSessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      logger.e('Error loading geofence sessions: $e');
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading geofence sessions')),
      );
    }
  }
  
  Future<void> _selectDateRange() async {
    final initialDateRange = DateTimeRange(
      start: _startDate,
      end: _endDate,
    );
    
    final newDateRange = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: initialDateRange,
    );
    
    if (newDateRange != null) {
      setState(() {
        _startDate = newDateRange.start;
        _endDate = newDateRange.end;
      });
      _loadData();
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance History'),
        actions: [
          IconButton(
            icon: Icon(Icons.date_range),
            onPressed: _selectDateRange,
            tooltip: 'Select Date Range',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Attendance', icon: Icon(Icons.event_available)),
            Tab(text: 'Geofence Sessions', icon: Icon(Icons.location_history)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Date range indicator
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Date Range:',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${DateFormat('MMM d, y').format(_startDate)} - ${DateFormat('MMM d, y').format(_endDate)}',
                        ),
                      ],
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.refresh),
                  onPressed: _loadData,
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAttendanceTab(),
                _buildGeofenceSessionsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAttendanceTab() {
    return _isLoading
        ? Center(child: CircularProgressIndicator())
        : _attendanceRecords.isEmpty
            ? _buildEmptyState('No attendance records found')
            : ListView.builder(
                itemCount: _attendanceRecords.length,
                itemBuilder: (context, index) {
                  final record = _attendanceRecords[index];
                  final date = record['date'] as DateTime;
                  final entryTime = record['entryTime'] as DateTime;
                  final exitTime = record['exitTime'] as DateTime?;
                  final durationMinutes = record['durationMinutes'] as int;
                  final formattedDuration = record['formattedDuration'] as String;
                  final isComplete = record['isComplete'] as bool;
                  
                  // Determine status color
                  Color statusColor;
                  if (isComplete) {
                    // More than 8 hours is green, less is orange
                    statusColor = durationMinutes >= 480 
                        ? Colors.green 
                        : Colors.orange;
                  } else {
                    // Incomplete session
                    statusColor = Colors.red;
                  }
                  
                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                DateFormat('EEEE, MMM d').format(date),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8, 
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  isComplete ? 'Complete' : 'Incomplete',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTimeInfo(
                                  'Entry',
                                  DateFormat('h:mm a').format(entryTime),
                                  Icons.login,
                                  Colors.green,
                                ),
                              ),
                              Expanded(
                                child: _buildTimeInfo(
                                  'Exit',
                                  exitTime != null
                                      ? DateFormat('h:mm a').format(exitTime)
                                      : 'Not recorded',
                                  Icons.logout,
                                  exitTime != null
                                      ? Colors.red
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timelapse,
                                color: Colors.blue,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Duration: $formattedDuration',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
  }
  
  Widget _buildGeofenceSessionsTab() {
    return _isLoading
        ? Center(child: CircularProgressIndicator())
        : _geofenceSessions.isEmpty
            ? _buildEmptyState('No geofence sessions found')
            : ListView.builder(
                itemCount: _geofenceSessions.length,
                itemBuilder: (context, index) {
                  final session = _geofenceSessions[index];
                  
                  // Format entry and exit times
                  final entryDate = DateFormat('MMM d, yyyy').format(session.entryTime);
                  final entryTime = DateFormat('h:mm a').format(session.entryTime);
                  final exitTime = session.exitTime != null
                      ? DateFormat('h:mm a').format(session.exitTime!)
                      : 'Still active';
                  
                  // Format duration
                  String durationText = 'Still active';
                  if (session.duration != null) {
                    final hours = session.duration!.inHours;
                    final minutes = (session.duration!.inMinutes % 60);
                    durationText = hours > 0
                        ? '$hours hr ${minutes > 0 ? '$minutes min' : ''}'
                        : '${session.duration!.inMinutes} min';
                  }
                  
                  // Determine status color
                  final Color statusColor = session.isActive ? Colors.blue : Colors.green;
                  
                  return Card(
                    margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                session.geofenceName,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 8, 
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  session.isActive ? 'Active' : 'Completed',
                                  style: TextStyle(
                                    color: statusColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 4),
                          Text(
                            entryDate,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                          Divider(),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTimeInfo(
                                  'Entry',
                                  entryTime,
                                  Icons.login,
                                  Colors.green,
                                ),
                              ),
                              Expanded(
                                child: _buildTimeInfo(
                                  'Exit',
                                  exitTime,
                                  Icons.logout,
                                  session.isActive ? Colors.grey : Colors.red,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.timelapse,
                                color: Colors.blue,
                                size: 20,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'Duration: $durationText',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue.shade700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
  }
  
  Widget _buildTimeInfo(String label, String time, IconData icon, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: 12,
          ),
        ),
        SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: color,
              size: 16,
            ),
            SizedBox(width: 4),
            Text(
              time,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.event_busy,
            size: 64,
            color: Colors.grey.shade400,
          ),
          SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          SizedBox(height: 8),
          Text(
            'Try selecting a different date range',
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
} 