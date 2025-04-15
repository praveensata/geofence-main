import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart'; // Import geolocator package
import '../services/api_service.dart';
import '../services/geofence_service.dart';
import 'package:intl/intl.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  AttendanceScreenState createState() => AttendanceScreenState();
}

class AttendanceScreenState extends State<AttendanceScreen> {
  final logger = Logger();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;
  final ApiService _apiService = ApiService();
  
  bool _isPresent = false;
  bool _isGeofencingStarted = false;
  bool _isLoading = false;
  bool _hasExitedGeofence = false;
  
  // Session tracking
  DateTime? _entryTime;
  Map<String, dynamic>? _todayAttendance;
  StreamSubscription<GeofenceEvent>? _geofenceStreamSubscription;

  // Google Maps
  GoogleMapController? _mapController;
  static const LatLng _geofenceCenter =
      LatLng(17.732089, 83.314537); // Example location
  static const double _geofenceRadius = 50; // Radius in meters
  final Set<Circle> _circles = {};
  final Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _checkGeofenceState();
    _setupMap();
    _getCurrentLocation();
    _checkTodaysAttendance();
    _setupGeofenceEventListener();
  }
  
  @override
  void dispose() {
    _geofenceStreamSubscription?.cancel();
    super.dispose();
  }
  
  // Setup listener for geofence events
  void _setupGeofenceEventListener() {
    _geofenceStreamSubscription = GeofenceService.instance.geofenceEventStream.listen((event) {
      if (event.userId == _user?.uid) {
        if (event.eventType == 'exit') {
          setState(() {
            _hasExitedGeofence = true;
            _isPresent = false;
          });
          logger.i('User exited geofence. Can mark attendance on next entry.');
          
          _showExitNotification(event.timestamp);
        } else if (event.eventType == 'entry' && _hasExitedGeofence) {
          setState(() {
            _hasExitedGeofence = false;
          });
          logger.i('User entered geofence after previous exit.');
        }
      }
    });
  }
  
  void _showExitNotification(DateTime exitTime) {
    if (_entryTime != null) {
      final duration = exitTime.difference(_entryTime!);
      final hours = duration.inHours;
      final minutes = (duration.inMinutes % 60);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('You have exited the geofence. Session duration: $hours hr ${minutes} min'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  // Check if the user has already marked attendance today
  Future<void> _checkTodaysAttendance() async {
    if (_user == null) return;
    
    try {
      final attendance = await _apiService.getTodayAttendance(_user!.uid);
      
      if (attendance != null) {
        final data = attendance['data'] as Map<String, dynamic>;
        final timestamp = data['timestamp'] as Timestamp;
        
        setState(() {
          _isPresent = true;
          _entryTime = timestamp.toDate();
          _todayAttendance = attendance;
        });
        
        logger.i('User already marked attendance today at ${DateFormat('hh:mm a').format(_entryTime!)}');
      } else {
        // Check shared preferences to see if user has exited the geofence since last attendance
        SharedPreferences prefs = await SharedPreferences.getInstance();
        bool hasExited = prefs.getBool('hasExitedGeofence_${_user!.uid}') ?? false;
        
        setState(() {
          _hasExitedGeofence = hasExited;
        });
      }
    } catch (e) {
      logger.e('Error checking today\'s attendance: $e');
    }
  }

  Future<void> _checkGeofenceState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool geofenceActive = prefs.getBool('isGeofenceActive') ?? false;
    setState(() {
      _isGeofencingStarted = geofenceActive;
    });
    logger.i('Geofence active: $_isGeofencingStarted');
  }

  void _setupMap() {
    setState(() {
      _circles.add(Circle(
        circleId: CircleId('geofence'),
        center: _geofenceCenter,
        radius: _geofenceRadius,
        fillColor: Colors.blue.withOpacity(0.3),
        strokeColor: Colors.blue,
        strokeWidth: 2,
      ));

      _markers.add(Marker(
        markerId: MarkerId('geofence_center'),
        position: _geofenceCenter,
        infoWindow: InfoWindow(title: 'Geofence Center'),
      ));
    });
  }

  Future<void> _getCurrentLocation() async {
    var status = await Permission.location.request();
    if (!mounted) return;

    if (status.isGranted) {
      Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      LatLng currentLatLng = LatLng(position.latitude, position.longitude);
      _mapController?.animateCamera(
        CameraUpdate.newLatLng(currentLatLng),
      );
      setState(() {
        _markers.add(Marker(
          markerId: MarkerId('current_location'),
          position: currentLatLng,
          infoWindow: InfoWindow(title: 'You are here'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        ));
      });
      logger.i('Current location: $currentLatLng');
    } else {
      logger.e('Location permissions are denied');
    }
  }

  void _startGeofencing() {
    GeofenceService.startGeofencing(_onEnterGeofence, _onExitGeofence);
    setState(() {
      _isGeofencingStarted = true;
    });
  }

  void _onEnterGeofence() {
    logger.i('Entered geofence');
    if (_user != null) {
      GeofenceService.logActivity(
          _user.uid, 'enter_geofence', 'User entered the geofence');
      
      // Reset the exited geofence flag when user enters
      _saveExitState(false);
    }
  }

  void _onExitGeofence() {
    logger.i('Exited geofence');
    if (_user != null) {
      GeofenceService.logActivity(
          _user.uid, 'exit_geofence', 'User exited the geofence');
      if (mounted) {
        setState(() {
          _isPresent = false;
          _isGeofencingStarted = false;
          _hasExitedGeofence = true;
        });
      }
      
      // Save exit state to preferences
      _saveExitState(true);
      
      GeofenceService.notifyUserOnExit();
    }
  }
  
  Future<void> _saveExitState(bool hasExited) async {
    if (_user == null) return;
    
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool('hasExitedGeofence_${_user!.uid}', hasExited);
      logger.i('Saved exit state: $hasExited');
    } catch (e) {
      logger.e('Error saving exit state: $e');
    }
  }

  Future<void> _submitAttendance() async {
    if (_user == null) return;
    
    // If already present and has not exited, show message
    if (_isPresent && !_hasExitedGeofence) {
      _showAlreadyMarkedDialog();
      return;
    }
    
    try {
      setState(() {
        _isLoading = true;
      });
      
      var status = await Permission.location.request();
      if (!mounted) return;

      if (status.isGranted) {
        bool isWithinGeofence = await GeofenceService.isWithinGeofence();
        if (!mounted) return;

        if (isWithinGeofence) {
          // Get current time for the attendance record
          final DateTime now = DateTime.now();
          
          // Check one more time if attendance has already been marked
          final existingAttendance = await _apiService.getTodayAttendance(_user!.uid);
          
          if (existingAttendance != null && !_hasExitedGeofence) {
            _showAlreadyMarkedDialog();
            setState(() {
              _isLoading = false;
              _isPresent = true;
            });
            return;
          }
          
          // Record attendance
          bool success = await _apiService.logAttendance(_user!.uid, now, true);
          
          if (success) {
            logger.i('Attendance logged at ${DateFormat('hh:mm a').format(now)}');
            GeofenceService.logActivity(_user!.uid, 'submit_attendance',
                'User submitted attendance and is present within geofence');
            
            // Update state and preferences
            SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setBool('isGeofenceActive', true);
            await _saveExitState(false);
            
            setState(() {
              _isPresent = true;
              _entryTime = now;
              _hasExitedGeofence = false;
            });
            
            _startGeofencing();
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Attendance marked successfully at ${DateFormat('hh:mm a').format(now)}'),
                backgroundColor: Colors.green,
              ),
            );
          } else {
            // Already marked today
            _showAlreadyMarkedDialog();
          }
        } else {
          logger.i('User is outside geofence');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('You are outside the geofence. You are marked as absent.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location permissions are required to log attendance.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      logger.e('Error submitting attendance: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error submitting attendance: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
  
  void _showAlreadyMarkedDialog() {
    String timeText = '';
    if (_entryTime != null) {
      timeText = ' at ${DateFormat('hh:mm a').format(_entryTime!)}';
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Attendance Already Marked'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You have already marked your attendance today$timeText.'),
            SizedBox(height: 8),
            Text('You can mark attendance again only after exiting and re-entering the geofence area.'),
            SizedBox(height: 16),
            if (_entryTime != null)
              Text(
                'Session started: ${DateFormat('hh:mm a').format(_entryTime!)}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            SizedBox(height: 8),
            Text(
              'Current status: ${_isGeofencingStarted ? "Tracking active" : "Tracking inactive"}',
              style: TextStyle(color: _isGeofencingStarted ? Colors.green : Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  // Add a button and method to view attendance history
  void _viewAttendanceHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AttendanceHistoryScreen(userId: _user!.uid),
      ),
    );
  }
  
  // Show session information
  Widget _buildSessionInfo() {
    if (_entryTime == null) {
      return Container();
    }
    
    final now = DateTime.now();
    final duration = now.difference(_entryTime!);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    
    return Container(
      padding: EdgeInsets.all(12),
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Session',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Entry time:'),
              Text(
                DateFormat('hh:mm a').format(_entryTime!),
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Current duration:'),
              Text(
                '$hours hour${hours != 1 ? 's' : ''} $minutes minute${minutes != 1 ? 's' : ''}',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    logger.i('Building widget: isPresent=$_isPresent, hasExited=$_hasExitedGeofence');
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance'),
        actions: [
          IconButton(
            icon: Icon(Icons.history),
            onPressed: _user != null ? () => _viewAttendanceHistory() : null,
            tooltip: 'View Attendance History',
          ),
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () {
              Navigator.pushNamed(context, '/profile');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _geofenceCenter,
                zoom: 16,
              ),
              circles: _circles,
              markers: _markers,
              onMapCreated: (controller) {
                _mapController = controller;
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // Status card
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _isPresent 
                        ? Colors.green.withOpacity(0.2) 
                        : Colors.orange.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _isPresent ? Colors.green : Colors.orange
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isPresent ? Icons.check_circle : Icons.info_outline,
                        color: _isPresent ? Colors.green : Colors.orange,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isPresent 
                                  ? 'Attendance marked for today' 
                                  : 'Attendance not marked yet',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (_entryTime != null)
                              Text(
                                'Entry time: ${DateFormat('hh:mm a').format(_entryTime!)}',
                                style: TextStyle(fontSize: 12),
                              ),
                            if (_isGeofencingStarted)
                              Text(
                                'Tracking active: Inside geofence',
                                style: TextStyle(fontSize: 12, color: Colors.green),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 12),
                
                // Session information (if active)
                if (_isPresent && _entryTime != null)
                  _buildSessionInfo(),
                
                // Mark attendance button or status
                if (_isPresent && !_hasExitedGeofence)
                  ElevatedButton(
                    onPressed: _showAlreadyMarkedDialog,
                    child: Text('Already Marked Attendance'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey,
                      foregroundColor: Colors.white,
                      minimumSize: Size(double.infinity, 50),
                    ),
                  )
                else
                  _isLoading
                      ? Center(child: CircularProgressIndicator())
                      : ElevatedButton(
                          onPressed: _submitAttendance,
                          child: Text(_hasExitedGeofence 
                              ? 'Mark Attendance (Re-entry)' 
                              : 'Mark Attendance'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: Size(double.infinity, 50),
                          ),
                        ),
                SizedBox(height: 8),
                
                // View history button
                OutlinedButton.icon(
                  onPressed: _user != null ? () => _viewAttendanceHistory() : null,
                  icon: Icon(Icons.history),
                  label: Text('View Attendance History'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                  ),
                ),
                
                SizedBox(height: 8),
                
                // Dashboard button
                ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, '/dashboard');
                  },
                  child: Text('Go to Dashboard'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: Size(double.infinity, 50),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
