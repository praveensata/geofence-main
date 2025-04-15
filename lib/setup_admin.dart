import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:logger/logger.dart';

class SetupAdminScreen extends StatefulWidget {
  @override
  _SetupAdminScreenState createState() => _SetupAdminScreenState();
}

class _SetupAdminScreenState extends State<SetupAdminScreen> {
  final Logger logger = Logger();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _adminIdController = TextEditingController(text: 'adminlbce@gmail.com');
  final _adminPasswordController = TextEditingController(text: 'admin@123');
  
  bool _isLoading = false;
  String _message = '';
  bool _success = false;
  
  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _adminIdController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }
  
  Future<void> _setupAdmin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final adminId = _adminIdController.text.trim();
    final adminPassword = _adminPasswordController.text;
    
    if (email.isEmpty || password.isEmpty) {
      setState(() {
        _message = 'Email and password are required';
        _success = false;
      });
      return;
    }
    
    if (password.length < 6) {
      setState(() {
        _message = 'Password must be at least 6 characters';
        _success = false;
      });
      return;
    }
    
    if (adminId.isEmpty || adminPassword.isEmpty) {
      setState(() {
        _message = 'Admin ID and password are required';
        _success = false;
      });
      return;
    }
    
    if (adminPassword.length < 6) {
      setState(() {
        _message = 'Admin password must be at least 6 characters';
        _success = false;
      });
      return;
    }
    
    setState(() {
      _isLoading = true;
      _message = '';
    });
    
    try {
      // First check if an admin user already exists
      final existingAdmins = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();
      
      if (existingAdmins.docs.isNotEmpty) {
        setState(() {
          _isLoading = false;
          _message = 'An admin user already exists. You cannot create another one.';
          _success = false;
        });
        return;
      }
      
      // Create new admin user in Firebase Auth
      UserCredential userCredential;
      try {
        userCredential = await _auth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );
      } catch (e) {
        // Check if user already exists
        if (e is FirebaseAuthException && e.code == 'email-already-in-use') {
          // Try to sign in instead
          userCredential = await _auth.signInWithEmailAndPassword(
            email: email,
            password: password,
          );
        } else {
          throw e;
        }
      }
      
      // Make sure we're signed in
      if (_auth.currentUser == null) {
        throw Exception('Failed to sign in or create user');
      }
      
      // Set admin role in Firestore
      await _firestore.collection('users').doc(_auth.currentUser!.uid).set({
        'email': email,
        'role': 'admin',
        'name': 'Admin User',
        'customUserId': 'ADMIN-1000',
        'lastUpdated': FieldValue.serverTimestamp(),
        'adminCredentials': {
          'username': adminId,
          'password': adminPassword
        }
      }, SetOptions(merge: true));

      logger.i('Admin user set up with ID: $adminId');
      
      // Double-check that our user has the admin role
      final userDoc = await _firestore.collection('users').doc(_auth.currentUser!.uid).get();
      if (!userDoc.exists || userDoc.data()?['role'] != 'admin') {
        throw Exception('Failed to set admin role');
      }
      
      setState(() {
        _isLoading = false;
        _message = 'Admin user setup complete!\n\nEmail: $email\nAdmin ID: $adminId\nPassword: $adminPassword\n\nYou can now log in with either your email or the Admin ID.';
        _success = true;
      });
      
    } catch (e) {
      setState(() {
        _isLoading = false;
        _message = 'Error setting up admin: $e';
        _success = false;
      });
      logger.e('Error setting up admin: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Setup Admin User'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Create Admin Account',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 20),
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Firebase Authentication',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue.shade800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'These credentials will be used for Firebase Authentication',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Admin Email',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.email),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        decoration: InputDecoration(
                          labelText: 'Admin Password',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock),
                        ),
                        obscureText: true,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),
              Card(
                elevation: 4,
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Login Credentials',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.red.shade800,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'These credentials will be used for direct admin login',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: _adminIdController,
                        decoration: InputDecoration(
                          labelText: 'Admin ID',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.admin_panel_settings),
                          helperText: 'Default: adminlbce@gmail.com',
                        ),
                      ),
                      SizedBox(height: 16),
                      TextField(
                        controller: _adminPasswordController,
                        decoration: InputDecoration(
                          labelText: 'Admin Password',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.lock),
                          helperText: 'Default: admin@123',
                        ),
                        obscureText: true,
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 24),
              if (_isLoading)
                Center(child: CircularProgressIndicator())
              else
                ElevatedButton(
                  onPressed: _setupAdmin,
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Setup Admin User',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              SizedBox(height: 16),
              if (_message.isNotEmpty)
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _success ? Colors.green.shade100 : Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _message,
                    style: TextStyle(
                      color: _success ? Colors.green.shade800 : Colors.red.shade800,
                    ),
                  ),
                ),
              SizedBox(height: 24),
              Text(
                'Note: After setting up the admin user, you can use either the Firebase email/password or the Admin ID/password to log in as admin.',
                style: TextStyle(fontStyle: FontStyle.italic),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
} 