import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'dart:io';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final User? user = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();
  final logger = Logger();

  String? _name;
  String? _email;
  String? _phoneNumber;
  String? _customUserId;
  File? _profileImage;
  bool _isLoading = true;

  final picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    if (user == null) {
      logger.e('User is null, cannot load profile');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
      });

      logger.i('Loading profile for user ID: ${user!.uid}');
      final userData = await firestore.collection('users').doc(user!.uid).get();
      
      if (userData.exists) {
        final data = userData.data();
        setState(() {
          _name = data?['name'] ?? '';
          _email = data?['email'] ?? user?.email ?? '';
          _phoneNumber = data?['phoneNumber'] ?? '';
          _customUserId = data?['customUserId'] ?? '';
        });
        logger.i('Profile data loaded: $_name, $_email, $_phoneNumber, customUserId: $_customUserId');
      } else {
        setState(() {
          _email = user?.email ?? '';
          _name = user?.displayName ?? '';
        });
        logger.w('No profile document found, using auth data: $_email, $_name');
      }
    } catch (e) {
      logger.e('Error loading profile: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading profile: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _pickImage() async {
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
        });
        logger.i('Image picked: ${pickedFile.path}');
      }
    } catch (e) {
      logger.e('Error picking image: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _saveProfile() async {
    if (user == null) {
      logger.e('User is null, cannot save profile');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You must be logged in to save profile')),
      );
      return;
    }

    if (_formKey.currentState!.validate()) {
      _formKey.currentState!.save();

      try {
        setState(() {
          _isLoading = true;
        });
        
        logger.i('Saving profile for user ID: ${user!.uid}');
        logger.i('Profile data to save: name=$_name, email=$_email, phone=$_phoneNumber');
        
        // Keep the customUserId if already exists and matches format
        Map<String, dynamic> userData = {
          'name': _name,
          'email': _email,
          'phoneNumber': _phoneNumber,
          'lastUpdated': FieldValue.serverTimestamp(),
        };
        
        // If we have a custom user ID from previous load, check if it matches format
        if (_customUserId != null && _customUserId!.isNotEmpty) {
          if (_customUserId!.startsWith('CSE') && _customUserId!.length == 8) {
            // If it already follows our format, keep it
            userData['customUserId'] = _customUserId;
          } else {
            // If not, generate a new one in CSE format
            userData['customUserId'] = await _generateNewEmployeeId();
          }
        } else {
          // No ID exists, generate a new one
          userData['customUserId'] = await _generateNewEmployeeId();
        }

        // Save data to Firestore
        await firestore.collection('users').doc(user!.uid).set(
              userData,
              SetOptions(merge: true),
            );

        logger.i('Profile updated successfully with employee ID: ${userData['customUserId']}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Profile updated with Employee ID: ${userData['customUserId']}')),
        );
      } catch (e) {
        logger.e('Error updating profile: $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating profile: $e')),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Generate a new employee ID in CSE12345 format
  Future<String> _generateNewEmployeeId() async {
    try {
      // Get the count of existing users to create a sequential ID
      final userCount = await firestore.collection('users').count().get();
      
      // Generate a 5-digit number, padded with leading zeros if needed
      int idNumber = 10000 + (userCount.count ?? 0);
      
      // If we somehow exceed 99999, wrap around
      if (idNumber > 99999) {
        idNumber = idNumber % 90000 + 10000;
      }
      
      String newId = 'CSE$idNumber';
      logger.i('Generated new employee ID: $newId');
      return newId;
    } catch (e) {
      logger.e('Error generating ID: $e');
      // Fallback to a random 5-digit number if counting fails
      int randomNumber = 10000 + DateTime.now().millisecondsSinceEpoch % 90000;
      return 'CSE$randomNumber';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _pickImage,
                        child: CircleAvatar(
                          radius: 50,
                          backgroundImage: _profileImage != null
                              ? FileImage(_profileImage!)
                              : (user?.photoURL != null
                                      ? NetworkImage(user!.photoURL!)
                                      : const AssetImage('assets/default_avatar.png'))
                                  as ImageProvider,
                          child: _profileImage == null && user?.photoURL == null
                              ? const Icon(Icons.camera_alt, size: 50)
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      initialValue: _name,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your name';
                        }
                        return null;
                      },
                      onSaved: (value) {
                        _name = value;
                      },
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      initialValue: _email,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your email';
                        }
                        if (!RegExp(r'^\S+@\S+\.\S+$').hasMatch(value)) {
                          return 'Please enter a valid email address';
                        }
                        return null;
                      },
                      onSaved: (value) {
                        _email = value;
                      },
                    ),
                    const SizedBox(height: 15),
                    TextFormField(
                      initialValue: _phoneNumber,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter your phone number';
                        }
                        return null;
                      },
                      onSaved: (value) {
                        _phoneNumber = value;
                      },
                    ),
                    if (_customUserId != null && _customUserId!.isNotEmpty) ...[
                      const SizedBox(height: 15),
                      Card(
                        color: _customUserId!.startsWith('CSE') && _customUserId!.length == 8
                            ? Colors.green.shade50
                            : Colors.amber.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Employee ID:',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: _customUserId!.startsWith('CSE') 
                                          ? Colors.green.shade100 
                                          : Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      _customUserId!,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: _customUserId!.startsWith('CSE') 
                                            ? Colors.green.shade800 
                                            : Colors.amber.shade800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (!(_customUserId!.startsWith('CSE') && _customUserId!.length == 8)) ...[
                                const SizedBox(height: 8),
                                const Text(
                                  'Your ID is using the old format. Click below to update to the new format (CSE12345).',
                                  style: TextStyle(fontSize: 12),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _updateToNewIdFormat,
                                    icon: const Icon(Icons.update, size: 16),
                                    label: const Text('Update ID Format'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.amber.shade600,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 25),
                    Center(
                      child: ElevatedButton.icon(
                        onPressed: _saveProfile,
                        icon: const Icon(Icons.save),
                        label: const Text('Save Profile'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 30,
                            vertical: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
  
  Future<void> _updateToNewIdFormat() async {
    try {
      setState(() {
        _isLoading = true;
      });
      
      String newId = await _generateNewEmployeeId();
      
      await firestore.collection('users').doc(user!.uid).update({
        'customUserId': newId,
      });
      
      setState(() {
        _customUserId = newId;
        _isLoading = false;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Employee ID updated to new format: $newId')),
      );
      
      logger.i('Employee ID updated to: $newId');
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      
      logger.e('Error updating employee ID: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating ID: $e')),
      );
    }
  }
}
