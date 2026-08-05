import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'validators.dart';

class OfficerSignupScreen extends StatefulWidget {
  const OfficerSignupScreen({super.key});

  @override
  State<OfficerSignupScreen> createState() => _OfficerSignupScreenState();
}

class _OfficerSignupScreenState extends State<OfficerSignupScreen> {
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();
  bool isLoading = false;
  String? emailError;
  String? passwordError;

  final String baseUrl = "http://10.95.149.28:5000";

  Future<void> signupOfficer() async {
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage("Please fill all fields");
      return;
    }

    final emailValidationError = Validators.email(email);
    if (emailValidationError != null) {
      setState(() {
        emailError = emailValidationError;
      });
      _showMessage(emailValidationError);
      return;
    }

    final passwordValidationError = Validators.password(password);
    if (passwordValidationError != null) {
      setState(() {
        passwordError = passwordValidationError;
      });
      _showMessage(passwordValidationError);
      return;
    }

    if (password != confirmPassword) {
      _showMessage("Passwords do not match");
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/signup/officer"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "f_name": firstName,
          "l_name": lastName,
          "email": email,
          "password": password,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        _showMessage("Signup successful! Please login");
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        _showMessage(data['error'] ?? "Signup failed");
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage("Connection error: Could not reach server");
    }

    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.blueGrey),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.badge,
              size: 80,
              color: Colors.blueGrey,
            ),
            const SizedBox(height: 16),
            const Text(
              "Officer Registration",
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.blueGrey,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Create your officer account",
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 30),

            TextField(
              controller: firstNameController,
              decoration: InputDecoration(
                labelText: "First Name",
                prefixIcon: const Icon(Icons.person),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: lastNameController,
              decoration: InputDecoration(
                labelText: "Last Name",
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: emailController,
              onChanged: (value) {
                if (emailError != null) {
                  setState(() {
                    emailError = null;
                  });
                }
              },
              decoration: InputDecoration(
                labelText: "Email",
                errorText: emailError,
                prefixIcon: const Icon(Icons.email),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: passwordController,
              obscureText: true,
              onChanged: (value) {
                if (passwordError != null) {
                  setState(() {
                    passwordError = null;
                  });
                }
              },
              decoration: InputDecoration(
                labelText: "Password",
                errorText: passwordError,
                helperText: "Min 8 chars, 1 uppercase, 1 lowercase, 1 number",
                helperMaxLines: 2,
                prefixIcon: const Icon(Icons.lock),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 20),

            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: "Confirm Password",
                prefixIcon: const Icon(Icons.lock_outline),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isLoading ? null : signupOfficer,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueGrey,
                  padding: const EdgeInsets.all(15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        "SIGN UP",
                        style: TextStyle(fontSize: 18, color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}