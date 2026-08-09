import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController otpController = TextEditingController();
  final TextEditingController newPasswordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool isLoading = false;
  int step = 1; // 1 = enter email, 2 = enter OTP, 3 = enter new password

  final String baseUrl = AppConfig.apiBaseUrl;

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> requestOtp() async {
    final email = emailController.text.trim();
    if (email.isEmpty) {
      _showMessage("Please enter your email");
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/forgot-password"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email}),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final devOtp = data['dev_otp'];
        _showMessage(
          devOtp == null
              ? data['message'] ?? "OTP sent to your email"
              : "${data['message']} OTP: $devOtp",
        );
        setState(() => step = 2);
      } else {
        _showMessage(data['error'] ?? "Failed to send OTP");
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage("Could not reach backend at $baseUrl");
    }

    if (!mounted) return;
    setState(() => isLoading = false);
  }

  Future<void> verifyOtp() async {
    final otp = otpController.text.trim();
    if (otp.isEmpty) {
      _showMessage("Please enter the OTP");
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/validate-otp"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": emailController.text.trim(),
          "otp": otp,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200) {
        _showMessage(data['message'] ?? "OTP verified");
        setState(() => step = 3);
      } else {
        _showMessage(data['error'] ?? "Invalid OTP");
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage("Could not reach backend at $baseUrl");
    }

    if (!mounted) return;
    setState(() => isLoading = false);
  }

  Future<void> resetPassword() async {
    final newPassword = newPasswordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showMessage("Please fill both password fields");
      return;
    }

    if (newPassword != confirmPassword) {
      _showMessage("Passwords do not match");
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/reset-password"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "email": emailController.text.trim(),
          "otp": otpController.text.trim(),
          "new_password": newPassword,
        }),
      );

      final data = jsonDecode(response.body);

      if (!mounted) return;

      if (response.statusCode == 200) {
        _showMessage(data['message'] ?? "Password reset successful! Please login.");
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        _showMessage(data['error'] ?? "Failed to reset password");
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage("Could not reach backend at $baseUrl");
    }

    if (!mounted) return;
    setState(() => isLoading = false);
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Enter your registered email. We'll send you an OTP.",
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: emailController,
          decoration: InputDecoration(
            labelText: "Email",
            prefixIcon: const Icon(Icons.email),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: isLoading ? null : requestOtp,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(15)),
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text("SEND OTP"),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Enter the OTP sent to ${emailController.text.trim()}",
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: otpController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: "OTP",
            prefixIcon: const Icon(Icons.lock_clock),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: isLoading ? null : verifyOtp,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(15)),
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text("VERIFY OTP"),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: isLoading ? null : requestOtp,
          child: const Text("Resend OTP"),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Enter your new password.",
          style: TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: newPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: "New Password",
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
            labelText: "Confirm New Password",
            prefixIcon: const Icon(Icons.lock_outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: isLoading ? null : resetPassword,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(15)),
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text("RESET PASSWORD"),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.green),
        title: const Text(
          "Forgot Password",
          style: TextStyle(color: Colors.green),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.water_drop, size: 70, color: Colors.green),
            const SizedBox(height: 24),
            if (step == 1) _buildStep1(),
            if (step == 2) _buildStep2(),
            if (step == 3) _buildStep3(),
          ],
        ),
      ),
    );
  }
}
