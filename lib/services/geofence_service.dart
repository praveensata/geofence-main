import 'dart:async';
import 'dart:isolate';
import 'dart:ui';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:logger/logger.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter/material.dart';
import 'notification_service.dart';
import 'api_service.dart';

import '../models/geofence.dart';
import '../models/geofence_event.dart';
import '../models/user_model.dart';

// Constants
const double defaultGeofenceRadius = 50.0;
const double defaultLatitude = 17.736839; 
const double defaultLongitude = 83.333469;

// Background task name
const String geoFenceTrackingTask = 'com.geofence.tracking';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    switch (task) {
      case geoFenceTrackingTask:
        await performBackgroundGeofenceTracking();
        break;
    }
    return Future.value(true);
  });
}

@pragma('vm:entry-point')
Future<void> performBackgroundGeofenceTracking() async {
  final prefs = await SharedPreferences.getInstance();
  final isTrackingEnabled = prefs.getBool('tracking_enabled') ?? false;
  
  if (!isTrackingEnabled) {
    return;
  }
  
  try {
    // Get current location
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    
    // Process geofences with this position
    await GeofenceService.processGeofencesWithPosition(position);
  } catch (e) {
    print('Error in background geofence tracking: $e');
  }
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  
  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }
  
  service.on('stopService').listen((event) {
    service.stopSelf();
  });
  
  // Run geofence tracking logic periodically
  Timer.periodic(const Duration(minutes: 1), (timer) async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      await GeofenceService.processGeofencesWithPosition(position);
    } catch (e) {
      print('Error in background service: $e');
    }
  });
}

class GeofenceService {
  static const double geofenceRadius = defaultGeofenceRadius; // in meters
  static const double collegeLatitude = defaultLatitude; // default latitude
  static const double collegeLongitude = defaultLongitude; // default longitude
  static final logger = Logger();
  static double totalDistance = 0.0;
  static Position? lastPosition;

  // Constants for background task
  static const String backgroundTaskName = "geofenceMonitoring";
  static const String backgroundTaskInputData = "geofenceData";
  static const String portName = "geofence_isolate_port";

  // Singleton pattern
  static final GeofenceService _instance = GeofenceService._internal();
  static GeofenceService get instance => _instance;
  
  // Initialize these as late to avoid null issues
  late FirebaseFirestore _firestore;
  late FirebaseAuth _auth;
  
  // Track active geofences
  List<Geofence> _activeGeofences = [];
  Map<String, bool> _userInsideGeofence = {};
  
  // Service initialized state
  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;
  
  // Geofence data stream
  final _geofenceEventStream = StreamController<GeofenceEvent>.broadcast();
  Stream<GeofenceEvent> get geofenceEventStream => _geofenceEventStream.stream;
  
  // Current tracking state
  bool _isTrackingEnabled = false;
  bool get isTrackingEnabled => _isTrackingEnabled;
  
  // Timer for foreground tracking
  Timer? _locationTimer;
  StreamSubscription<Position>? _positionStream;
  
  // Current known device info
  String _deviceInfo = 'Unknown device';
  
  // Private constructor
  GeofenceService._internal();
  
