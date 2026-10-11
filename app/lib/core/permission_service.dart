import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/stitch_theme.dart';

class PermissionService {
  static const String _keyHasRequestedInitial =
      'billket_has_requested_initial_permissions_v2';

  /// Returns whether initial permissions should be asked on app startup.
  static Future<bool> shouldAskInitialPermissions() async {
    if (kIsWeb) return false;
    if (!Platform.isAndroid && !Platform.isIOS) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyRequested = prefs.getBool(_keyHasRequestedInitial) ?? false;
      if (alreadyRequested) return false;

      // Check if camera is already granted
      final cameraStatus = await Permission.camera.status;
      if (cameraStatus.isGranted) {
        // If already granted somehow, mark as requested
        await prefs.setBool(_keyHasRequestedInitial, true);
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Marks that the initial permissions prompt has been presented.
  static Future<void> markInitialPermissionsRequested() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_keyHasRequestedInitial, true);
    } catch (_) {}
  }

  /// Requests all essential permissions needed for the application to function.
  static Future<Map<Permission, PermissionStatus>> requestAllEssentialPermissions() async {
    final permissionsToRequest = <Permission>[
      Permission.camera,
    ];

    if (Platform.isAndroid) {
      // Storage for saving reports, PDF bills, Excel/JSON exports
      permissionsToRequest.add(Permission.storage);
      permissionsToRequest.add(Permission.photos);
      permissionsToRequest.add(Permission.notification);
    } else if (Platform.isIOS) {
      permissionsToRequest.add(Permission.photos);
      permissionsToRequest.add(Permission.notification);
    }

    final statuses = await permissionsToRequest.request();
    await markInitialPermissionsRequested();
    return statuses;
  }

  /// Checks if camera permission is granted.
  static Future<bool> hasCameraPermission() async {
    if (kIsWeb) return true;
    return (await Permission.camera.status).isGranted;
  }

  /// Requests camera permission, optionally displaying explanation if permanently denied.
  static Future<bool> requestCameraPermission(BuildContext context) async {
    if (kIsWeb) return true;
    final status = await Permission.camera.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied && context.mounted) {
      _showOpenSettingsDialog(
        context,
        title: 'Camera Permission Required',
        message:
            'Camera permission is required to scan product barcodes and capture receipt photos. Please enable it in Settings.',
      );
    }
    return false;
  }

  /// Requests storage/file permission for downloading or saving reports.
  static Future<bool> requestStoragePermission(BuildContext context) async {
    if (kIsWeb || !Platform.isAndroid) return true;

    // On Android 13+ (SDK 33+), Permission.storage is always denied; photo/media permissions or Scoped Storage apply.
    final status = await Permission.storage.request();
    if (status.isGranted) return true;

    final photoStatus = await Permission.photos.request();
    if (photoStatus.isGranted) return true;

    if (status.isPermanentlyDenied && context.mounted) {
      _showOpenSettingsDialog(
        context,
        title: 'Storage Permission Required',
        message:
            'Storage permission is needed to save exported reports and invoices to your Downloads folder. Please enable it in Settings.',
      );
    }
    return false;
  }

  /// Displays the first-time permission onboarding bottom sheet.
  static Future<void> showInitialPermissionsPrompt(BuildContext context) async {
    if (!context.mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalCtx) => const _InitialPermissionsSheet(),
    );
  }

  static void _showOpenSettingsDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.settings_suggest_rounded, color: StitchColors.primary, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(fontSize: 13, color: StitchColors.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StitchColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

class _InitialPermissionsSheet extends StatefulWidget {
  const _InitialPermissionsSheet();

  @override
  State<_InitialPermissionsSheet> createState() => _InitialPermissionsSheetState();
}

class _InitialPermissionsSheetState extends State<_InitialPermissionsSheet> {
  bool _isRequesting = false;

  Future<void> _handleGrantPermissions() async {
    setState(() => _isRequesting = true);
    try {
      await PermissionService.requestAllEssentialPermissions();
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isRequesting = false);
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleSkip() async {
    await PermissionService.markInitialPermissionsRequested();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        22,
        14,
        22,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Header Banner
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [StitchColors.primary, Color(0xFF4F46E5)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: StitchColors.primary.withValues(alpha: 0.25),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Permissions Needed',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: StitchColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'To give you the best billing experience',
                        style: TextStyle(
                          fontSize: 12,
                          color: StitchColors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            const Text(
              'Billket requires access to your camera and files to scan barcodes and export reports directly to your phone:',
              style: TextStyle(
                fontSize: 12.5,
                color: StitchColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),

            // Feature 1: Camera
            _permissionTile(
              icon: Icons.camera_alt_rounded,
              iconColor: const Color(0xFF2563EB),
              bgColor: const Color(0xFFEFF6FF),
              title: 'Camera Access',
              description:
                  'Instantly scan item barcodes during checkout and take photos of bills or paper receipts.',
            ),
            const SizedBox(height: 10),

            // Feature 2: Files & Storage
            _permissionTile(
              icon: Icons.folder_rounded,
              iconColor: const Color(0xFF059669),
              bgColor: const Color(0xFFECFDF5),
              title: 'Files & Storage',
              description:
                  'Download GST reports (Excel .xlsx & JSON), save PDF invoices, and backup accounting data.',
            ),
            const SizedBox(height: 10),

            // Feature 3: Notifications
            _permissionTile(
              icon: Icons.notifications_active_rounded,
              iconColor: const Color(0xFF7C3AED),
              bgColor: const Color(0xFFF5F3FF),
              title: 'Alerts & Reminders',
              description:
                  'Receive critical notifications for payment receipts, daily sales summaries, and cloud sync.',
            ),
            const SizedBox(height: 22),

            // Action Buttons
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: StitchColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 1,
              ),
              onPressed: _isRequesting ? null : _handleGrantPermissions,
              child: _isRequesting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_outline_rounded, size: 18),
                        SizedBox(width: 8),
                        Text(
                          'Allow Permissions & Continue',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 8),

            TextButton(
              onPressed: _isRequesting ? null : _handleSkip,
              child: const Text(
                'Maybe Later',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: StitchColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permissionTile({
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StitchColors.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: StitchColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: StitchColors.textSecondary,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
