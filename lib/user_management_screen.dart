import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_config.dart';
import 'auth_service.dart';
import 'app_theme.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Create User form
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  String _selectedRole = 'farmer';
  bool _isCreating = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  // User list
  List<Map<String, dynamic>> _users = [];
  bool _isLoadingUsers = false;
  String? _usersError;

  final String baseUrl = AppConfig.apiBaseUrl;
  static const String _adminKey = 'supersecretadminkey';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && !_tabController.indexIsChanging) {
        _fetchUsers();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isCreating = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final role = _selectedRole;

    // Register locally in AuthService for RBAC
    AuthService.instance.registerAccount(
      username: username,
      password: password,
      roleStr: role,
    );

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/admin/create-user'),
        headers: {
          'Content-Type': 'application/json',
          'X-Admin-Key': _adminKey,
        },
        body: jsonEncode({'username': username, 'password': password, 'role': role}),
      );

      if (!mounted) return;
      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        _showBanner('User "$username" created as $role!', Colors.green.shade700);
      } else {
        _showBanner('User "$username" registered locally as $role!', Colors.green.shade700);
      }
    } catch (e) {
      if (!mounted) return;
      _showBanner('User "$username" created locally as $role (Offline mode)', Colors.green.shade700);
    } finally {
      if (mounted) {
        _formKey.currentState!.reset();
        _usernameController.clear();
        _passwordController.clear();
        _confirmPasswordController.clear();
        setState(() {
          _selectedRole = 'farmer';
          _isCreating = false;
        });
      }
    }
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoadingUsers = true;
      _usersError = null;
    });

    final localAccounts = AuthService.instance.getAllAccounts().map((a) => {
      'username': a.username,
      'role': a.roleString,
    }).toList();

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/admin/users'),
        headers: {'X-Admin-Key': _adminKey},
      ).timeout(const Duration(seconds: 3));

      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final fetched = List<Map<String, dynamic>>.from(data['users'] ?? []);
        setState(() {
          _users = [...localAccounts, ...fetched];
        });
      } else {
        setState(() => _users = localAccounts);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _users = localAccounts);
    } finally {
      if (mounted) setState(() => _isLoadingUsers = false);
    }
  }

  void _showBanner(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w500)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin': return Colors.deepPurple;
      case 'officer': return AppColors.aquaBlue;
      case 'farmer': return AppColors.emerald;
      default: return AppColors.textSecondary;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'admin': return Icons.admin_panel_settings_rounded;
      case 'officer': return Icons.badge_rounded;
      case 'farmer': return Icons.agriculture_rounded;
      default: return Icons.person_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textDark,
        elevation: 0,
        title: const Text(
          'User Role Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppColors.emerald,
          indicatorWeight: 3,
          labelColor: AppColors.emerald,
          unselectedLabelColor: AppColors.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.person_add_alt_1_rounded), text: 'Create User'),
            Tab(icon: Icon(Icons.group_rounded), text: 'All Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCreateUserTab(), _buildUsersListTab()],
      ),
    );
  }

  Widget _buildCreateUserTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.deepPurple.withOpacity(0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.manage_accounts, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Setup New User',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Assign roles: Admin · Officer · Farmer',
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            const Text(
              'Select Role',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: Colors.black87),
            ),
            const SizedBox(height: 12),

            // Role selector
            Row(
              children: ['farmer', 'admin'].map((role) {
                final selected = _selectedRole == role;
                final color = _roleColor(role);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedRole = role),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: selected ? color : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: selected ? color : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                        boxShadow: selected
                            ? [BoxShadow(color: color.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]
                            : [],
                      ),
                      child: Column(
                        children: [
                          Icon(_roleIcon(role), color: selected ? Colors.white : color, size: 26),
                          const SizedBox(height: 6),
                          Text(
                            role[0].toUpperCase() + role.substring(1),
                            style: TextStyle(
                              color: selected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 24),
            _buildLabel('Username / Email'),
            const SizedBox(height: 8),             TextFormField(
              controller: _usernameController,
              textInputAction: TextInputAction.next,
              decoration: _inputDeco('Enter username or email', Icons.person_outline),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Username is required';
                if (v.trim().length < 3) return 'Minimum 3 characters';
                return null;
              },
            ),

            const SizedBox(height: 16),
            _buildLabel('Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              decoration: _inputDeco('Enter password', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Password is required';
                if (v.trim().length < 4) return 'Minimum 4 characters';
                return null;
              },
            ),

            const SizedBox(height: 16),
            _buildLabel('Confirm Password'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirmPasswordController,
              obscureText: _obscureConfirm,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) { if (!_isCreating) _createUser(); },
              decoration: _inputDeco('Re-enter password', Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility, color: Colors.grey),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Please confirm password';
                if (v.trim() != _passwordController.text.trim()) return 'Passwords do not match';
                return null;
              },
            ),

            const SizedBox(height: 24),

            // Role info badge
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: _roleColor(_selectedRole).withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _roleColor(_selectedRole).withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(_roleIcon(_selectedRole), color: _roleColor(_selectedRole), size: 20),
                  const SizedBox(width: 10),
                  Text(
                    'This user will have ${_selectedRole.toUpperCase()} access',
                    style: TextStyle(
                      color: _roleColor(_selectedRole),
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCreating ? null : _createUser,
                icon: _isCreating
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.add_circle_outline, color: Colors.white),
                label: Text(
                  _isCreating ? 'Creating...' : 'CREATE USER',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.all(16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ),
      ),
     ),
    );
  }

  Widget _buildUsersListTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Registered Users (${_users.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.deepPurple),
                tooltip: 'Refresh',
                onPressed: _fetchUsers,
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoadingUsers
              ? const Center(child: CircularProgressIndicator(color: Colors.deepPurple))
              : _usersError != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.cloud_off, size: 60, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(_usersError!, style: TextStyle(color: Colors.grey.shade600)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _fetchUsers,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _users.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.people_outline, size: 60, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No users found.\nTap refresh to load.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _fetchUsers,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Load Users'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.deepPurple,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _users.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final user = _users[index];
                            final role = (user['role'] ?? 'farmer') as String;
                            final username = (user['username'] ?? '') as String;
                            final color = _roleColor(role);

                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade200),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.12),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(_roleIcon(role), color: color, size: 26),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          username,
                                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Icon(Icons.circle, size: 8, color: color),
                                            const SizedBox(width: 5),
                                            Text(
                                              role.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: color,
                                                fontWeight: FontWeight.w600,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: color.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      role[0].toUpperCase() + role.substring(1),
                                      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
    );
  }

  InputDecoration _inputDeco(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey.shade400),
      prefixIcon: Icon(icon, color: Colors.deepPurple.shade300),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.deepPurple, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }
}
