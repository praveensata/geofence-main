import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logger/logger.dart';
import 'dart:async';
import 'services/geofence_service.dart';
import 'services/notification_service.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/advanced_geofencing_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/admin_dashboard.dart';
import 'screens/dashboard_screen.dart';
import 'screens/attendance_history_screen.dart';
import 'setup_admin.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'services/api_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';

final Logger logger = Logger();
// Global flag to track if initialization was successful
bool isAppInitialized = false;

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Run the app with error handling
  runApp(SafeModeApp());
}

class SafeModeApp extends StatefulWidget {
  @override
  _SafeModeAppState createState() => _SafeModeAppState();
}

class _SafeModeAppState extends State<SafeModeApp> {
  // Initialization state
  bool _isInitializing = true;
  bool _firebaseInitialized = false;
  bool _notificationsInitialized = false;
  bool _geofenceInitialized = false;
  String? _initError;
  final List<String> _initWarnings = [];

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  // Initialize app services with proper error handling
  Future<void> _initializeApp() async {
    try {
      logger.i('Starting app initialization');
      
      // Initialize Firebase with error handling
      try {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
        _firebaseInitialized = true;
        logger.i('Firebase initialized successfully');
      } catch (e) {
        logger.e('Failed to initialize Firebase: $e');
        _initWarnings.add('Firebase initialization failed. Some features may not work.');
      }

      // Only proceed with other services if Firebase is working
      if (_firebaseInitialized) {
        // Initialize notification service
        try {
  await NotificationService.initialize();
          _notificationsInitialized = true;
          logger.i('Notification service initialized successfully');
        } catch (e) {
          logger.e('Failed to initialize notification service: $e');
          _initWarnings.add('Notifications may not work properly.');
        }

        // Initialize geofence service
        try {
          await GeofenceService.instance.initialize();
          _geofenceInitialized = true;
          logger.i('Geofence service initialized successfully');
        } catch (e) {
          logger.e('Failed to initialize geofence service: $e');
          _initWarnings.add('Geofencing features may not work properly.');
        }
      }

      // App can start even with some services failing
      logger.i('App initialization completed with status: '
          'Firebase: $_firebaseInitialized, '
          'Notifications: $_notificationsInitialized, '
          'Geofence: $_geofenceInitialized');
      
      // Set global flag
      isAppInitialized = _firebaseInitialized;
      
    } catch (e) {
      logger.e('Unexpected error during app initialization: $e');
      _initError = 'Failed to start the app. Please try again later.';
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while initializing
    if (_isInitializing) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 24),
                Text('Starting app...')
              ],
            ),
          ),
        ),
      );
    }

    // If we have a critical error, show error screen
    if (_initError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: ErrorScreen(
          error: _initError!,
        ),
      );
    }

    // If Firebase is not working, show a minimal app with error message
    if (!_firebaseInitialized) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 48),
                SizedBox(height: 16),
                Text(
                  'Unable to connect to services',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'The app requires connectivity to Firebase services. Please check your internet connection and try again.',
                    textAlign: TextAlign.center,
                  ),
                ),
                SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => _retryInitialization(),
                  child: Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Main app with routes
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Geofence App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: _buildHomeWithWarnings(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/attendance': (context) => const AdvancedGeofencingScreen(),
        '/admin': (context) => AdminDashboard(),
        '/dashboard': (context) => const DashboardScreen(),
        '/profile': (context) => const ProfileScreen(),
        '/advanced_geofencing': (context) => const AdvancedGeofencingScreen(),
        '/setup_admin': (context) => SetupAdminScreen(),
        '/admin_fix': (context) => AdminSetupFixScreen(),
        '/attendance_history': (context) => AttendanceHistoryScreen(userId: FirebaseAuth.instance.currentUser?.uid),
      },
    );
  }

  Widget _buildHomeWithWarnings() {
    // Start with main app content (login screen)
    Widget content = LoginScreen();

    // If we have warnings, wrap with a banner
    if (_initWarnings.isNotEmpty) {
      return Scaffold(
        body: Column(
          children: [
            _buildWarningBanner(),
            Expanded(child: content),
          ],
        ),
      );
    }

    return content;
  }

  Widget _buildWarningBanner() {
    return Container(
      width: double.infinity,
      color: Colors.amber[100],
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.amber[800]),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Some features may be limited. Tap for details.',
                style: TextStyle(color: Colors.amber[900]),
              ),
            ),
            IconButton(
              icon: Icon(Icons.info_outline, color: Colors.amber[800]),
              onPressed: () => _showWarningsDialog(),
            ),
          ],
        ),
      ),
    );
  }

  void _showWarningsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('App Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The following services have issues:'),
            SizedBox(height: 8),
            ..._initWarnings.map((warning) => Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
                  Expanded(child: Text(warning)),
                ],
              ),
            )),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _retryInitialization();
            },
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }

  void _retryInitialization() {
    if (mounted) {
      setState(() {
        _isInitializing = true;
        _firebaseInitialized = false;
        _notificationsInitialized = false;
        _geofenceInitialized = false;
        _initError = null;
        _initWarnings.clear();
      });
    }
    
    _initializeApp();
  }
}