  // Static method to process geofences with a position (used by background tasks)
  static Future<void> processGeofencesWithPosition(Position position) async {
    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final FirebaseAuth auth = FirebaseAuth.instance;
      
      final User? currentUser = auth.currentUser;
      if (currentUser == null) {
        logger.w('No user signed in for geofence processing');
        return;
      }
      
      try {
        // Safely call the instance method with proper error handling
        await GeofenceService.instance._checkGeofencesWithPosition(position);
        logger.i('Successfully processed geofences with position');
      } catch (e) {
        logger.e('Error in _checkGeofencesWithPosition: $e');
        // Don't rethrow to prevent background process from stopping
      }
    } catch (e) {
      // Log but don't crash the background process
      logger.e('Error processing geofences in background: $e');
    }
  }
  
  // Initialize the geofence service
  Future<void> initialize() async {
    try {
      logger.i('Initializing GeofenceService');
      
      // Request permissions
      await _requestLocationPermissions();
      
      // Initialize services
      _firestore = FirebaseFirestore.instance;
      _auth = FirebaseAuth.instance;
      
      // Check if we have active geofences and update their data
      try {
        await _loadActiveGeofences();
        logger.i('Loaded active geofences successfully');
      } catch (e) {
        logger.e('Error loading active geofences: $e');
        // Initialize with empty list if there's an error
        _activeGeofences = [];
      }
      
      // Check for any unclosed sessions from previous app runs
      await _checkForUnclosedSessions();
      
      _isInitialized = true;
      logger.i('GeofenceService initialized successfully');
    } catch (e) {
      logger.e('Error initializing GeofenceService: $e');
      // Don't rethrow, just log the error
    }
  }
  
  // Load active geofences from Firestore
  Future<void> _loadActiveGeofences() async {
    try {
      final snapshot = await _firestore.collection('geofences')
          .where('isActive', isEqualTo: true)
          .get();
      
      _activeGeofences = snapshot.docs
          .map((doc) => Geofence.fromFirestore(doc))
          .toList();
      
      logger.i('Loaded ${_activeGeofences.length} active geofences');
    } catch (e) {
      logger.e('Error loading active geofences: $e');
      // Initialize with empty list if there's an error
      _activeGeofences = [];
    }
  }
  
  // Request location permissions
  Future<bool> _requestLocationPermissions() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;
      
      // Test if location services are enabled.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logger.w('Location services are disabled.');
        return false;
      }
      
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.w('Location permissions are denied');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        logger.w('Location permissions are permanently denied');
        return false;
      }
      
      return true;
    } catch (e) {
      logger.e('Error requesting location permission: $e');
      return false;
    }
  }
  
  // Load geofences from Firestore
  Future<void> _loadGeofencesFromFirestore() async {
    try {
      final snapshot = await _firestore.collection('geofences').get();
      
      logger.i('Loaded ${snapshot.docs.length} geofences from Firestore');
    } catch (e) {
      logger.e('Error loading geofences from Firestore: $e');
    }
  }
  
  // Get device information
  Future<void> _initDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceInfo = '${androidInfo.manufacturer} ${androidInfo.model}';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceInfo = '${iosInfo.name} ${iosInfo.systemVersion}';
      }
    } catch (e) {
      logger.e('Error getting device info: $e');
    }
  }
  
  // Setup background service
  Future<void> _initializeBackgroundService() async {
    try {
      if (Platform.isAndroid) {
        final service = FlutterBackgroundService();
        
        await service.configure(
          androidConfiguration: AndroidConfiguration(
            onStart: onStart,
            autoStart: false,
            isForegroundMode: true,
            notificationChannelId: 'geofence_service',
            initialNotificationTitle: 'Geofence Service',
            initialNotificationContent: 'Tracking your location',
            foregroundServiceNotificationId: 888,
          ),
          iosConfiguration: IosConfiguration(
            autoStart: false,
            onForeground: onStart,
            onBackground: onIosBackground,
          ),
        );
      }
      
      logger.i('Background service initialized');
    } catch (e) {
      logger.e('Error initializing background service: $e');
    }
  }
  
  // Check location permissions
  Future<bool> requestLocationPermission() async {
    try {
      bool serviceEnabled;
      LocationPermission permission;
      
      // Test if location services are enabled.
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        logger.w('Location services are disabled.');
        return false;
      }
      
      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          logger.w('Location permissions are denied');
          return false;
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        logger.w('Location permissions are permanently denied, we cannot request permissions.');
        return false;
      }
      
      return true;
    } catch (e) {
      logger.e('Error requesting location permission: $e');
      return false;
    }
  }
  
  // Start background tracking
  Future<void> startBackgroundTracking() async {
    try {
      // Save tracking state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tracking_enabled', true);
      
      // Start foreground service for Android
      if (Platform.isAndroid) {
        final service = FlutterBackgroundService();
        await service.startService();
      }
      
      // Register periodic background task
      await Workmanager().registerPeriodicTask(
        'geofenceTracking',
        geoFenceTrackingTask,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      
      logger.i('Background tracking started');
    } catch (e) {
      logger.e('Error starting background tracking: $e');
    }
  }
  
  // Stop background tracking
  Future<void> stopBackgroundTracking() async {
    try {
      // Update tracking state
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tracking_enabled', false);
      
      // Stop foreground service for Android
      if (Platform.isAndroid) {
        final service = FlutterBackgroundService();
        service.invoke('stopService');
      }
      
      // Cancel background tasks
      await Workmanager().cancelAll();
      
      logger.i('Background tracking stopped');
    } catch (e) {
      logger.e('Error stopping background tracking: $e');
    }
  }
  
  // Start tracking
  Future<void> startTracking() async {
    try {
      if (!_isInitialized) {
        await initialize();
      }
      
      // Check location permission again
      bool hasPermission = await requestLocationPermission();
      if (!hasPermission) {
        logger.w('Cannot start tracking: insufficient location permissions');
        return;
      }
      
      // Stop any existing tracking first
      await stopTracking();
      
      // Start background tracking
      await startBackgroundTracking();
      
      // Start foreground tracking timer
      _startForegroundTrackingTimer();
      
      logger.i('Geofence tracking started');
    } catch (e) {
      logger.e('Error starting tracking: $e');
    }
  }
  
  // Stop tracking
  Future<void> stopTracking() async {
    try {
      // Cancel foreground tracking
      _locationTimer?.cancel();
      _locationTimer = null;
      
      // Stop background tracking
      await stopBackgroundTracking();
      
      logger.i('Geofence tracking stopped');
    } catch (e) {
      logger.e('Error stopping tracking: $e');
    }
  }
  
  // Timer for foreground tracking
  void _startForegroundTrackingTimer() {
    _locationTimer = Timer.periodic(const Duration(minutes: 1), (timer) async {
      await _checkGeofences();
    });
  }
  
  // Process geofences with current position
  Future<void> _checkGeofences() async {
    try {
      // Get current position
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      await _checkGeofencesWithPosition(position);
    } catch (e) {
      logger.e('Error checking geofences: $e');
    }
  }
  
  // Check geofences with the given position
  Future<void> _checkGeofencesWithPosition(Position position) async {
    if (_activeGeofences.isEmpty) {
      return;
    }
    
    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        logger.w('No user signed in, skipping geofence check');
        return;
      }
      
      // Save the last position to preferences for recovery if app is killed
      _saveLastPosition(position);
      
      for (final geofence in _activeGeofences) {
        try {
      double distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
            geofence.latitude,
            geofence.longitude,
          );
          
          bool isInside = distance <= geofence.radius;
          bool wasInside = _userInsideGeofence[geofence.id] ?? false;
          
          if (isInside && !wasInside) {
            // User entered geofence
            logger.i('User entered geofence: ${geofence.name}');
            _userInsideGeofence[geofence.id] = true;
            await _handleGeofenceEntry(user, geofence, position);
          } else if (!isInside && wasInside) {
            // User exited geofence
            logger.i('User exited geofence: ${geofence.name}');
            _userInsideGeofence[geofence.id] = false;
            await _handleGeofenceExit(user, geofence, position);
          }
        } catch (e) {
          logger.e('Error checking individual geofence ${geofence.id}: $e');
          // Continue checking other geofences
        }
      }
    } catch (e) {
      logger.e('Error in _checkGeofencesWithPosition: $e');
    }
  }
  
  // Handle geofence entry
  Future<void> _handleGeofenceEntry(User user, Geofence geofence, Position position) async {
    try {
      // Load user data to get user name
      DocumentSnapshot userDoc;
      String userName;
      
      try {
        userDoc = await _firestore.collection('users').doc(user.uid).get();
        // Fix the way we extract userName from userDoc
        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data() as Map<String, dynamic>;
          userName = userData['name'] ?? user.displayName ?? 'Unknown User';
        } else {
          userName = user.displayName ?? 'Unknown User';
        }
      } catch (e) {
        logger.e('Error getting user data: $e');
        userName = user.displayName ?? 'Unknown User';
      }
      
      // Create a session ID first
      final sessionId = const Uuid().v4();
      
      // Create geofence entry event with sessionId
      final event = GeofenceEvent(
        id: const Uuid().v4(),
        userId: user.uid,
        userName: userName,
        geofenceId: geofence.id,
        geofenceName: geofence.name,
        timestamp: DateTime.now(),
        eventType: 'entry',
        location: GeoPoint(position.latitude, position.longitude),
        sessionId: sessionId, // Use the newly created sessionId
        isProcessed: false,
      );
      
      // Record the event
      await _recordGeofenceEvent(event);
      
      // Broadcast the event
      _geofenceEventStream.add(event);
      
      // Send notification
      NotificationService.displayNotification(
        'Geofence Entry',
        'You have entered ${geofence.name}',
      );
      
      // Log for backward compatibility
      await logActivity(
        user.uid,
        'ENTRY',
        'User entered geofence: ${geofence.name}',
        metadata: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'geofenceId': geofence.id,
        },
      );
    } catch (e) {
      logger.e('Error handling geofence entry: $e');
    }
  }
  
  // Handle geofence exit
  Future<void> _handleGeofenceExit(User user, Geofence geofence, Position position) async {
    try {
      // Find active session for this user and geofence
      final sessionQuery = await _firestore.collection('geofence_sessions')
          .where('userId', isEqualTo: user.uid)
          .where('geofenceId', isEqualTo: geofence.id)
          .where('isActive', isEqualTo: true)
          .limit(1)
          .get();
      
      String sessionId = '';
      if (sessionQuery.docs.isNotEmpty) {
        sessionId = sessionQuery.docs.first.id;
      }
      
      // Load user data to get user name
      DocumentSnapshot userDoc;
      String userName;
      
      try {
        userDoc = await _firestore.collection('users').doc(user.uid).get();
        // Fix the way we extract userName from userDoc
        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data() as Map<String, dynamic>;
          userName = userData['name'] ?? user.displayName ?? 'Unknown User';
        } else {
          userName = user.displayName ?? 'Unknown User';
        }
      } catch (e) {
        logger.e('Error getting user data: $e');
        userName = user.displayName ?? 'Unknown User';
      }
      
      // Create geofence exit event
      final event = GeofenceEvent(
        id: const Uuid().v4(),
        userId: user.uid,
        userName: userName,
        geofenceId: geofence.id,
        geofenceName: geofence.name,
        timestamp: DateTime.now(),
        eventType: 'exit',
        location: GeoPoint(position.latitude, position.longitude),
        sessionId: sessionId, // This will be empty string if no session was found
        isProcessed: false,
      );
      
      // Record the event
      await _recordGeofenceEvent(event);
      
      // Use ApiService to record exit event in the attendance system
      try {
        // ApiService is already imported at the top of the file
        final apiService = ApiService();
        final exitTime = DateTime.now();
        
        // Record exit in the attendance system
        final exitRecorded = await apiService.recordExit(user.uid, exitTime);
        
        if (exitRecorded) {
          logger.i('Successfully recorded exit event in attendance system');
        } else {
          logger.w('No matching entry record found for exit event');
        }
      } catch (e) {
        logger.e('Error recording exit in attendance system: $e');
      }
      
      // Broadcast the event
      _geofenceEventStream.add(event);
      
      // Send notification
      NotificationService.displayNotification(
        'Geofence Exit',
        'You have exited ${geofence.name}',
      );
      
      // Log for backward compatibility
      await logActivity(
        user.uid,
        'EXIT',
        'User exited geofence: ${geofence.name}',
        metadata: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'geofenceId': geofence.id,
        },
      );
    } catch (e) {
      logger.e('Error handling geofence exit: $e');
    }
  }
  
  // Record geofence event
  Future<void> _recordGeofenceEvent(GeofenceEvent event) async {
    try {
      // Get a reference to the geofence_events collection
      final eventsRef = _firestore.collection('geofence_events');
      
      if (event.eventType == 'entry') {
        // For entry events, create a new session document
        final sessionsRef = _firestore.collection('geofence_sessions');
        final sessionDoc = sessionsRef.doc(event.sessionId);
        
        // Create a new session with status active
        final session = GeofenceSession(
          id: event.sessionId,
          userId: event.userId,
          userName: event.userName,
          geofenceId: event.geofenceId,
          geofenceName: event.geofenceName,
          entryTime: event.timestamp,
          isActive: true,
        );
        
        // Add the session and event to Firestore
        try {
          await sessionDoc.set(session.toMap());
          await eventsRef.doc(event.id).set(event.toMap());
          logger.i('Recorded entry event and created session ${event.sessionId}');
        } catch (e) {
          logger.e('Error writing entry event to Firestore: $e');
        }
      } else if (event.eventType == 'exit') {
        // For exit events, update the session if it exists
        try {
          if (event.sessionId.isNotEmpty) {
            final sessionRef = _firestore.collection('geofence_sessions').doc(event.sessionId);
            final sessionDoc = await sessionRef.get();
            
            if (sessionDoc.exists) {
              final session = GeofenceSession.fromFirestore(sessionDoc);
              
              // Calculate duration
              final duration = event.timestamp.difference(session.entryTime).inSeconds;
              
              // Update session with exit time and duration
              // Create a new session with updated fields since copyWith is not available
              final updatedSession = GeofenceSession(
                id: session.id,
                userId: session.userId,
                userName: session.userName,
                geofenceId: session.geofenceId,
                geofenceName: session.geofenceName,
                entryTime: session.entryTime,
                exitTime: event.timestamp,
                duration: Duration(seconds: duration),
                isActive: false,
              );
              
              // Update the event with duration information
              final updatedEvent = event.copyWith(
                entryTime: session.entryTime,
                duration: Duration(seconds: duration),
              );
              
              // Update Firestore
              await sessionRef.update(updatedSession.toMap());
              await eventsRef.doc(updatedEvent.id).set(updatedEvent.toMap());
              logger.i('Updated session ${session.id} with exit data');
            } else {
              // Session not found, just record the exit event
              await eventsRef.doc(event.id).set(event.toMap());
              logger.w('Session ${event.sessionId} not found for exit event');
            }
          } else {
            // No session ID, just record the exit event
            await eventsRef.doc(event.id).set(event.toMap());
            logger.w('No session ID provided for exit event');
          }
        } catch (e) {
          logger.e('Error processing exit event: $e');
          // Still try to record the event even if session update fails
          await eventsRef.doc(event.id).set(event.toMap());
        }
      }
    } catch (e) {
      logger.e('Error in _recordGeofenceEvent: $e');
    }
  }
  
  // Log activity for compatibility
  static Future<void> logActivityWithParams({
    required String userId,
    required String activityType,
    required String description,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final firestore = FirebaseFirestore.instance;
      
      // Get user name from Firestore
      String userName = 'Unknown User';
      try {
        final userDoc = await firestore.collection('users').doc(userId).get();
        if (userDoc.exists && userDoc.data() != null) {
          final userData = userDoc.data() as Map<String, dynamic>;
          userName = userData['name'] ?? 'Unknown User';
      } else {
          // If user document doesn't exist, try to get name from Firebase Auth
          final user = FirebaseAuth.instance.currentUser;
          if (user != null && user.uid == userId) {
            userName = user.displayName ?? 'Unknown User';
          }
        }
      } catch (e) {
        logger.e('Error getting user name for activity log: $e');
      }
      
      // Add activity log with user name
      await firestore.collection('activity_logs').add({
        'userId': userId,
        'userName': userName, // Include user name in the activity log
        'activity': activityType,
        'description': description,
        'timestamp': Timestamp.now(),
        'metadata': metadata ?? {},
      });
      
      logger.i('Logged activity for $userName: $activityType - $description');
    } catch (e) {
      logger.e('Error logging activity: $e');
    }
  }

  // Backward compatibility for old logActivity calls
  static Future<void> logActivity(
    String userId,
    String activityType,
    String description, {
    Map<String, dynamic>? metadata,
  }) async {
    return await logActivityWithParams(
      userId: userId,
      activityType: activityType,
      description: description,
      metadata: metadata,
    );
  }

  // Backward compatibility for notification on exit
  static Future<void> notifyUserOnExit() async {
    try {
      NotificationService.displayNotification(
        'Geofence Exit',
        'You have exited the geofence area.',
      );
      
      // Also record this exit in the attendance system
      try {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
          final apiService = ApiService();
          final exitTime = DateTime.now();
          
          // Record exit in the attendance system
          final exitRecorded = await apiService.recordExit(user.uid, exitTime);
          
          if (exitRecorded) {
            logger.i('Successfully recorded exit event for user ${user.uid}');
          } else {
            logger.w('No matching entry record found for user ${user.uid}');
          }
        }
      } catch (e) {
        logger.e('Error recording exit in attendance system: $e');
      }
    } catch (e) {
      logger.e('Error displaying notification: $e');
    }
  }
  
  // Check if within geofence for compatibility
  static Future<bool> isWithinGeofence() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      // Calculate distance to default geofence
      final distanceInMeters = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        collegeLatitude,
        collegeLongitude,
      );
      
      return distanceInMeters <= geofenceRadius;
    } catch (e) {
      logger.e('Error checking if within geofence: $e');
      return false;
    }
  }
  
  // Backward compatibility for starting geofencing
  static Future<void> startGeofencing(
    Function onEnterGeofence,
    Function onExitGeofence,
  ) async {
    await GeofenceService.instance.startTracking();
  }
  
  // Get all geofence events for a specific user
  Stream<List<GeofenceEvent>> getUserGeofenceEvents(String userId) {
    return _firestore
        .collection('geofence_events')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GeofenceEvent.fromFirestore(doc))
              .toList();
        });
  }
  
  // Get all geofence sessions for a specific user
  Stream<List<GeofenceSession>> getUserGeofenceSessions(String userId) {
    return _firestore
        .collection('geofence_sessions')
        .where('userId', isEqualTo: userId)
        .orderBy('entryTime', descending: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GeofenceSession.fromFirestore(doc))
              .toList();
        });
  }
  
  // Get active sessions (user currently inside geofence)
  Stream<List<GeofenceSession>> getActiveGeofenceSessions() {
    return _firestore
        .collection('geofence_sessions')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => GeofenceSession.fromFirestore(doc))
              .toList();
        });
  }
  
  // Dispose of the service
  Future<void> dispose() async {
    await stopTracking();
    await _geofenceEventStream.close();
    _isInitialized = false;
  }

  // Check for any unclosed sessions and close them if needed
  Future<void> _checkForUnclosedSessions() async {
    try {
      final User? user = _auth.currentUser;
      if (user == null) {
        logger.w('No user signed in, skipping unclosed session check');
        return;
      }
      
      // Get the last known location from preferences
      final prefs = await SharedPreferences.getInstance();
      final lastLat = prefs.getDouble('last_latitude');
      final lastLng = prefs.getDouble('last_longitude');
      final lastTimestamp = prefs.getInt('last_position_timestamp');
      
      if (lastLat == null || lastLng == null || lastTimestamp == null) {
        logger.i('No last known position found, skipping unclosed session check');
        return;
      }
      
      // Get current time
      final now = DateTime.now();
      final lastPositionTime = DateTime.fromMillisecondsSinceEpoch(lastTimestamp);
      
      // If last position is too old (more than 12 hours), ignore it
      if (now.difference(lastPositionTime).inHours > 12) {
        logger.i('Last position is too old, skipping unclosed session check');
        return;
      }
      
      // Find any active sessions for this user
      final sessionsQuery = await _firestore.collection('geofence_sessions')
          .where('userId', isEqualTo: user.uid)
          .where('isActive', isEqualTo: true)
          .get();
      
      if (sessionsQuery.docs.isEmpty) {
        logger.i('No active sessions found for user');
        return;
      }
      
      logger.i('Found ${sessionsQuery.docs.length} active sessions to check');
      
      // Check each session against the last known position
      for (final sessionDoc in sessionsQuery.docs) {
        try {
          final session = GeofenceSession.fromFirestore(sessionDoc);
          
          // Find the associated geofence
          final geofenceDoc = await _firestore.collection('geofences')
              .doc(session.geofenceId)
              .get();
          
          if (!geofenceDoc.exists) {
            logger.w('Geofence ${session.geofenceId} not found for session ${session.id}');
            continue;
          }
          
          final geofence = Geofence.fromFirestore(geofenceDoc);
          
          // Calculate distance from last known position to geofence
          final distance = Geolocator.distanceBetween(
            lastLat,
            lastLng,
            geofence.latitude,
            geofence.longitude,
          );
          
          // If user was outside geofence, close the session
          if (distance > geofence.radius) {
            logger.i('Last known position was outside geofence, closing session ${session.id}');
            
            // Create a position object for the last known position
            final position = Position(
              latitude: lastLat,
              longitude: lastLng,
              timestamp: lastPositionTime,
              accuracy: 0,
              altitude: 0,
              heading: 0,
              speed: 0,
              speedAccuracy: 0,
              altitudeAccuracy: 0,
              headingAccuracy: 0,
            );
            
            // Handle the exit event
            await _handleSessionExitRecovery(user, session, geofence, position);
          }
        } catch (e) {
          logger.e('Error processing session ${sessionDoc.id}: $e');
        }
      }
    } catch (e) {
      logger.e('Error checking for unclosed sessions: $e');
    }
  }
  
  // Handle session exit recovery for sessions that weren't properly closed
  Future<void> _handleSessionExitRecovery(User user, GeofenceSession session, Geofence geofence, Position position) async {
    try {
      // Use the session to create an exit event
      final event = GeofenceEvent(
        id: const Uuid().v4(),
        userId: user.uid,
        userName: session.userName,
        geofenceId: geofence.id,
        geofenceName: geofence.name,
        timestamp: DateTime.now(), // Use current time as exit time
        eventType: 'exit',
        location: GeoPoint(position.latitude, position.longitude),
        sessionId: session.id,
        isProcessed: false,
        entryTime: session.entryTime, // Include the original entry time
      );
      
      // Record the exit event
      await _recordGeofenceExitRecovery(event, session);
      
      // Log recovery action
      await logActivity(
        user.uid,
        'EXIT_RECOVERY',
        'Recovered exit event for session ${session.id} in geofence: ${geofence.name}',
        metadata: {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'geofenceId': geofence.id,
          'sessionId': session.id,
        },
      );
      
      logger.i('Successfully recovered exit event for session ${session.id}');
    } catch (e) {
      logger.e('Error handling session exit recovery: $e');
    }
  }
  
  // Record recovered exit event 
  Future<void> _recordGeofenceExitRecovery(GeofenceEvent event, GeofenceSession session) async {
    try {
      final eventsRef = _firestore.collection('geofence_events');
      final sessionRef = _firestore.collection('geofence_sessions').doc(session.id);
      
      // Calculate duration
      final duration = event.timestamp.difference(session.entryTime).inSeconds;
      
      // Update session with exit time and duration
      final updatedSession = GeofenceSession(
        id: session.id,
        userId: session.userId,
        userName: session.userName,
        geofenceId: session.geofenceId,
        geofenceName: session.geofenceName,
        entryTime: session.entryTime,
        exitTime: event.timestamp,
        duration: Duration(seconds: duration),
        isActive: false,
      );
      
      // Update the event with duration
      final updatedEvent = event.copyWith(
        duration: Duration(seconds: duration),
      );
      
      // Update Firestore
      await sessionRef.update(updatedSession.toMap());
      await eventsRef.doc(updatedEvent.id).set(updatedEvent.toMap());
      
      logger.i('Updated session ${session.id} with recovered exit data');
    } catch (e) {
      logger.e('Error recording recovered exit event: $e');
    }
  }

  // Save last position to preferences for recovery if app is killed
  Future<void> _saveLastPosition(Position position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_latitude', position.latitude);
      await prefs.setDouble('last_longitude', position.longitude);
      await prefs.setInt('last_position_timestamp', position.timestamp?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch);
      
      logger.d('Saved last position: ${position.latitude}, ${position.longitude}');
    } catch (e) {
      logger.e('Error saving last position: $e');
    }
  }
}
