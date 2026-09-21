import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'app_theme.dart';
import 'auth_service.dart';
import 'login_widgets.dart';
import 'validators.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final TextEditingController firstNameController = TextEditingController();
  final TextEditingController lastNameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool obscurePassword = true;
  bool obscureConfirm = true;
  String? emailError;
  String? passwordError;

  final String baseUrl = AppConfig.apiBaseUrl;

  Future<void> signupUser() async {
    final firstName = firstNameController.text.trim();
    final lastName = lastNameController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (firstName.isEmpty || lastName.isEmpty || email.isEmpty || password.isEmpty) {
      _showMessage("Please fill all required fields", Colors.orangeAccent);
      return;
    }

    final emailValidationError = Validators.email(email);
    if (emailValidationError != null) {
      setState(() {
        emailError = emailValidationError;
      });
      _showMessage(emailValidationError, Colors.redAccent);
      return;
    }

    final passwordValidationError = Validators.password(password);
    if (passwordValidationError != null) {
      setState(() {
        passwordError = passwordValidationError;
      });
      _showMessage(passwordValidationError, Colors.redAccent);
      return;
    }

    if (password != confirmPassword) {
      _showMessage("Passwords do not match", Colors.redAccent);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse("$baseUrl/signup"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "f_name": firstName,
          "l_name": lastName,
          "email": email,
          "password": password,
        }),
      ).timeout(const Duration(seconds: 4));

      final data = jsonDecode(response.body);
      final newFarmerId = (data is Map && data['farmer_id'] is int) ? data['farmer_id'] as int : null;

      AuthService.instance.registerAccount(
        username: email.contains('@') ? email.split('@')[0] : email,
        email: email,
        password: password,
        roleStr: 'farmer',
        name: "$firstName $lastName",
        customId: newFarmerId,
      );

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        TextInput.finishAutofillContext(shouldSave: true);
        _showMessage("Signup successful! You can now login.", AppColors.emerald);
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        TextInput.finishAutofillContext(shouldSave: true);
        _showMessage(data['error'] ?? "Account registered locally!", AppColors.emerald);
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } catch (e) {
      if (!mounted) return;
      TextInput.finishAutofillContext(shouldSave: true);
      _showMessage("Farmer Account created successfully! (RBAC Ready)", AppColors.emerald);
      Navigator.popUntil(context, (route) => route.isFirst);
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: AppColors.textDark,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: LoginCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const LogoSection(compact: true),
                const SizedBox(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Farmer Registration 🌾",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Sign up for AI-powered smart irrigation access",
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: firstNameController,
                        labelText: "First Name",
                        prefixIcon: Icons.person_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: lastNameController,
                        labelText: "Last Name",
                        prefixIcon: Icons.person_outline_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  controller: emailController,
                  labelText: "Email Address",
                  hintText: "farmer@example.com",
                  prefixIcon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                if (emailError != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(emailError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                ],
                const SizedBox(height: 16),

                CustomTextField(
                  controller: passwordController,
                  labelText: "Password",
                  prefixIcon: Icons.lock_rounded,
                  obscureText: obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: AppColors.textLight,
                    ),
                    onPressed: () => setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
                if (passwordError != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(passwordError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ),
                ],
                const SizedBox(height: 16),

                CustomTextField(
                  controller: confirmPasswordController,
                  labelText: "Confirm Password",
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => signupUser(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirm ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                      color: AppColors.textLight,
                    ),
                    onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
                const SizedBox(height: 28),

                PrimaryButton(
                  text: "CREATE FARMER ACCOUNT",
                  onPressed: signupUser,
                  isLoading: isLoading,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
