import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:logger/logger.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final logger = Logger();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isAdmin = false;
  bool _isLoading = false;
  bool _showDebugTools = false;

  // Default admin credentials
  final String _defaultAdminId = 'adminlbce@gmail.com';
  final String _defaultAdminPassword = 'admin@1234';
  final String _defaultAdminEmail = 'adminlbce@gmail.com';

  @override
  void initState() {
    super.initState();
    // Pre-populate fields in admin mode for easier testing
    if (_isAdmin) {
      _emailController.text = _defaultAdminId;
      _passwordController.text = _defaultAdminPassword;
    }
  }

  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please enter both ID/email and password')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // SIMPLE DIRECT ADMIN CREDENTIAL CHECK
      if (_isAdmin) {
        final adminId = _emailController.text.trim();
        final adminPassword = _passwordController.text.trim();
        
        logger.i('Admin login attempt with ID: $adminId and password: ${adminPassword.substring(0, 2)}***');
        
        // Simple direct check for default admin credentials - check both old and new password
        if (adminId == _defaultAdminId && 
            (adminPassword == _defaultAdminPassword || adminPassword == 'admin@123')) {
          logger.i('Default admin credentials matched, signing in as $_defaultAdminEmail');
          
          try {
            // Try to sign in with the admin email
            await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: _defaultAdminEmail,
              password: adminPassword,
            );
            
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/admin');
            }
            return;
          } catch (e) {
            logger.e('Error signing in with default admin: $e');
            
            // If admin doesn't exist in Auth or password wrong, create/update it
            if (e is FirebaseAuthException && 
                (e.code == 'user-not-found' || e.code == 'wrong-password')) {
              logger.i('Admin user not found or wrong password, creating/updating it now');
              try {
                await _setupAdminAccount();
                
                // Try signing in again after setup
                await FirebaseAuth.instance.signInWithEmailAndPassword(
                  email: _defaultAdminEmail,
                  password: _defaultAdminPassword,
                );
                
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/admin');
                }
                return;
              } catch (setupError) {
                logger.e('Error setting up admin account: $setupError');
                throw Exception('Could not set up admin account: $setupError');
              }
            } else {
              // Some other error with signing in
              logger.e('Error signing in as admin: $e');
              throw Exception('Firebase auth error: ${e.toString()}');
            }
          }
        } else {
          // Not using default credentials, check Firestore for custom credentials
          try {
            final adminQuery = await FirebaseFirestore.instance
                .collection('users')
                .where('role', isEqualTo: 'admin')
                .get();
                
            logger.i('Found ${adminQuery.docs.length} admin users in Firestore');
            
            if (adminQuery.docs.isEmpty) {
              // No admin users found, create one with default credentials
              logger.i('No admin users found, creating default admin');
              await _setupAdminAccount();
              
              // Try signing in with default credentials
              if (adminId == _defaultAdminId && adminPassword == _defaultAdminPassword) {
                await FirebaseAuth.instance.signInWithEmailAndPassword(
                  email: _defaultAdminEmail,
                  password: _defaultAdminPassword,
                );
                
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/admin');
                }
                return;
              } else {
                throw Exception('Invalid admin credentials');
              }
            }
            
            bool credentialsFound = false;
            String? adminEmail;
            String? storedPassword;
            
            for (var doc in adminQuery.docs) {
              final data = doc.data();
              
              // Check if this user has admin credentials stored
              if (data.containsKey('adminCredentials')) {
                final credentials = data['adminCredentials'] as Map<String, dynamic>?;
                if (credentials != null) {
                  final storedUsername = credentials['username'];
                  storedPassword = credentials['password'];
                  adminEmail = data['email'] as String?;
                  
                  logger.i('Checking against stored admin credentials for: $storedUsername');
                  
                  if (adminId == storedUsername && adminPassword == storedPassword) {
                    credentialsFound = true;
                    logger.i('Custom admin credentials matched for email: $adminEmail');
                    break;
                  }
                }
              }
            }
            
            if (credentialsFound && adminEmail != null && storedPassword != null) {
              try {
                await FirebaseAuth.instance.signInWithEmailAndPassword(
                  email: adminEmail,
                  password: storedPassword, // Using stored password from Firestore
                );
                
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/admin');
                }
                return;
              } catch (signInError) {
                logger.e('Error signing in with custom admin: $signInError');
                
                if (signInError is FirebaseAuthException && 
                    (signInError.code == 'wrong-password' || signInError.code == 'user-not-found')) {
                  // Try resetting the admin account
                  await _setupAdminAccount();
                  
                  // Try to sign in with default admin
                  await FirebaseAuth.instance.signInWithEmailAndPassword(
                    email: _defaultAdminEmail,
                    password: _defaultAdminPassword,
                  );
                  
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, '/admin');
                  }
                  return;
                } else {
                  throw signInError;
                }
              }
            } else {
              throw Exception('Invalid admin credentials');
            }
          } catch (e) {
            logger.e('Admin login error: $e');
            throw Exception('Admin login failed: ${e.toString()}');
          }
        }
      } else {
        // Regular user login with more error details
        try {
          UserCredential userCredential = await FirebaseAuth.instance.signInWithEmailAndPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text.trim(),
          );
          
          // Check if user is admin in Firestore
          final userData = await FirebaseFirestore.instance
              .collection('users')
              .doc(userCredential.user!.uid)
              .get();
              
          final bool isAdmin = userData.exists && userData.data()?['role'] == 'admin';
              
          if (isAdmin) {
            logger.i('Admin user signed in via Firebase: ${userCredential.user?.email}');
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/admin');
            }
          } else {
            logger.i('Regular user signed in: ${userCredential.user?.email}');
            if (mounted) {
              Navigator.pushReplacementNamed(context, '/attendance');
            }
          }
        } catch (e) {
          logger.e('Regular login error: $e');
          throw e;
        }
      }
    } catch (e) {
      logger.e('Error during login: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Login failed: ${e.toString().replaceAll('Exception: ', '')}',
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
            duration: Duration(seconds: 5),
            action: _showDebugTools ? SnackBarAction(
              label: 'Fix Admin',
              onPressed: () => _setupAdminAccount(),
            ) : null,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Function to set up admin account in Firebase
  Future<void> _setupAdminAccount() async {
    try {
      logger.i('Creating or updating admin user in Firebase');
      
      // Create the admin in Firebase Auth
      UserCredential credential;
      try {
        // Delete any existing admin user first if possible
        try {
          final user = FirebaseAuth.instance.currentUser;
          if (user != null && user.email == _defaultAdminEmail) {
            await user.delete();
            logger.i('Deleted existing admin user');
          }
        } catch (e) {
          logger.e('Error trying to delete existing user: $e');
          // Continue with the process
        }
      
        // Try to create
        credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: _defaultAdminEmail,
          password: _defaultAdminPassword,
        );
        logger.i('Created new admin user in Firebase Auth');
      } catch (e) {
        // If already exists, sign in
        if (e is FirebaseAuthException && e.code == 'email-already-in-use') {
          try {
            credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: _defaultAdminEmail,
              password: _defaultAdminPassword,
            );
            logger.i('Signed in to existing admin account');
          } catch (signInError) {
            // If password is wrong, we need to reset it
            if (signInError is FirebaseAuthException && signInError.code == 'wrong-password') {
              logger.w('Admin password incorrect, attempting reset via email');
              
              // Send password reset email
              await FirebaseAuth.instance.sendPasswordResetEmail(email: _defaultAdminEmail);
              
              throw Exception('Admin password needs to be reset. Check email: $_defaultAdminEmail');
            } else {
              throw signInError;
            }
          }
        } else {
          throw e;
        }
      }
      
      // Get all admin users and update or create as needed
      final adminQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();
          
      // If we have admin users, update them all to have the correct credentials
      if (adminQuery.docs.isNotEmpty) {
        for (var doc in adminQuery.docs) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(doc.id)
              .update({
                'adminCredentials': {
                  'username': _defaultAdminId,
                  'password': _defaultAdminPassword
                },
                'lastUpdated': FieldValue.serverTimestamp(),
              });
        }
        
        logger.i('Updated all existing admin users with new credentials');
      }
      
      // Set admin role in Firestore for the current credential
      await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .set({
        'email': _defaultAdminEmail,
        'role': 'admin',
        'name': 'Admin User',
        'customUserId': 'ADMIN-1000',
        'lastUpdated': FieldValue.serverTimestamp(),
        'adminCredentials': {
          'username': _defaultAdminId,
          'password': _defaultAdminPassword
        }
      }, SetOptions(merge: true));
      
      logger.i('Admin user created/updated in Firestore');
      
      // Verify the document was created/updated
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(credential.user!.uid)
          .get();
          
      if (!doc.exists) {
        logger.e('Admin document does not exist after setup!');
        throw Exception('Failed to create admin document');
      }
      
      logger.i('Admin setup successful');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Admin account created/updated successfully'),
            backgroundColor: Colors.green,
          )
        );
      }
    } catch (e) {
      logger.e('Error setting up admin: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error setting up admin: $e'),
            backgroundColor: Colors.red,
          )
        );
      }
      throw e;
    }
  }

  void _toggleAdminMode() {
    setState(() {
      _isAdmin = !_isAdmin;
      
      // Clear fields when switching modes
      _emailController.clear();
      _passwordController.clear();
      
      // Pre-fill admin credentials when in admin mode (for easier testing)
      if (_isAdmin) {
        _emailController.text = _defaultAdminId;
      }
    });
  }
  
  void _toggleDebugTools() {
    setState(() {
      _showDebugTools = !_showDebugTools;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.blue.shade400,
              Colors.purple.shade600,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.0),
                    ),
                    elevation: 10,
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _isAdmin ? 'Admin Login' : 'Welcome Back',
                            style:
                                Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      color: _isAdmin ? Colors.red.shade800 : Colors.black87,
                                      fontWeight: FontWeight.bold,
                                    ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: _isAdmin ? 'Admin ID' : 'Email',
                              prefixIcon: Icon(_isAdmin ? Icons.admin_panel_settings : Icons.email),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                            ),
                            keyboardType: _isAdmin ? TextInputType.text : TextInputType.emailAddress,
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: Icon(Icons.lock),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12.0),
                              ),
                            ),
                            obscureText: true,
                          ),
                          const SizedBox(height: 30),
                          _isLoading
                              ? CircularProgressIndicator()
                              : ElevatedButton(
                                  onPressed: _login,
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16.0,
                                      horizontal: 32.0,
                                    ),
                                    backgroundColor: _isAdmin ? Colors.red.shade700 : Colors.blue,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12.0),
                                    ),
                                  ),
                                  child: Text(
                                    _isAdmin ? 'Admin Login' : 'Login',
                                    style: TextStyle(fontSize: 16.0, color: Colors.white),
                                  ),
                                ),
                          const SizedBox(height: 20),
                          TextButton.icon(
                            onPressed: _toggleAdminMode,
                            icon: Icon(_isAdmin ? Icons.person : Icons.admin_panel_settings),
                            label: Text(
                              _isAdmin ? 'Switch to User Login' : 'Switch to Admin Login',
                              style: TextStyle(fontSize: 14.0),
                            ),
                          ),
                          
                          // Debug tools section
                          if (_showDebugTools) ...[
                            Divider(height: 30),
                            Text(
                              'Debug Tools',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade700
                              ),
                            ),
                            SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _setupAdminAccount,
                              icon: Icon(Icons.build),
                              label: Text('Create/Reset Admin Account'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'This will create or reset the admin account with\nID: $_defaultAdminId, Password: $_defaultAdminPassword',
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                            SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.pushNamed(context, '/admin_fix');
                              },
                              icon: Icon(Icons.admin_panel_settings),
                              label: Text('Go to Admin Fix Screen'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Use this if admin login is not working',
                              style: TextStyle(fontSize: 10, color: Colors.grey),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          
                          if (_isAdmin) ...[
                            SizedBox(height: 8),
                            Text(
                              'Default Admin ID: adminlbce@gmail.com\nDefault Password: admin@1234',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                                fontStyle: FontStyle.italic,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleDebugTools,
        child: Icon(_showDebugTools ? Icons.build_circle : Icons.build),
        backgroundColor: _showDebugTools ? Colors.orange : Colors.blue,
        mini: true,
      ),
    );
  }
}