class ErrorScreen extends StatelessWidget {
  final String error;
  final bool firebaseInitialized;
  final bool notificationsInitialized;
  final bool geofenceInitialized;
  
  const ErrorScreen({
    Key? key,
    required this.error,
    this.firebaseInitialized = false,
    this.notificationsInitialized = false,
    this.geofenceInitialized = false,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    // Wrap in try-catch to prevent crashes in the error screen itself
    try {
      return Scaffold(
        appBar: AppBar(
          title: const Text('App Initialization Error'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The app encountered problems during initialization:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                _buildStatusItem('Firebase', firebaseInitialized),
                _buildStatusItem('Notifications', notificationsInitialized),
                _buildStatusItem('Geofence Service', geofenceInitialized),
                const SizedBox(height: 20),
                Text(
                  error,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Please check your internet connection and try again. If the problem persists, contact support.',
                  style: TextStyle(fontSize: 16),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      SystemNavigator.pop();
                    },
                    child: const Text('Close App'),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context, 
                        MaterialPageRoute(builder: (_) => const LoginScreen())
                      );
                    },
                    child: const Text('Continue Anyway'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      // If even the error screen crashes, show an absolute minimal screen
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 64),
              const SizedBox(height: 16),
              const Text('Error during startup'),
              const SizedBox(height: 16),
              Text('$error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => SystemNavigator.pop(),
                child: const Text('Close App'),
              ),
            ],
          ),
        ),
      );
    }
  }
  
  Widget _buildStatusItem(String serviceName, bool isInitialized) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(
            isInitialized ? Icons.check_circle : Icons.error,
            color: isInitialized ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 10),
          Text(
            '$serviceName: ${isInitialized ? 'Initialized' : 'Failed'}',
            style: TextStyle(
              fontSize: 16,
              color: isInitialized ? Colors.green : Colors.red,
            ),
          ),
        ],
      ),
    );
  }
}

// Helper widget for service status items
class StatusItem extends StatelessWidget {
  final String name;
  final bool isInitialized;
  
