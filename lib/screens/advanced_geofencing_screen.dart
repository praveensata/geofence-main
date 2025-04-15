import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import '../services/api_service.dart';
import '../services/geofence_service.dart';
import '../services/notification_service.dart';

class AdvancedGeofencingScreen extends StatefulWidget {
  const AdvancedGeofencingScreen({super.key});

  @override
  AdvancedGeofencingScreenState createState() => AdvancedGeofencingScreenState();
}

class AdvancedGeofencingScreenState extends State<AdvancedGeofencingScreen> with WidgetsBindingObserver {
  final logger = Logger();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _user = FirebaseAuth.instance.currentUser;
  
  // Geofence states
  bool _isWithinGeofence = false;
  bool _isMonitoring = false;
  
  // Current location
  Position? _currentPosition;
  
  // Google Maps
  GoogleMapController? _mapController;
  LatLng _geofenceCenter = LatLng(GeofenceService.collegeLatitude, GeofenceService.collegeLongitude);
  double _geofenceRadius = GeofenceService.geofenceRadius;
  
  // Map elements
  final Set<Circle> _circles = {};
  final Set<Marker> _markers = {};
  
  // Location tracking
  StreamSubscription<Position>? _positionStream;
  
  // Activity logs
  List<Map<String, dynamic>> _activityLogs = [];

