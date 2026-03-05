import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:personal_finance_tracker/theme/app_icons.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;

import '../helpers/config.dart';
import '../helpers/database_helper.dart';
import '../helpers/dialog_helper.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final dbHelper = DatabaseHelper();
  final _auth = FirebaseAuth.instance;
  final _nameController = TextEditingController();

  User? get currentUser => _auth.currentUser;

  bool _isLoggingOut = false;
  bool _isUploading = false;
  bool _isRestoring = false;
  String _selectedCurrency = 'KSh';
  bool _isImageLoading = false;
  String? _cachedImageUrl;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _refreshUserData();
    // Preload profile image immediately
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _preloadProfileImage();
    });
  }

  Future<void> _preloadImage(String imageUrl) async {
    if (!mounted || _cachedImageUrl == imageUrl) return;

    setState(() {
      _isImageLoading = true;
    });

    try {
      await precacheImage(NetworkImage(imageUrl), context);
      if (!mounted) return;
      setState(() {
        _cachedImageUrl = imageUrl;
        _isImageLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isImageLoading = false;
      });
    }
  }

  Future<void> _preloadProfileImage() async {
    if (currentUser?.photoURL != null && currentUser!.photoURL!.isNotEmpty) {
      final imageUrl = _optimizedProfileImageUrl(currentUser!.photoURL!);
      await _preloadImage(imageUrl);
    }
  }

  String _optimizedProfileImageUrl(String imageUrl) {
    if (!imageUrl.contains('cloudinary.com') ||
        !imageUrl.contains('/upload/')) {
      return imageUrl;
    }

    if (imageUrl.contains('/upload/w_')) {
      return imageUrl;
    }

    return imageUrl.replaceFirst(
      '/upload/',
      '/upload/w_200,h_200,c_fill,q_auto,f_auto/',
    );
  }

  Future<void> _refreshUserData() async {
    // Reload user data to ensure we have the latest photoURL
    if (currentUser != null) {
      await currentUser!.reload();
      if (mounted) {
        setState(() {});
        // Preload image after refresh
        _preloadProfileImage();
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickAndUploadImage() async {
    final imagePicker = ImagePicker();
    final XFile? image = await imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    ); // Slightly higher quality but still optimized

    if (image == null || currentUser == null) return;

    setState(() => _isUploading = true);

    try {
      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/${AppConfig.cloudinaryCloudName}/image/upload',
      );
      final request = http.MultipartRequest('POST', url);
      request.files.add(await http.MultipartFile.fromPath('file', image.path));

      final timestamp =
          (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString();
      final stringToSign =
          'timestamp=$timestamp${AppConfig.cloudinaryApiSecret}';
      final signature = sha1.convert(utf8.encode(stringToSign)).toString();

      request.fields['api_key'] = AppConfig.cloudinaryApiKey;
      request.fields['timestamp'] = timestamp;
      request.fields['signature'] = signature;

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final responseJson = json.decode(responseData);
        final imageUrl = responseJson['secure_url'];

        // Update photo URL in Firebase Auth
        await currentUser!.updatePhotoURL(imageUrl);

        // Preload the new image immediately
        await _preloadImage(imageUrl);

        // Wait for Firebase to process the update
        await Future.delayed(const Duration(milliseconds: 500));

        // Reload user to get updated photo URL from Firebase
        await currentUser!.reload();

        // Get fresh user instance
        final updatedUser = _auth.currentUser;

        // Verify the photo URL was saved
        if (updatedUser != null) {
          // Reload one more time to ensure we have the latest data
          await updatedUser.reload();
          final finalUser = _auth.currentUser;
          if (!mounted) return;

          // Preload the image again to ensure it's cached.
          if (finalUser?.photoURL != null) {
            await _preloadImage(finalUser!.photoURL!);
            if (!mounted) return;
          }

          if (finalUser?.photoURL == imageUrl || finalUser?.photoURL != null) {
            SnackbarHelper.showSuccess(
              context,
              'Profile picture updated successfully!',
            );
          } else {
            SnackbarHelper.showSuccess(
              context,
              'Profile picture updated! Changes will appear after app restart.',
            );
          }
        }
      } else {
        final errorData = await response.stream.bytesToString();
        debugPrint('Cloudinary Error: $errorData');
        if (mounted) {
          SnackbarHelper.showError(
            context,
            'Failed to upload image. Status code: ${response.statusCode}',
          );
        }
      }
    } catch (e) {
      debugPrint('Error uploading to Cloudinary: $e');
      if (mounted) {
        SnackbarHelper.showError(context, 'Failed to upload image: $e');
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _selectedCurrency = prefs.getString('currency') ?? 'KSh';
      });
    }
  }

  Future<void> _saveCurrencyPreference(String currency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency', currency);
    setState(() => _selectedCurrency = currency);
  }

  void _showUpdateNameDialog() async {
    final result = await DialogHelper.showInputDialog(
      context: context,
      title: 'Update Your Name',
      hintText: 'Enter your full name',
      initialValue: currentUser?.displayName,
      confirmText: 'Update',
    );

    if (result != null && result.isNotEmpty && currentUser != null) {
      try {
        await currentUser!.updateDisplayName(result.trim());
        if (mounted) {
          SnackbarHelper.showSuccess(context, 'Name updated successfully!');
          setState(() {});
        }
      } catch (e) {
        if (mounted) {
          SnackbarHelper.showError(context, 'Failed to update name');
        }
      }
    }
  }

  Future<void> _sendPasswordResetEmail() async {
    if (currentUser?.email == null) return;
    try {
      await _auth.sendPasswordResetEmail(email: currentUser!.email!);
      if (mounted) {
        SnackbarHelper.showSuccess(
          context,
          'Password reset link sent to your email.',
        );
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        SnackbarHelper.showError(
          context,
          e.message ?? 'Failed to send reset email.',
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final bool? confirm = await DialogHelper.showConfirmDialog(
      context: context,
      title: 'Delete Account',
      message:
          'This is irreversible. All your data will be permanently deleted. Are you sure?',
      confirmText: 'DELETE',
      confirmColor: Colors.red,
    );

    if (confirm == true) {
      try {
        await currentUser?.delete();
        if (mounted) {
          SnackbarHelper.showSuccess(context, 'Account deleted successfully.');
        }
      } on FirebaseAuthException catch (e) {
        if (mounted) {
          SnackbarHelper.showError(
            context,
            e.message ?? 'Failed to delete account.',
          );
        }
      }
    }
  }

  Future<void> _logout() async {
    if (!mounted) return;

    final bool? confirm = await DialogHelper.showConfirmDialog(
      context: context,
      title: 'Confirm Logout',
      message: 'Are you sure you want to log out?',
      confirmText: 'Logout',
      confirmColor: Colors.red,
    );

    if (confirm != true || !mounted) return;

    setState(() => _isLoggingOut = true);

    try {
      await _auth.signOut();
      // After signOut, AuthGate's StreamBuilder will detect the auth state change
      // and navigate to WelcomeScreen. The ProfileScreen will be disposed.
      // Don't try to update state here as the widget will be disposed.
    } catch (e) {
      debugPrint('Logout error: $e');
      // Only update state if logout failed and widget is still mounted
      if (mounted) {
        setState(() => _isLoggingOut = false);
        SnackbarHelper.showError(context, 'Failed to log out: ${e.toString()}');
      }
    }
  }

  Future<void> _launchWhatsApp() async {
    const phoneNumber = '+254748088741'; // WhatsApp format: no spaces
    const message = 'Hello, I have a question about the Ledgerlite app.';
    final whatsappUrl = Uri.parse(
      "https://wa.me/$phoneNumber?text=${Uri.encodeComponent(message)}",
    );

    try {
      final canLaunch = await canLaunchUrl(whatsappUrl);
      if (!mounted) return;

      if (canLaunch) {
        await launchUrl(whatsappUrl, mode: LaunchMode.externalApplication);
      } else {
        SnackbarHelper.showError(
          context,
          'Could not launch WhatsApp. Is it installed?',
        );
      }
    } catch (e) {
      if (!mounted) return;
      SnackbarHelper.showError(context, 'An error occurred.');
    }
  }

  void _showFaqDialog() {
    DialogHelper.showModernDialog(
      context: context,
      title: 'Frequently Asked Questions',
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFaqItem(
              'How do I add a transaction?',
              'Tap the "+" button on the home screen, fill in the details, and tap "Save Transaction".',
            ),
            const SizedBox(height: 16),
            _buildFaqItem(
              'How do I manage categories?',
              'Go to Add Transaction screen, tap the settings icon next to Category, or go to Settings > Manage Categories.',
            ),
            const SizedBox(height: 16),
            _buildFaqItem(
              'Can I set up recurring bills?',
              'Yes! When adding a bill, toggle "Recurring Bill" and select the frequency (weekly or monthly).',
            ),
            const SizedBox(height: 16),
            _buildFaqItem(
              'How do I view my financial reports?',
              'Tap the "Reports" tab at the bottom to see charts and breakdowns of your income and expenses.',
            ),
            const SizedBox(height: 16),
            _buildFaqItem(
              'Is my data backed up?',
              'Yes! Your data is automatically synced to the cloud. You can restore it anytime from Settings.',
            ),
            const SizedBox(height: 16),
            _buildFaqItem(
              'How do I change my currency?',
              'Go to Settings > Currency and select your preferred currency from the dropdown.',
            ),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text(
            'Close',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          answer,
          style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.5),
        ),
      ],
    );
  }

  Future<void> _handleRestore() async {
    if (currentUser == null) return;

    final bool? confirm = await DialogHelper.showConfirmDialog(
      context: context,
      title: 'Restore from Cloud',
      message:
          'This will replace all local data with your cloud backup. Are you sure?',
      confirmText: 'Restore',
      confirmColor: Colors.blue,
    );

    if (confirm == true && mounted) {
      setState(() => _isRestoring = true);
      try {
        await dbHelper.restoreFromFirestore(currentUser!.uid);
        if (!mounted) return;
        SnackbarHelper.showSuccess(
          context,
          "Data restored successfully! Please restart the app to see all changes.",
        );
      } catch (e) {
        if (!mounted) return;
        SnackbarHelper.showError(context, "Error restoring data: $e");
      } finally {
        if (mounted) setState(() => _isRestoring = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _auth.userChanges(),
      builder: (context, userSnapshot) {
        final user = userSnapshot.data ?? currentUser;

        if (user == null) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (user.photoURL != null && user.photoURL!.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && currentUser != null) {
              _preloadProfileImage();
            }
          });
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final topGradientColor =
            (isDark ? AppColors.darkPrimary : AppColors.primary).withValues(
          alpha: isDark ? 0.18 : 0.08,
        );

        return Scaffold(
          body: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  topGradientColor,
                  Theme.of(context).scaffoldBackgroundColor,
                ],
              ),
            ),
            child: SafeArea(
              child: RefreshIndicator(
                onRefresh: _refreshUserData,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    _buildScreenHeader(),
                    const SizedBox(height: 16),
                    _buildProfileHero(user),
                    const SizedBox(height: 20),
                    _buildSectionCard(
                      icon: AppIcons.money,
                      title: 'Preferences',
                      subtitle: 'Customize your finance workspace.',
                      children: [
                        _buildActionTile(
                          icon: AppIcons.money,
                          title: 'Currency',
                          subtitle: 'Choose your default amount format',
                          trailing: _buildCurrencyTrailingPill(),
                          onTap: _showCurrencyPicker,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildSectionCard(
                      icon: AppIcons.security,
                      title: 'Account & Security',
                      subtitle: 'Manage account access and sensitive actions.',
                      children: [
                        _buildActionTile(
                          icon: AppIcons.password,
                          title: 'Change Password',
                          subtitle: 'Send a reset link to your email',
                          onTap: _sendPasswordResetEmail,
                        ),
                        _buildActionTile(
                          icon: AppIcons.delete_forever,
                          title: 'Delete Account',
                          subtitle: 'Permanently remove your account and data',
                          accentColor: AppColors.error,
                          titleColor: AppColors.error,
                          onTap: _deleteAccount,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildSectionCard(
                      icon: AppIcons.cloud_download_outlined,
                      title: 'Data & Sync',
                      subtitle: 'Restore your cloud backup on this device.',
                      children: [
                        _buildActionTile(
                          icon: AppIcons.cloud_download_outlined,
                          title: 'Restore from Cloud',
                          subtitle: 'Replace local records with cloud backup',
                          trailing: _isRestoring
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : null,
                          onTap: _isRestoring ? null : _handleRestore,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _buildSectionCard(
                      icon: AppIcons.support_agent,
                      title: 'Help & Support',
                      subtitle: 'Get answers or contact support directly.',
                      children: [
                        _buildActionTile(
                          icon: AppIcons.question_answer_outlined,
                          title: 'FAQ',
                          subtitle: 'Read common questions and quick tips',
                          onTap: _showFaqDialog,
                        ),
                        _buildActionTile(
                          customLeading: SvgPicture.asset(
                            'assets/icons/whatsapp_logo.svg',
                            width: 18,
                            height: 18,
                          ),
                          accentColor: const Color(0xFF25D366),
                          title: 'Contact via WhatsApp',
                          subtitle: 'Chat with support in WhatsApp',
                          onTap: _launchWhatsApp,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    _buildLogoutButton(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildScreenHeader() {
    final textTheme = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile',
                style: textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Manage preferences, security, and support settings.',
                style: textTheme.bodyMedium?.copyWith(
                  color: muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.filledTonal(
          onPressed: _refreshUserData,
          icon: const Icon(AppIcons.refresh),
          style: IconButton.styleFrom(
            foregroundColor: AppColors.primary,
            backgroundColor: AppColors.primary.withValues(alpha: 0.14),
          ),
          tooltip: 'Refresh profile',
        ),
      ],
    );
  }

  Widget _buildProfileHero(User user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final heroPrimary = isDark ? AppColors.darkPrimary : AppColors.primary;
    final heroSecondary = isDark ? AppColors.darkTertiary : AppColors.tertiary;
    final displayName = (user.displayName ?? '').trim().isEmpty
        ? 'User'
        : user.displayName!.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [heroPrimary, heroSecondary],
        ),
        boxShadow: [
          BoxShadow(
            color: heroPrimary.withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: _pickAndUploadImage,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildProfileAvatar(user),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Icon(
                          AppIcons.edit,
                          size: 14,
                          color: heroPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        IconButton(
                          onPressed: _showUpdateNameDialog,
                          icon: const Icon(AppIcons.edit, size: 16),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            padding: EdgeInsets.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            foregroundColor: Colors.white,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.16),
                          ),
                          tooltip: 'Edit name',
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user.email ?? 'No email',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildHeroPill(
                          icon: AppIcons.money,
                          text: 'Currency: $_selectedCurrency',
                        ),
                        _buildHeroPill(
                          icon: AppIcons.verified_user_outlined,
                          text: user.emailVerified
                              ? 'Email verified'
                              : 'Verify email',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionButton(
                  icon: AppIcons.edit,
                  label: 'Edit Name',
                  onTap: _showUpdateNameDialog,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildQuickActionButton(
                  icon: AppIcons.password,
                  label: 'Reset Password',
                  onTap: _sendPasswordResetEmail,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroPill({required IconData icon, required String text}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.26)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: Colors.white),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor =
        isDark ? AppColors.darkNeutralBorder : AppColors.neutralBorder;
    final surfaceColor =
        isDark ? AppColors.darkCardBackground : AppColors.white;
    final muted =
        isDark ? AppColors.darkNeutralMedium : AppColors.neutralMedium;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 17, color: AppColors.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: muted,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (int index = 0; index < children.length; index++) ...[
            children[index],
            if (index < children.length - 1)
              Divider(
                height: 1,
                color: Theme.of(context).colorScheme.outlineVariant.withValues(
                      alpha: 0.72,
                    ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionTile({
    IconData? icon,
    Widget? customLeading,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    Color? accentColor,
    Color? titleColor,
  }) {
    final color = accentColor ?? AppColors.primary;
    final leadingIcon = customLeading ??
        Icon(
          icon ?? AppIcons.info_outline,
          size: 18,
          color: color,
        );
    final isEnabled = onTap != null;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: leadingIcon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: titleColor ??
                                Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: muted,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing ??
                  (isEnabled
                      ? Icon(AppIcons.chevron_right, size: 18, color: muted)
                      : Icon(
                          AppIcons.chevron_right,
                          size: 18,
                          color: muted.withValues(alpha: 0.45),
                        )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrencyTrailingPill() {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            _selectedCurrency,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(AppIcons.chevron_right, size: 18, color: muted),
      ],
    );
  }

  Future<void> _showCurrencyPicker() async {
    const currencies = <String>['KSh', 'USD', 'EUR', 'GBP'];

    final selectedCurrency = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (bottomSheetContext) {
        final muted = Theme.of(bottomSheetContext).colorScheme.onSurfaceVariant;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: muted.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Select currency',
                style: Theme.of(bottomSheetContext)
                    .textTheme
                    .titleMedium
                    ?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'This affects all amount labels across the app.',
                style:
                    Theme.of(bottomSheetContext).textTheme.bodySmall?.copyWith(
                          color: muted,
                          fontWeight: FontWeight.w600,
                        ),
              ),
              const SizedBox(height: 12),
              for (final currency in currencies)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => Navigator.of(bottomSheetContext).pop(currency),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              currency,
                              style: Theme.of(bottomSheetContext)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (_selectedCurrency == currency)
                            const Icon(
                              AppIcons.check_circle,
                              size: 18,
                              color: AppColors.success,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted ||
        selectedCurrency == null ||
        selectedCurrency == _selectedCurrency) {
      return;
    }

    await _saveCurrencyPreference(selectedCurrency);
    if (!mounted) return;
    SnackbarHelper.showSuccess(
        context, 'Currency updated to $selectedCurrency');
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton.icon(
        onPressed: _isLoggingOut ? null : _logout,
        icon: _isLoggingOut
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: Colors.white,
                ),
              )
            : const Icon(AppIcons.logout),
        label: Text(_isLoggingOut ? 'Logging out...' : 'Logout'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.error,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Theme.of(context).colorScheme.outlineVariant,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildProfileAvatar(User user) {
    final imageUrl = user.photoURL == null || user.photoURL!.isEmpty
        ? null
        : _optimizedProfileImageUrl(user.photoURL!);
    final isLoading =
        imageUrl != null && _isImageLoading && _cachedImageUrl != imageUrl;

    return Container(
      width: 86,
      height: 86,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.45),
          width: 2.4,
        ),
      ),
      child: ClipOval(
        child: imageUrl == null
            ? Container(
                color: Colors.white.withValues(alpha: 0.18),
                child: const Icon(
                  AppIcons.person,
                  size: 40,
                  color: Colors.white,
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    cacheWidth: 200,
                    cacheHeight: 200,
                    errorBuilder: (context, error, stackTrace) => Container(
                      color: Colors.white.withValues(alpha: 0.18),
                      child: const Icon(
                        AppIcons.person,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (_isUploading || isLoading)
                    Container(
                      color: Colors.black.withValues(alpha: 0.34),
                      alignment: Alignment.center,
                      child: const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
