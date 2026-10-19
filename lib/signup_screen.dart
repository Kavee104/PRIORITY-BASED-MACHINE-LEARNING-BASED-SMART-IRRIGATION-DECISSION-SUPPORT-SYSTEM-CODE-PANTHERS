import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'app_localization.dart';
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
  final TextEditingController confirmPasswordController =
      TextEditingController();

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

    if (firstName.isEmpty ||
        lastName.isEmpty ||
        email.isEmpty ||
        password.isEmpty) {
      _showMessage(
        context.tr('Please fill all required fields'),
        Colors.orangeAccent,
      );
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
      _showMessage(context.tr('Passwords do not match'), Colors.redAccent);
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/signup"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "f_name": firstName,
              "l_name": lastName,
              "email": email,
              "password": password,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);
      final newFarmerId = (data is Map && data['farmer_id'] is int)
          ? data['farmer_id'] as int
          : null;

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 201) {
        AuthService.instance.registerAccount(
          username: email.contains('@') ? email.split('@')[0] : email,
          email: email,
          password: password,
          roleStr: 'farmer',
          name: "$firstName $lastName",
          customId: newFarmerId,
        );
        TextInput.finishAutofillContext(shouldSave: true);
        _showMessage(
          context.tr('Signup successful! You can now login.'),
          AppColors.emerald,
        );
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        _showMessage(
          data['error'] ?? "Could not save the account in the database.",
          Colors.redAccent,
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(
        "Could not connect to the registration server. Account was not created.",
        Colors.redAccent,
      );
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
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
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
        actions: const [
          Center(child: LanguageSelector()),
          SizedBox(width: 12),
        ],
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
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('Farmer Registration'),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textDark,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr(
                      'Sign up for AI-powered smart irrigation access',
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(
                      child: CustomTextField(
                        controller: firstNameController,
                        labelText: context.tr('First Name'),
                        prefixIcon: Icons.person_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomTextField(
                        controller: lastNameController,
                        labelText: context.tr('Last Name'),
                        prefixIcon: Icons.person_outline_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                CustomTextField(
                  controller: emailController,
                  labelText: context.tr('Email Address'),
                  hintText: "farmer@example.com",
                  prefixIcon: Icons.email_rounded,
                  keyboardType: TextInputType.emailAddress,
                ),
                if (emailError != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      emailError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                CustomTextField(
                  controller: passwordController,
                  labelText: context.tr('Password'),
                  prefixIcon: Icons.lock_rounded,
                  obscureText: obscurePassword,
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: AppColors.textLight,
                    ),
                    onPressed: () =>
                        setState(() => obscurePassword = !obscurePassword),
                  ),
                ),
                if (passwordError != null) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      passwordError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                CustomTextField(
                  controller: confirmPasswordController,
                  labelText: context.tr('Confirm Password'),
                  prefixIcon: Icons.lock_outline_rounded,
                  obscureText: obscureConfirm,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => signupUser(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscureConfirm
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: AppColors.textLight,
                    ),
                    onPressed: () =>
                        setState(() => obscureConfirm = !obscureConfirm),
                  ),
                ),
                const SizedBox(height: 28),

                PrimaryButton(
                  text: context.tr('CREATE FARMER ACCOUNT'),
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
