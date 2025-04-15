import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationService {
  static final Logger _logger = Logger();
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseAuth _auth = FirebaseAuth.instance;
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  // Local notifications plugin
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  // Notification channel ID
  static const String _channelId = 'geofence_channel';
  static const String _channelName = 'Geofence Notifications';
  static const String _channelDesc = 'Notifications for geofence events';
  
  // Notification IDs
  static int _notificationId = 0;
  
  // Instance getter for singleton
  static NotificationService? _instance;
  static NotificationService get instance {
    _instance ??= NotificationService._internal();
    return _instance!;
  }
  
  // Private constructor
  NotificationService._internal();
  
  // Initialize the notification service
  static Future<void> initialize() async {
    try {
      // Request permission with error handling
      try {
        await _requestPermission();
        _logger.i('Notification permissions requested successfully');
      } catch (e) {
        _logger.e('Error requesting notification permission: $e');
        // Continue initialization even if permission request fails
      }
      
      // Configure FCM with error handling
      try {
        await _configureFCM();
        _logger.i('FCM configured successfully');
      } catch (e) {
        _logger.e('Error configuring FCM: $e');
        // Continue initialization even if FCM configuration fails
      }
      
      // Initialize local notifications with error handling
      try {
        await _initializeLocalNotifications();
        _logger.i('Local notifications initialized successfully');
      } catch (e) {
        _logger.e('Error initializing local notifications: $e');
        // Continue even if local notifications fail
      }
      
      _logger.i('NotificationService initialization completed');
    } catch (e) {
      _logger.e('Unexpected error in NotificationService initialization: $e');
      // The service will be partially functional depending on what succeeded
    }
  }
  
  // Request notification permission
  static Future<void> _requestPermission() async {
    try {
      NotificationSettings settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
      );
      
      _logger.i('User notification permission status: ${settings.authorizationStatus}');
    } catch (e) {
      _logger.e('Error requesting notification permission: $e');
      rethrow; // Propagate to the main try-catch in initialize
    }
  }
  
  // Configure Firebase Cloud Messaging
  static Future<void> _configureFCM() async {
    try {
      // Get FCM token with error handling
      try {
        String? token = await _messaging.getToken();
        if (token != null) {
          _logger.i('FCM Token obtained successfully');
          
          // Save token to user document if logged in
          try {
            final user = _auth.currentUser;
            if (user != null) {
              await _firestore.collection('users').doc(user.uid).update({
                'fcmTokens': FieldValue.arrayUnion([token]),
                'lastTokenUpdate': Timestamp.now(),
              });
              _logger.i('FCM Token saved to user document');
            }
          } catch (e) {
            _logger.e('Error saving FCM token to user document: $e');
            // Continue even if saving to Firestore fails
          }
          
          // Save token to shared preferences
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('fcm_token', token);
            _logger.i('FCM Token saved to shared preferences');
          } catch (e) {
            _logger.e('Error saving FCM token to shared preferences: $e');
            // Continue even if saving to shared preferences fails
          }
        }
      } catch (e) {
        _logger.e('Error getting FCM token: $e');
        // Continue configuration even if getting token fails
      }
      
      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) async {
        _logger.i('FCM Token refreshed');
        
        try {
          // Save new token to user document if logged in
          final user = _auth.currentUser;
          if (user != null) {
            await _firestore.collection('users').doc(user.uid).update({
              'fcmTokens': FieldValue.arrayUnion([newToken]),
              'lastTokenUpdate': Timestamp.now(),
            });
          }
          
          // Save token to shared preferences
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('fcm_token', newToken);
        } catch (e) {
          _logger.e('Error handling token refresh: $e');
          // Token refresh handling can fail silently
        }
      });
      
      // Handle background messages
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      
      // Handle messages when app is in foreground
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
      
      // Handle when user taps on notification to open app
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationOpen);
    } catch (e) {
      _logger.e('Error configuring FCM: $e');
      rethrow; // Propagate to the main try-catch in initialize
    }
  }
  
  // Initialize local notifications
  static Future<void> _initializeLocalNotifications() async {
    try {
      const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      final InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      
      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
      
      // Create Android notification channel
      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(
              const AndroidNotificationChannel(
                _channelId,
                _channelName,
                description: _channelDesc,
                importance: Importance.high,
              ),
            );
      }
    } catch (e) {
      _logger.e('Error initializing local notifications: $e');
    }
  }
  
  // Background message handler
  static Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
    // Save message to shared preferences to handle it when app opens
    final prefs = await SharedPreferences.getInstance();
    final pendingMessages = prefs.getStringList('pending_messages') ?? [];
    pendingMessages.add(jsonEncode(message.data));
    await prefs.setStringList('pending_messages', pendingMessages);
    
    // Show local notification for the message
    await showNotification(
      title: message.notification?.title ?? 'New Notification',
      body: message.notification?.body ?? '',
      payload: message.data,
    );
  }
  
  // Foreground message handler
  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    _logger.i('Received foreground message: ${message.messageId}');
    
    // Show local notification for the message
    await showNotification(
      title: message.notification?.title ?? 'New Notification',
      body: message.notification?.body ?? '',
      payload: message.data,
    );
  }
  
  // Handle notification tap
  static void _handleNotificationOpen(RemoteMessage message) {
    _logger.i('Notification opened: ${message.messageId}');
    
    // Process the notification data here
    _processNotificationData(message.data);
  }
  
  // Process notification data
  static void _processNotificationData(Map<String, dynamic> data) {
    try {
      final type = data['type'];
      
      if (type == 'geofence_entry') {
        // Handle geofence entry notification
        _logger.i('Processing geofence entry notification');
      } else if (type == 'geofence_exit') {
        // Handle geofence exit notification
        _logger.i('Processing geofence exit notification');
      } else {
        // Handle other notification types
        _logger.i('Processing notification of type: $type');
      }
    } catch (e) {
      _logger.e('Error processing notification data: $e');
    }
  }
  
  // Handle local notification tap
  static void _onNotificationTap(NotificationResponse response) {
    try {
      _logger.i('Local notification tapped: ${response.id}');
      
      if (response.payload != null) {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>;
        _processNotificationData(data);
      }
    } catch (e) {
      _logger.e('Error handling notification tap: $e');
    }
  }
  
  // Show a notification
  static Future<void> showNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    try {
      final androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
        ticker: 'geofence_ticker',
        icon: '@mipmap/ic_launcher',
      );
      
      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );
      
      final details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );
      
      // Increment notification ID to ensure uniqueness
      _notificationId++;
      
      await _localNotifications.show(
        _notificationId,
      title,
      body,
        details,
        payload: payload != null ? jsonEncode(payload) : null,
      );
      
      _logger.i('Showed notification: $title');
    } catch (e) {
      _logger.e('Error showing notification: $e');
    }
  }
  
  // Show a notification with positional parameters (backward compatibility)
  static Future<void> displayNotification(
    String title,
    String body, {
    Map<String, dynamic>? payload,
  }) async {
    return await showNotification(
      title: title,
      body: body,
      payload: payload,
    );
  }
  
  // Instance methods for geofence notifications
  Future<void> sendNotification({
    required String title,
    required String body,
    Map<String, dynamic>? payload,
  }) async {
    await NotificationService.showNotification(
      title: title,
      body: body,
      payload: payload,
    );
  }
  
  // Send geofence entry notification
  Future<void> sendGeofenceEntryNotification({
    required String userId,
    required String userName,
    required String geofenceId,
    required String geofenceName,
  }) async {
    await sendNotification(
      title: 'Entered $geofenceName',
      body: 'You have entered the $geofenceName geofence area',
      payload: {
        'type': 'geofence_entry',
        'geofenceId': geofenceId,
        'userId': userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );
  }
  
  // Send geofence exit notification
  Future<void> sendGeofenceExitNotification({
    required String userId,
    required String userName,
    required String geofenceId,
    required String geofenceName,
    Duration? duration,
  }) async {
    final String durationText = duration != null 
      ? 'You spent ${_formatDuration(duration)} in this area.' 
      : '';
      
    await sendNotification(
      title: 'Exited $geofenceName',
      body: 'You have left the $geofenceName geofence area. $durationText',
      payload: {
        'type': 'geofence_exit',
        'geofenceId': geofenceId,
        'userId': userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch.toString(),
        'duration': duration?.inSeconds.toString(),
      },
    );
  }
  
  // Format duration for notification
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    
    if (duration.inDays > 0) {
      return '${duration.inDays}d ${twoDigits(duration.inHours.remainder(24))}h';
    } else if (duration.inHours > 0) {
      return '${duration.inHours}h ${twoDigits(duration.inMinutes.remainder(60))}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${twoDigits(duration.inSeconds.remainder(60))}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }
  
  // Send notification to a specific user
  static Future<void> sendNotificationToUser({
    required String userId,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Get user document
      final userDoc = await _firestore.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        _logger.w('User $userId not found');
        return;
      }
      
      final userData = userDoc.data()!;
      final fcmTokens = (userData['fcmTokens'] as List<dynamic>?) ?? [];
      
      if (fcmTokens.isEmpty) {
        _logger.w('No FCM tokens found for user $userId');
        return;
      }
      
      // Prepare notification message
      final message = {
        'notification': {
          'title': title,
          'body': body,
        },
        'data': data ?? {},
        'tokens': fcmTokens,
      };
      
      // Add to cloud function queue for sending
      await _firestore.collection('notification_queue').add({
        'message': message,
        'userId': userId,
        'createdAt': Timestamp.now(),
        'status': 'pending',
      });
      
      _logger.i('Queued notification to user $userId: $title');
    } catch (e) {
      _logger.e('Error sending notification to user: $e');
    }
  }
  
  // Send notification to all admins
  static Future<void> sendNotificationToAdmins({
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) async {
    try {
      // Get all admin users
      final adminSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();
      
      // Send notification to each admin
      for (final adminDoc in adminSnapshot.docs) {
        await sendNotificationToUser(
          userId: adminDoc.id,
          title: title,
          body: body,
          data: data,
        );
      }
      
      _logger.i('Sent notification to all admins: $title');
    } catch (e) {
      _logger.e('Error sending notification to admins: $e');
    }
  }
  
  // Process any pending notifications
  static Future<void> processPendingNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingMessages = prefs.getStringList('pending_messages') ?? [];
      
      if (pendingMessages.isNotEmpty) {
        _logger.i('Processing ${pendingMessages.length} pending notifications');
        
        for (final messageJson in pendingMessages) {
          final messageData = jsonDecode(messageJson) as Map<String, dynamic>;
          _processNotificationData(messageData);
        }
        
        // Clear pending messages
        await prefs.remove('pending_messages');
      }
    } catch (e) {
      _logger.e('Error processing pending notifications: $e');
    }
  }
}