  const StatusItem({Key? key, required this.name, required this.isInitialized}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            isInitialized ? Icons.check_circle : Icons.error_outline,
            color: isInitialized ? Colors.green : Colors.red,
          ),
          SizedBox(width: 8),
          Text(name),
          Spacer(),
          Text(
            isInitialized ? 'Ready' : 'Failed',
            style: TextStyle(
              color: isInitialized ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _setUserData(String userId) async {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final Logger logger = Logger();

  try {
    // Check if the document exists
    DocumentSnapshot userSnapshot =
        await firestore.collection('users').doc(userId).get();
    if (!userSnapshot.exists) {
      // Set initial user data
      await firestore.collection('users').doc(userId).set({
        'customUserId': 'user_custom_id_$userId', // Example custom user ID
        'managerEmail':
            'potti2255@gmail.com', // Your email address as manager email
        // Add other user fields if needed
      });
      logger.i('User data set for userId: $userId');
    } else {
      // Ensure managerEmail is set even if the document exists
      Map<String, dynamic> data = userSnapshot.data() as Map<String, dynamic>;
      if (!data.containsKey('managerEmail')) {
        await firestore.collection('users').doc(userId).update({
          'managerEmail':
              'potti2255@gmail.com', // Your email address as manager email
        });
        logger.i('managerEmail added for userId: $userId');
      }
    }
  } catch (e) {
    logger.e('Error setting user data: $e');
  }
}

void onEnterGeofence() {
  try {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    logger.i('Entered geofence');
      NotificationService.displayNotification(
        'Geofence Alert', 'You have entered the geofence area.');
    ApiService().logAttendance(user.uid, DateTime.now(), true);
    }
  } catch (e) {
    logger.e('Error handling geofence entry: $e');
  }
}

Future<void> onExitGeofence() async {
  try {
  final user = FirebaseAuth.instance.currentUser;
  if (user != null) {
    logger.i('Exited geofence');
      NotificationService.displayNotification(
        'Geofence Alert', 'You have exited the geofence area.');
    await ApiService().logAttendance(user.uid, DateTime.now(), false);

    await FirebaseAuth.instance.signOut().then((_) {
      logger.i('User logged out automatically');
    });
  }
  } catch (e) {
    logger.e('Error handling geofence exit: $e');
  }
}

class AdminSetupFixScreen extends StatefulWidget {
  @override
  _AdminSetupFixScreenState createState() => _AdminSetupFixScreenState();
}

class _AdminSetupFixScreenState extends State<AdminSetupFixScreen> {
  final Logger logger = Logger();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Hard-coded admin credentials
  final String _adminEmail = 'adminlbce@gmail.com';
  final String _adminPassword = 'admin@123';
  final String _adminId = 'adminlbce@gmail.com';
  
  String _message = 'Press the button to create/fix admin account';
  bool _isLoading = false;
  bool _success = false;
  User? _currentUser;
  
  @override
  void initState() {
    super.initState();
    _checkCurrentUser();
  }
  
  void _checkCurrentUser() {
    setState(() {
      _currentUser = _auth.currentUser;
    });
  }

  Future<void> _createAdminUser() async {
    setState(() {
      _isLoading = true;
      _message = 'Creating admin account...';
    });
    
    try {
      // 1. Try to sign out first (clean state)
      await _auth.signOut();
      
      // 2. Try to create admin user
      UserCredential credential;
      try {
        logger.i('Attempting to create admin user with email: $_adminEmail');
        credential = await _auth.createUserWithEmailAndPassword(
          email: _adminEmail,
          password: _adminPassword,
        );
        logger.i('Created new admin user: ${credential.user?.uid}');
      } catch (e) {
        // If user already exists, sign in
        if (e is FirebaseAuthException && e.code == 'email-already-in-use') {
          logger.i('Admin email already exists, signing in instead');
          credential = await _auth.signInWithEmailAndPassword(
            email: _adminEmail,
            password: _adminPassword,
          );
          logger.i('Signed in as existing admin: ${credential.user?.uid}');
        } else {
          throw Exception('Failed to create/login admin: $e');
        }
      }
      
      // 3. Set admin role in Firestore
      if (credential.user != null) {
        logger.i('Setting admin role in Firestore for user: ${credential.user!.uid}');
        
        await _firestore.collection('users').doc(credential.user!.uid).set({
          'email': _adminEmail,
          'role': 'admin',
          'name': 'Administrator',
          'customUserId': 'ADMIN-1000',
          'lastUpdated': FieldValue.serverTimestamp(),
          'adminCredentials': {
            'username': _adminId,
            'password': _adminPassword
          }
        }, SetOptions(merge: true));
        
        // 4. Verify the document was created
        final doc = await _firestore.collection('users').doc(credential.user!.uid).get();
        if (!doc.exists) {
          throw Exception('Admin document was not created in Firestore');
        }
        
        final data = doc.data();
        if (data == null || data['role'] != 'admin') {
          throw Exception('Admin document exists but role is not "admin"');
        }
        
        // 5. Get current user after operations
        _checkCurrentUser();
        
        setState(() {
          _isLoading = false;
          _success = true;
          _message = 'Admin account created/fixed successfully!\n\n'
              'Email: $_adminEmail\n'
              'Password: $_adminPassword\n'
              'Admin ID: $_adminId\n\n'
              'You can now go back and login with these credentials.';
        });
      } else {
        throw Exception('Failed to get user after auth operation');
      }
    } catch (e) {
      logger.e('Error creating admin account: $e');
      setState(() {
        _isLoading = false;
        _success = false;
        _message = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Admin Setup Fix'),
        backgroundColor: Colors.red,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              color: Colors.amber.shade50,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current Authentication State:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('Signed in: ${_currentUser != null ? 'YES' : 'NO'}'),
                    if (_currentUser != null) ...[
                      Text('User ID: ${_currentUser!.uid}'),
                      Text('Email: ${_currentUser!.email}'),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            Card(
              elevation: 4,
              color: Colors.blue.shade50,
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Credentials to Create:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('Email: $_adminEmail'),
                    Text('Password: $_adminPassword'),
                    Text('Admin ID: $_adminId'),
                    SizedBox(height: 16),
                    Text(
                      'These credentials will work for both regular login and admin login.',
                      style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 24),
            _isLoading
                ? Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _createAdminUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: Text('CREATE/FIX ADMIN ACCOUNT', style: TextStyle(fontSize: 16)),
                  ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _success ? Colors.green.shade100 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _success ? Colors.green : Colors.grey,
                ),
              ),
              child: Text(_message),
            ),
            SizedBox(height: 24),
            if (_success)
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacementNamed(context, '/login');
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                child: Text('Go to Login Screen'),
              ),
          ],
        ),
      ),
    );
  }
}