  // Profile data
  String _userName = '';
  String _employeeId = '';
  bool _isProfileLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadProfileData();
    _checkGeofenceState();
    _setupMap();
    _getCurrentLocation();
    _loadActivityLogs();
  }
  
  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkGeofenceState();
      _getCurrentLocation();
    }
  }

  Future<void> _checkGeofenceState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isMonitoring = prefs.getBool('isGeofenceActive') ?? false;
    
    if (isMonitoring) {
      _startGeofenceMonitoring();
    }
    
    setState(() {
      _isMonitoring = isMonitoring;
    });
    
    // Check if user is within geofence
    await _checkIfWithinGeofence();
  }
  
  Future<void> _checkIfWithinGeofence() async {
    bool isWithin = await GeofenceService.isWithinGeofence();
    setState(() {
      _isWithinGeofence = isWithin;
    });
  }

  void _setupMap() {
    setState(() {
      _circles.add(Circle(
        circleId: const CircleId('geofence'),
        center: _geofenceCenter,
        radius: _geofenceRadius,
        fillColor: Colors.blue.withOpacity(0.3),
        strokeColor: Colors.blue,
        strokeWidth: 2,
      ));

      _markers.add(Marker(
        markerId: const MarkerId('geofence_center'),
        position: _geofenceCenter,
        infoWindow: const InfoWindow(title: 'Geofence Center'),
      ));
    });
  }

  Future<void> _getCurrentLocation() async {
    var status = await Permission.location.request();
    if (!mounted) return;

    if (status.isGranted) {
      try {
        Position position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        
        if (!mounted) return;
        
        setState(() {
          _currentPosition = position;
          
          // Update the current location marker
          _markers.removeWhere((marker) => marker.markerId.value == 'current_location');
          _markers.add(Marker(
            markerId: const MarkerId('current_location'),
            position: LatLng(position.latitude, position.longitude),
            infoWindow: const InfoWindow(title: 'You are here'),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          ));
        });
        
        // Move camera to current location
        _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(
            LatLng(position.latitude, position.longitude),
            16,
          ),
        );
        
        // Check if within geofence
        await _checkIfWithinGeofence();
        
      } catch (e) {
        logger.e('Error getting current location: $e');
      }
    } else {
      logger.e('Location permissions are denied');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location permissions are required')),
      );
    }
  }

  void _startGeofenceMonitoring() {
    if (_positionStream != null) {
      return; // Already monitoring
    }
    
    _positionStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Update every 5 meters
      ),
    ).listen((position) {
      _updateLocationOnMap(position);
      _checkGeofenceStatus(position);
    });
    
    setState(() {
      _isMonitoring = true;
    });
    
    _saveGeofenceState(true);
    NotificationService.displayNotification(
      'Geofence Monitoring',
      'Geofence monitoring has been started'
    );
  }
  
  void _stopGeofenceMonitoring() {
    _positionStream?.cancel();
    _positionStream = null;
    
    setState(() {
      _isMonitoring = false;
    });
    
    _saveGeofenceState(false);
    NotificationService.displayNotification(
      'Geofence Monitoring',
      'Geofence monitoring has been stopped'
    );
  }
  
  Future<void> _saveGeofenceState(bool isActive) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isGeofenceActive', isActive);
  }
  
  void _updateLocationOnMap(Position position) {
    if (!mounted) return;
    
    setState(() {
      _currentPosition = position;
      
      // Update marker
      _markers.removeWhere((marker) => marker.markerId.value == 'current_location');
      _markers.add(Marker(
        markerId: const MarkerId('current_location'),
        position: LatLng(position.latitude, position.longitude),
        infoWindow: const InfoWindow(title: 'You are here'),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ));
    });
  }
  
  void _checkGeofenceStatus(Position position) {
    double distance = Geolocator.distanceBetween(
      _geofenceCenter.latitude,
      _geofenceCenter.longitude,
      position.latitude,
      position.longitude,
    );
    
    bool wasWithinGeofence = _isWithinGeofence;
    bool isNowWithinGeofence = distance <= _geofenceRadius;
    
    if (wasWithinGeofence != isNowWithinGeofence) {
      // Status changed
      if (isNowWithinGeofence) {
        _onEnterGeofence();
      } else {
        _onExitGeofence();
      }
    }
    
    setState(() {
      _isWithinGeofence = isNowWithinGeofence;
    });
  }
  
  void _onEnterGeofence() {
    if (_user == null) return;
    
    logger.i('Entered geofence');
    NotificationService.displayNotification(
      'Geofence Alert',
      'You have entered the geofence area'
    );
    
    GeofenceService.logActivity(
      _user!.uid,
      'ENTER',
      'Entered geofence area'
    );
    
    _loadActivityLogs(); // Refresh logs
  }
  
  void _onExitGeofence() {
    if (_user == null) return;
    
    logger.i('Exited geofence');
    NotificationService.displayNotification(
      'Geofence Alert',
      'You have exited the geofence area'
    );
    
    GeofenceService.logActivity(
      _user!.uid,
      'EXIT',
      'Exited geofence area'
    );
    
    _loadActivityLogs(); // Refresh logs
  }
  
  Future<void> _markAttendance() async {
    if (_user == null) return;
    
    if (_isWithinGeofence) {
      await ApiService().logAttendance(_user!.uid, DateTime.now(), true);
      
      GeofenceService.logActivity(
        _user!.uid,
        'ATTENDANCE',
        'Marked attendance within geofence'
      );
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attendance marked successfully')),
      );
      
      // Start monitoring if not already started
      if (!_isMonitoring) {
        _startGeofenceMonitoring();
      }
      
      _loadActivityLogs(); // Refresh logs
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be within the geofence to mark attendance')),
      );
    }
  }
  
  Future<void> _loadActivityLogs() async {
    if (_user == null) return;
    
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('activity_logs')
          .where('userId', isEqualTo: _user!.uid)
          .orderBy('timestamp', descending: true)
          .limit(10)
          .get();
      
      if (!mounted) return;
      
      setState(() {
        _activityLogs = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'timestamp': (data['timestamp'] as Timestamp).toDate(),
            'activity': data['activity'],
            'description': data['description'],
          };
        }).toList();
      });
    } catch (e) {
      logger.e('Error loading activity logs: $e');
    }
  }

  Future<void> _loadProfileData() async {
    if (_user == null) return;
    
    try {
      DocumentSnapshot doc = await _firestore.collection('users').doc(_user!.uid).get();
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        
        setState(() {
          _userName = data['name'] ?? _user?.displayName ?? 'User';
          _employeeId = data['customUserId'] ?? '';
          _isProfileLoaded = true;
        });
        
        logger.i('Profile loaded: $_userName, $_employeeId');
      } else {
        setState(() {
          _userName = _user?.displayName ?? 'User';
          _isProfileLoaded = true;
        });
      }
    } catch (e) {
      logger.e('Error loading profile: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Geofencing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _getCurrentLocation();
              _loadActivityLogs();
              _loadProfileData();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // User info card
          if (_isProfileLoaded && (_userName.isNotEmpty || _employeeId.isNotEmpty))
            Card(
              margin: const EdgeInsets.all(8.0),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 24, color: Colors.blue),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _userName,
                            style: const TextStyle(
                              fontSize: 16, 
                              fontWeight: FontWeight.bold
                            ),
                          ),
                          if (_employeeId.isNotEmpty)
                            Text(
                              'ID: $_employeeId',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.pushNamed(context, '/profile'),
                      icon: const Icon(Icons.edit, size: 16),
                      label: const Text('Edit'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, 
                          vertical: 8
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Status bar
          Container(
            padding: const EdgeInsets.all(8.0),
            color: _isWithinGeofence ? Colors.green.shade100 : Colors.red.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _isWithinGeofence 
                      ? 'Status: Within Geofence' 
                      : 'Status: Outside Geofence',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isWithinGeofence ? Colors.green.shade800 : Colors.red.shade800,
                  ),
                ),
                Text(
                  _isMonitoring 
                      ? 'Monitoring: Active' 
                      : 'Monitoring: Inactive',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isMonitoring ? Colors.blue.shade800 : Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
          
          // Map
          Expanded(
            flex: 3,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _geofenceCenter,
                zoom: 16,
              ),
              circles: _circles,
              markers: _markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (controller) {
                _mapController = controller;
              },
            ),
          ),
          
          // Distance info and actions
          if (_currentPosition != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                'Distance to geofence center: ${Geolocator.distanceBetween(
                  _geofenceCenter.latitude,
                  _geofenceCenter.longitude,
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                ).toStringAsFixed(2)} meters',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          
          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: _isMonitoring ? _stopGeofenceMonitoring : _startGeofenceMonitoring,
                  icon: Icon(_isMonitoring ? Icons.stop : Icons.play_arrow),
                  label: Text(_isMonitoring ? 'Stop Monitoring' : 'Start Monitoring'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isMonitoring ? Colors.red : Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _markAttendance,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Mark Attendance'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          
          // Activity logs
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: _activityLogs.length,
                    itemBuilder: (context, index) {
                      final log = _activityLogs[index];
                      return ListTile(
                        leading: Icon(
                          log['activity'] == 'ENTER' 
                              ? Icons.login 
                              : log['activity'] == 'EXIT' 
                                  ? Icons.logout 
                                  : Icons.check_circle,
                          color: log['activity'] == 'ENTER' 
                              ? Colors.green 
                              : log['activity'] == 'EXIT' 
                                  ? Colors.red 
                                  : Colors.blue,
                        ),
                        title: Text(log['activity']),
                        subtitle: Text(
                          '${log['description']} - ${DateFormat('MMM dd, HH:mm:ss').format(log['timestamp'])}'
                        ),
                        dense: true,
                      );
                    },
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