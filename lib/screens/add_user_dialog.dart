import 'package:flutter/material.dart';
import 'package:logger/logger.dart';

class AddUserDialog extends StatefulWidget {
  final Function(Map<String, dynamic>) onAddUser;

  const AddUserDialog({super.key, required this.onAddUser});

  @override
  _AddUserDialogState createState() => _AddUserDialogState();
}

class _AddUserDialogState extends State<AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customUserIdController =
      TextEditingController(); // New controller for custom user ID
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _roleController = TextEditingController();
  final logger = Logger();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add User'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _customUserIdController,
              decoration: const InputDecoration(labelText: 'User ID'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a user ID';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter an email';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a password';
                }
                return null;
              },
            ),
            TextFormField(
              controller: _roleController,
              decoration: const InputDecoration(labelText: 'Role'),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter a role';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final userData = {
                'customUserId': _customUserIdController.text,
                'email': _emailController.text,
                'password': _passwordController.text,
                'role': _roleController.text,
              };
              widget.onAddUser(userData);
              Navigator.of(context).pop();
            }
          },
          child: const Text('Add'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
