import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:logger/logger.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  DashboardScreenState createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen> {
  final logger = Logger();
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _user;
  List<Map<String, dynamic>> _attendanceLogs = [];
  bool _isLoading = true;
  
  // Profile data
  Map<String, dynamic>? _profileData;
  String _userName = 'User';
  String _userEmail = '';
  String _userPhone = '';
  String _employeeId = '';

  @override
  void initState() {
    super.initState();
    _user = _auth.currentUser;
    _loadData();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // This will ensure profile data is refreshed when returning from profile screen
    _loadProfileData();
  }

  Future<void> _loadData() async {
    if (_user == null) {
      logger.e("User is null");
      setState(() {
        _isLoading = false;
      });
      return;
    }

    await Future.wait([
      _fetchAttendanceLogs(),
      _loadProfileData(),
    ]);
    
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadProfileData() async {
    if (_user == null) return;
    
    try {
      logger.i('Loading profile data for user: ${_user!.uid}');
      final doc = await _firestore.collection('users').doc(_user!.uid).get();
      
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        
        setState(() {
          _profileData = data;
          _userName = data['name'] ?? _user?.displayName ?? 'User';
          _userEmail = data['email'] ?? _user?.email ?? '';
          _userPhone = data['phoneNumber'] ?? '';
          _employeeId = data['customUserId'] ?? '';
        });
        
        logger.i('Profile data loaded: $_userName, $_userEmail, $_userPhone, $_employeeId');
      } else {
        setState(() {
          _userName = _user?.displayName ?? 'User';
          _userEmail = _user?.email ?? '';
        });
        logger.w('No profile document found');
      }
    } catch (e) {
      logger.e('Error loading profile data: $e');
    }
  }

  Future<void> _fetchAttendanceLogs() async {
    if (_user == null) return;

    try {
      QuerySnapshot snapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: _user!.uid)
          .orderBy('timestamp', descending: true)
          .get();

      setState(() {
        _attendanceLogs = snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return {
            'date': (data['timestamp'] as Timestamp).toDate(),
            'status': data['isEntering'] ? 'Entered' : 'Exited',
          };
        }).toList();
      });

      logger.i('Fetched ${_attendanceLogs.length} attendance logs');
    } catch (e) {
      if (e.toString().contains('failed-precondition')) {
        logger.e('Index is still building. Please try again later.');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Index is still building. Please try again later.')),
        );
      } else {
        logger.e('Error fetching attendance logs: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching attendance logs: $e')),
        );
      }
    }
  }

  void _logout() async {
    await _auth.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }
  
  Future<void> _navigateToProfile() async {
    await Navigator.pushNamed(context, '/profile');
    // Refresh profile data when returning from profile screen
    _loadProfileData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildUserInfo(),
                      const SizedBox(height: 16),
                      _buildAttendanceHeader(),
                      const SizedBox(height: 10),
                      _buildAttendanceList(),
                      const SizedBox(height: 20),
                      _buildActions(),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Dashboard'),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loadData,
        ),
        IconButton(
          icon: const Icon(Icons.logout),
          onPressed: _logout,
        ),
      ],
    );
  }

  Widget _buildUserInfo() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundImage: 
                    _user?.photoURL != null 
                      ? NetworkImage(_user!.photoURL!) as ImageProvider
                      : const AssetImage('assets/default_avatar.png'),
                  radius: 40,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome, $_userName',
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _userEmail,
                        style: const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      if (_userPhone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Phone: $_userPhone',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (_employeeId.isNotEmpty) ...[
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Employee ID:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _employeeId,
                      style: TextStyle(
                        color: Colors.blue.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _navigateToProfile,
              icon: const Icon(Icons.edit),
              label: const Text('Edit Profile'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                minimumSize: const Size(double.infinity, 0),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceHeader() {
    return const Text(
      'Your Attendance Logs:',
      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildAttendanceList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('attendance')
          .where('userId', isEqualTo: _user?.uid)
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final attendanceRecords = snapshot.data!.docs;
        
        if (attendanceRecords.isEmpty) {
          return Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.history_outlined, size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text(
                      'No attendance records yet',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: attendanceRecords.length,
          itemBuilder: (context, index) {
            final record = attendanceRecords[index];
            final timestamp = (record['timestamp'] as Timestamp).toDate();
            final status = record['isEntering'] ? 'Entered' : 'Exited';

            return _buildAttendanceCard(timestamp, status);
          },
        );
      },
    );
  }

  Widget _buildAttendanceCard(DateTime timestamp, String status) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 4,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        leading: Icon(
          status == 'Entered' ? Icons.login : Icons.logout,
          color: status == 'Entered' ? Colors.green : Colors.red,
        ),
        title: Text(DateFormat('dd MMM yyyy, hh:mm a').format(timestamp)),
        subtitle: Text('Status: $status'),
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Actions',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              onPressed: () {
                Navigator.pushNamed(context, '/attendance');
              },
              icon: const Icon(Icons.location_on),
              label: const Text('Attendance & Geofencing'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: _navigateToProfile,
              icon: const Icon(Icons.person),
              label: const Text('View Profile'),
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
