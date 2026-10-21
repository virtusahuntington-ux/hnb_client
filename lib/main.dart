import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://kbkzbdidvpskssjvoxor.supabase.co',
    publishableKey: 'sb_publishable_6GyZDug44K5tjxkFGSbqZw_sZkd_3Yp',
  );

  runApp(const ClientApp());
}

final supabase = Supabase.instance.client;

// ---------------------------------------------------------------------------
// User Session Data Model (With JSON Serialization for LocalStorage)
// ---------------------------------------------------------------------------
class UserProfileData {
  final String email;
  final String username;
  final String designation;
  final String? photoUrl;

  UserProfileData({
    required this.email,
    required this.username,
    required this.designation,
    this.photoUrl,
  });

  Map<String, dynamic> toJson() => {
    'email': email,
    'username': username,
    'designation': designation,
    'photo_url': photoUrl,
  };

  factory UserProfileData.fromJson(Map<String, dynamic> json) {
    return UserProfileData(
      email: json['email'] ?? '',
      username: json['username'] ?? 'HNB Cherished Moments',
      designation: json['designation'] ?? 'VIP Corporate Guest',
      photoUrl: json['photo_url'],
    );
  }

  static void saveToStorage(UserProfileData profile) {
    html.window.localStorage['hnb_user_session'] = jsonEncode(profile.toJson());
  }

  static UserProfileData? loadFromStorage() {
    final sessionJson = html.window.localStorage['hnb_user_session'];
    if (sessionJson != null && sessionJson.isNotEmpty) {
      try {
        final data = jsonDecode(sessionJson);
        return UserProfileData.fromJson(data);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static void clearStorage() {
    html.window.localStorage.remove('hnb_user_session');
  }
}

// ---------------------------------------------------------------------------
// Router Setup: Screen 1 (Login) -> Screen 2 (Dashboard)
// ---------------------------------------------------------------------------
final GoRouter _router = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const LoginScreen(),
      redirect: (context, state) {
        final savedProfile = UserProfileData.loadFromStorage();
        if (savedProfile != null) {
          return '/dashboard/client1';
        }
        return null;
      },
    ),
    GoRoute(
      path: '/dashboard/:clientId',
      builder: (context, state) {
        final clientId = state.pathParameters['clientId'] ?? 'client1';
        final userProfile =
            (state.extra as UserProfileData?) ??
            UserProfileData.loadFromStorage() ??
            UserProfileData(
              email: 'Team Virtusa - Huntington',
              username: 'Virtusa - Huntington Cherished Moments',
              designation: 'Guest',
            );
        return ClientDashboard(clientId: clientId, userProfile: userProfile);
      },
      redirect: (context, state) {
        final savedProfile = UserProfileData.loadFromStorage();
        if (state.extra == null && savedProfile == null) {
          return '/';
        }
        return null;
      },
    ),
  ],
);

class ClientApp extends StatelessWidget {
  const ClientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: _router,
      title: 'HNB Cherished Memories',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          primary: const Color(0xFF2E7D32),
          secondary: const Color(0xFF81C784),
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAF8),
      ),
    );
  }
}

// ===========================================================================
// SCREEN 1: LOGIN SCREEN (WITH FEATURE-FLAGGED GUEST MODE)
// ===========================================================================
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isPasswordVisible = false;
  bool _isLoading = false;
  String? _errorMessage;

  late final Future<Map<String, dynamic>?> _loginConfigFuture;
  late final Future<Map<String, dynamic>?> _internalPortalConfigFuture;

  @override
  void initState() {
    super.initState();
    _loginConfigFuture = _fetchLoginConfig();
    _internalPortalConfigFuture = _fetchInternalPortalConfig();
  }

  Future<Map<String, dynamic>?> _fetchLoginConfig() async {
    try {
      final response = await Supabase.instance.client
          .from('login_config')
          .select()
          .limit(1)
          .maybeSingle();
      return response;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _fetchInternalPortalConfig() async {
    try {
      final response = await Supabase.instance.client
          .from('internal_portal_config')
          .select()
          .eq('key', 'guest_config')
          .maybeSingle();
      return response;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleGuestLogin(Map<String, dynamic> portalConfig) {
    final guestEmail =
        portalConfig['guest_email'] ?? 'Virtusa - Huntington Cherished Moments';
    final guestUsername =
        portalConfig['guest_username'] ??
        'To Virtusa - Huntington Cherished Moments';
    final guestDesignation =
        portalConfig['guest_designation'] ?? 'VIR Corporate Guest';

    final guestProfile = UserProfileData(
      email: guestEmail,
      username: guestUsername,
      designation: guestDesignation,
    );

    UserProfileData.saveToStorage(guestProfile);
    context.go('/dashboard/client1', extra: guestProfile);
  }

  void _handleLogin() async {
    setState(() => _errorMessage = null);

    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final enteredEmail = _emailController.text.trim().toLowerCase();
    final enteredPassword = _passwordController.text.trim();

    try {
      final response = await Supabase.instance.client
          .from('client_profiles')
          .select()
          .eq('email', enteredEmail)
          .maybeSingle();

      if (!mounted) return;

      if (response != null) {
        final String storedPassword = response['password'] ?? '';

        if (storedPassword == enteredPassword) {
          final userProfile = UserProfileData(
            email: response['email'] ?? enteredEmail,
            username: response['username'] ?? 'Guest User',
            designation: response['designation'] ?? 'VIP Corporate Guest',
            photoUrl: response['photo_url'],
          );

          UserProfileData.saveToStorage(userProfile);

          setState(() => _isLoading = false);
          context.go('/dashboard/client1', extra: userProfile);
        } else {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Invalid credentials: Incorrect password.';
          });
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Access Denied: Account not found in client database.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Authentication Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    return Scaffold(
      backgroundColor: const Color(0xFF0D3B12),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF2E7D32),
                    Color(0xFF1B5E20),
                    Color(0xFF0D3B12),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Card(
                elevation: 12,
                shadowColor: Colors.black45,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Container(
                  width: isMobile ? double.infinity : 440,
                  padding: EdgeInsets.all(isMobile ? 24 : 36),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: FutureBuilder<Map<String, dynamic>?>(
                    future: _loginConfigFuture,
                    builder: (context, snapshot) {
                      final config = snapshot.data;
                      final titleText =
                          config?['title'] ?? 'HNB Cherished Memories';
                      final subtitleText = config?['subtitle'] ?? 'Login';
                      final emailLabel =
                          config?['email_label'] ?? 'Huntington Email';
                      final emailHint =
                          config?['email_hint'] ?? 'username@huntington.com';
                      final passwordLabel =
                          config?['password_label'] ?? 'Password';
                      final passwordHint =
                          config?['password_hint'] ??
                          'password is your passport id';

                      return Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFE8F5E9),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.lock_person_rounded,
                                  size: 40,
                                  color: Color(0xFF2E7D32),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              titleText,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitleText,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 24),

                            if (_errorMessage != null) ...[
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.red.shade200,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      size: 18,
                                      color: Colors.redAccent,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _errorMessage!,
                                        style: TextStyle(
                                          color: Colors.red.shade900,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: InputDecoration(
                                labelText: emailLabel,
                                hintText: emailHint,
                                prefixIcon: const Icon(
                                  Icons.email_outlined,
                                  color: Color(0xFF2E7D32),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF2E7D32),
                                    width: 2,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter your email';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),

                            TextFormField(
                              controller: _passwordController,
                              obscureText: !_isPasswordVisible,
                              decoration: InputDecoration(
                                labelText: passwordLabel,
                                hintText: passwordHint,
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  color: Color(0xFF2E7D32),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _isPasswordVisible
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                  ),
                                  onPressed: () => setState(
                                    () => _isPasswordVisible =
                                        !_isPasswordVisible,
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF2E7D32),
                                    width: 2,
                                  ),
                                ),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter password';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),

                            ElevatedButton(
                              onPressed: _isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2E7D32),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.all(14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 2,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      'Verify & Login',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),

                            // ==========================================
                            // ORIGINAL LOOK & FEEL CTA WITH COMPACT INFO TOOLTIP
                            // ==========================================
                            FutureBuilder<Map<String, dynamic>?>(
                              future: _internalPortalConfigFuture,
                              builder: (context, portalSnapshot) {
                                final portalConfig = portalSnapshot.data ?? {};
                                final bool isGuestModeEnabled =
                                    portalConfig['is_guest_mode_enabled'] ??
                                    true;
                                final String buttonLabel =
                                    portalConfig['button_label'] ??
                                    'Login - Internal Portal';
                                final String adminMessage =
                                    portalConfig['admin_message'] ??
                                    'This CTA is visible under database control by the database admin. If you are facing any issues, please contact the DATABASE admin.';

                                if (!isGuestModeEnabled) {
                                  return const SizedBox.shrink();
                                }

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Divider(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          child: Text(
                                            'OR',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.grey.shade500,
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Divider(
                                            color: Colors.grey.shade300,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      children: [
                                        // Original Standard Look & Feel OutlinedButton
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _handleGuestLogin(portalConfig),
                                            style: OutlinedButton.styleFrom(
                                              foregroundColor: const Color(
                                                0xFF2E7D32,
                                              ),
                                              padding: const EdgeInsets.all(12),
                                              side: const BorderSide(
                                                color: Color(0xFF81C784),
                                                width: 1.5,
                                              ),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.person_pin_rounded,
                                              size: 20,
                                              color: Color(0xFF2E7D32),
                                            ),
                                            label: Text(
                                              buttonLabel,
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),

                                        // Small Dedicated Info Icon with Minimal Tooltip
                                        Tooltip(
                                          message: adminMessage,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 6,
                                          ),
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade900,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          textStyle: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                          ),
                                          child: Container(
                                            height: 48,
                                            width: 32,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.info_outline_rounded,
                                              size: 16,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// SCREEN 2: MAIN DASHBOARD SCREEN
// ===========================================================================
class ClientDashboard extends StatefulWidget {
  final String clientId;
  final UserProfileData userProfile;

  const ClientDashboard({
    super.key,
    required this.clientId,
    required this.userProfile,
  });

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  final GlobalKey _highlightsKey = GlobalKey();
  final GlobalKey _photosKey = GlobalKey();
  final GlobalKey _videosKey = GlobalKey();
  final GlobalKey _virtusaKey = GlobalKey();

  String _selectedCategory = 'All';
  final List<String> _categories = ['All', 'Sessions', 'Cultural Events'];

  late Future<List<Map<String, dynamic>>> _momentsFuture;
  late Future<Map<String, dynamic>?> _topBannerFuture;
  late Future<List<Map<String, dynamic>>> _bottomQuoteFuture;
  late Future<List<Map<String, dynamic>>> _virtusaDocsFuture;

  @override
  void initState() {
    super.initState();
    _momentsFuture = _fetchMoments();
    _topBannerFuture = _fetchTopBanner();
    _bottomQuoteFuture = _fetchBottomQuotes();
    _virtusaDocsFuture = _fetchVirtusaDocs();
  }

  Future<Map<String, dynamic>?> _fetchTopBanner() async {
    try {
      final response = await supabase
          .from('top_banner')
          .select()
          .limit(1)
          .maybeSingle();
      return response;
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchBottomQuotes() async {
    try {
      final response = await supabase
          .from('bottom_quote')
          .select()
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchVirtusaDocs() async {
    try {
      final response = await supabase
          .from('sessions_documents')
          .select()
          .eq('client_name', widget.clientId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchMoments() {
    var query = supabase
        .from('moments')
        .select()
        .eq('client_name', widget.clientId);

    if (_selectedCategory != 'All') {
      query = query.eq('category', _selectedCategory);
    }

    return query.order('created_at', ascending: false);
  }

  void _onCategorySelected(String category) {
    if (_selectedCategory == category) return;
    setState(() {
      _selectedCategory = category;
      _momentsFuture = _fetchMoments();
    });
  }

  void _scrollToSection(GlobalKey key) {
    final context = key.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOut,
        alignment: 0.05,
      );
    }
  }

  void _openDocumentModal(
    BuildContext context,
    String title,
    String fileUrl,
    String fileType,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (context) {
        final double width = MediaQuery.of(context).size.width;
        final double dialogWidth = width > 900 ? 850 : width * 0.94;

        final String viewId =
            'doc-viewer-${DateTime.now().millisecondsSinceEpoch}';
        final String lowerType = fileType.toLowerCase();
        final bool isPptx = lowerType == 'pptx' || lowerType == 'ppt';

        String previewUrl = fileUrl;
        if (isPptx && !fileUrl.contains('officeapps.live.com')) {
          previewUrl =
              'https://view.officeapps.live.com/op/view.aspx?src=${Uri.encodeComponent(fileUrl)}';
        }

        ui_web.platformViewRegistry.registerViewFactory(viewId, (int viewId) {
          final iframe = html.IFrameElement()
            ..src = previewUrl
            ..style.border = 'none'
            ..style.width = '100%'
            ..style.height = '100%';
          return iframe;
        });

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            width: dialogWidth,
            height: MediaQuery.of(context).size.height * 0.85,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  color: const Color(0xFF1B5E20),
                  child: Row(
                    children: [
                      Icon(
                        isPptx
                            ? Icons.slideshow_rounded
                            : Icons.picture_as_pdf_rounded,
                        color: const Color(0xFF81C784),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Expanded(child: HtmlElementView(viewType: viewId)),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openVideoModal(
    BuildContext context,
    String youtubeUrl,
    String title,
    String description,
  ) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (context) {
        return _VideoPlayerDialog(
          youtubeUrl: youtubeUrl,
          title: title,
          description: description,
        );
      },
    );
  }

  void _openLightbox(BuildContext context, String imageUrl, String caption) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              InteractiveViewer(
                clipBehavior: Clip.none,
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(
                      Icons.broken_image,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
              if (caption.isNotEmpty)
                Positioned(
                  bottom: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Text(
                      caption,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _downloadMedia(BuildContext context, String url) async {
    if (url.isEmpty) return;

    try {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Downloading photo...'),
          duration: Duration(seconds: 2),
        ),
      );

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final base64Image = base64Encode(bytes);
        final dataUrl = 'data:image/jpeg;base64,$base64Image';
        final fileName =
            'hnb_memory_${DateTime.now().millisecondsSinceEpoch}.jpg';

        final anchor = html.AnchorElement(href: dataUrl)
          ..setAttribute('download', fileName)
          ..style.display = 'none';

        html.document.body?.children.add(anchor);
        anchor.click();
        html.document.body?.children.remove(anchor);

        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Downloaded successfully! Check your Downloads folder.',
            ),
            backgroundColor: Color(0xFF2E7D32),
          ),
        );
      } else {
        throw Exception('HTTP Error ${response.statusCode}');
      }
    } catch (e) {
      final fileName =
          'hnb_memory_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName);

      html.document.body?.children.add(anchor);
      anchor.click();
      html.document.body?.children.remove(anchor);
    }
  }

  void _handleLogout() {
    UserProfileData.clearStorage();
    if (mounted) {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;
    final crossAxisCount = width > 1100 ? 3 : (width > 650 ? 2 : 1);

    final String displayName = widget.userProfile.username;
    final String? photoUrl = widget.userProfile.photoUrl;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            expandedHeight: isMobile ? 380 : 400,
            pinned: true,
            backgroundColor: const Color(0xFF1B5E20),
            leading: IconButton(
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
              tooltip: 'Logout',
              onPressed: _handleLogout,
            ),
            title: Text(
              'Welcome, $displayName • Cherished Memories ✨',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            centerTitle: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(bottom: 12),
              background: Stack(
                children: [
                  const Positioned.fill(child: _AnimatedBannerBackground()),
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 12 : 28,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.25),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF81C784).withOpacity(0.6),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.verified_user,
                                  size: 12,
                                  color: Color(0xFF81C784),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Signed in as ${widget.userProfile.email}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // DYNAMIC LOGO / AVATAR FETCHED FROM top_banner TABLE
                        FutureBuilder<Map<String, dynamic>?>(
                          future: _topBannerFuture,
                          builder: (context, snapshot) {
                            final logoUrl = snapshot.data?['logo_url'];
                            final hasCustomLogo =
                                logoUrl != null &&
                                logoUrl.toString().trim().isNotEmpty;

                            return Center(
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFF81C784),
                                      Color(0xFF4CAF50),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 14,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                padding: const EdgeInsets.all(3),
                                child: CircleAvatar(
                                  radius: isMobile ? 36 : 42,
                                  backgroundColor: Colors.white,
                                  backgroundImage: hasCustomLogo
                                      ? NetworkImage(logoUrl)
                                      : ((photoUrl != null &&
                                                photoUrl.isNotEmpty)
                                            ? NetworkImage(photoUrl)
                                            : null),
                                  child:
                                      (!hasCustomLogo &&
                                          (photoUrl == null ||
                                              photoUrl.isEmpty))
                                      ? Text(
                                          displayName.isNotEmpty
                                              ? displayName[0].toUpperCase()
                                              : 'H',
                                          style: TextStyle(
                                            color: const Color(0xFF2E7D32),
                                            fontSize: isMobile ? 26 : 32,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 8),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🎉 ', style: TextStyle(fontSize: 18)),
                            Flexible(
                              child: Text(
                                'Welcome, $displayName',
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: isMobile ? 20 : 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.verified,
                              size: 16,
                              color: Color(0xFF81C784),
                            ),
                            const Text(' ✨', style: TextStyle(fontSize: 16)),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // TOP LINE BANNER - FETCHED FROM top_banner TABLE
                        FutureBuilder<Map<String, dynamic>?>(
                          future: _topBannerFuture,
                          builder: (context, snapshot) {
                            final bannerData = snapshot.data;
                            final bannerText =
                                bannerData?['banner_text'] ??
                                '✨ HNB OFFICIAL CLIENT VISIT • 16-10-2026 ✨';

                            return Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                  ),
                                ),
                                child: Text(
                                  bannerText,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFE8F5E9),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.0,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 14),

                        // TOP CTAS: Photos, Videos, Virtusa Sessions (Hidden when documents empty)
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _virtusaDocsFuture,
                          builder: (context, snapshot) {
                            final docsList = snapshot.data ?? [];
                            final hasVirtusaDocs = docsList.isNotEmpty;

                            return Center(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _BannerNavButton(
                                    icon: Icons.photo_library_rounded,
                                    label: 'Photos',
                                    onTap: () => _scrollToSection(_photosKey),
                                    isHighlight: true,
                                  ),
                                  _BannerNavButton(
                                    icon: Icons.videocam_rounded,
                                    label: 'Videos',
                                    onTap: () => _scrollToSection(_videosKey),
                                    isHighlight: true,
                                  ),
                                  if (hasVirtusaDocs)
                                    _BannerNavButton(
                                      icon: Icons.description_rounded,
                                      label: 'Virtusa Sessions',
                                      isHighlight: true,
                                      onTap: () =>
                                          _scrollToSection(_virtusaKey),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 14),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: const [
                            Icon(
                              Icons.ads_click_rounded,
                              size: 11,
                              color: Color(
                                0xFFA5D6A7,
                              ), // Soft mint green for contrast
                            ),
                            SizedBox(width: 5),
                            Text(
                              'Tap above for quick access',
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.2,
                                color: Colors.white, // Pure crisp white
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // -----------------------------------------------------------------
          // SECTION 1: EVENT HIGHLIGHTS CAROUSEL
          // -----------------------------------------------------------------
          SliverToBoxAdapter(
            key: _highlightsKey,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 18 : 28,
                28,
                isMobile ? 18 : 28,
                14,
              ),
              child: const _SectionHeader(
                icon: Icons.star_rounded,
                title: 'Featured Event Highlights',
                subtitle: 'Curated milestones & key event moments',
              ),
            ),
          ),

          FutureBuilder<List<Map<String, dynamic>>>(
            future: supabase
                .from('event_highlights')
                .select()
                .order('display_order', ascending: true),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                );
              }
              final highlights = snapshot.data ?? [];
              if (highlights.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Text(
                      'No highlights curated yet.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                );
              }

              return SliverToBoxAdapter(
                child: _HighlightsCarousel(
                  highlights: highlights,
                  isMobile: isMobile,
                ),
              );
            },
          ),

          // -----------------------------------------------------------------
          // SECTION 2: PHOTOS GALLERY & POSTERS
          // -----------------------------------------------------------------
          SliverToBoxAdapter(
            key: _photosKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    isMobile ? 18 : 28,
                    32,
                    isMobile ? 18 : 28,
                    10,
                  ),
                  child: const _SectionHeader(
                    icon: Icons.photo_library_rounded,
                    title: 'Photos Gallery & Posters',
                    subtitle: 'Captured photos & commemorative posters',
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 18 : 28,
                    vertical: 6,
                  ),
                  child: Row(
                    children: _categories.map((category) {
                      final isSelected = _selectedCategory == category;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          selected: isSelected,
                          label: Text(
                            category,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected
                                  ? Colors.white
                                  : const Color(0xFF1B5E20),
                            ),
                          ),
                          selectedColor: const Color(0xFF2E7D32),
                          backgroundColor: Colors.white,
                          checkmarkColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected
                                  ? const Color(0xFF2E7D32)
                                  : const Color(0xFF81C784).withOpacity(0.5),
                            ),
                          ),
                          onSelected: (_) => _onCategorySelected(category),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),

          FutureBuilder<List<Map<String, dynamic>>>(
            future: _momentsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                );
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Center(
                      child: Text(
                        'No photo memories found under "$_selectedCategory".',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: isMobile ? 1.2 : 1.3,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final data = list[index];
                    return _BeautifiedPhotoCard(
                      index: index,
                      momentData: data,
                      userEmail: widget.userProfile.email,
                      onTap: () => _openLightbox(
                        context,
                        data['media_url'] ?? '',
                        data['comment'] ?? '',
                      ),
                      onDownload: () =>
                          _downloadMedia(context, data['media_url'] ?? ''),
                    );
                  }, childCount: list.length),
                ),
              );
            },
          ),

          // -----------------------------------------------------------------
          // SECTION 3: EXCLUSIVE VIDEOS GALLERY
          // -----------------------------------------------------------------
          SliverToBoxAdapter(
            key: _videosKey,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                isMobile ? 18 : 28,
                32,
                isMobile ? 18 : 28,
                14,
              ),
              child: const _SectionHeader(
                icon: Icons.video_collection_rounded,
                title: 'Exclusive Videos Gallery',
                subtitle: 'Flashmobs, celebrations & video showcases',
              ),
            ),
          ),

          FutureBuilder<List<Map<String, dynamic>>>(
            future: supabase
                .from('videos')
                .select()
                .eq('client_name', widget.clientId)
                .order('created_at', ascending: false),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 180,
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                );
              }
              final videos = snapshot.data ?? [];
              if (videos.isEmpty) {
                return const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    child: Text(
                      'No videos uploaded yet.',
                      style: TextStyle(
                        color: Colors.grey,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 24),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: isMobile ? 1.2 : 1.3,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final video = videos[index];
                    final youtubeUrl = video['youtube_url'] ?? '';
                    final title = video['title'] ?? 'HNB Highlight Video';
                    final description =
                        video['description'] ?? 'Flashmobs & Special Events';

                    return _VideoThumbnailCard(
                      index: index,
                      youtubeUrl: youtubeUrl,
                      title: title,
                      description: description,
                      onTap: () => _openVideoModal(
                        context,
                        youtubeUrl,
                        title,
                        description,
                      ),
                    );
                  }, childCount: videos.length),
                ),
              );
            },
          ),

          // -----------------------------------------------------------------
          // SECTION 4: VIRTUSA SESSIONS (HANDLES PPTX & PDF FILES)
          // -----------------------------------------------------------------
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _virtusaDocsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }

              final docs = snapshot.data ?? [];

              if (docs.isEmpty) {
                return const SliverToBoxAdapter(child: SizedBox.shrink());
              }

              return SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    key: _virtusaKey,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        isMobile ? 18 : 28,
                        32,
                        isMobile ? 18 : 28,
                        14,
                      ),
                      child: const _SectionHeader(
                        icon: Icons.topic_rounded,
                        title: 'Virtusa Sessions Documents',
                        subtitle: 'Executive presentation decks (PPTX) & technical PDFs',
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 16 : 24,
                    ),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossAxisCount,
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: isMobile ? 2.2 : 2.5,
                      ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final doc = docs[index];
                        final title = doc['title'] ?? 'Virtusa Session File';
                        final fileType = (doc['file_type'] ?? 'pptx')
                            .toString()
                            .toLowerCase();
                        final fileUrl = doc['file_url'] ?? '';

                        final bool isPptx =
                            fileType == 'pptx' || fileType == 'ppt';

                        return Card(
                          elevation: 3,
                          shadowColor: Colors.black12,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: const Color(0xFF81C784).withOpacity(0.4),
                            ),
                          ),
                          child: InkWell(
                            onTap: () => _openDocumentModal(
                              context,
                              title,
                              fileUrl,
                              fileType,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isPptx
                                          ? Colors.orange.shade50
                                          : Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      isPptx
                                          ? Icons.slideshow_rounded
                                          : Icons.picture_as_pdf_rounded,
                                      color: isPptx
                                          ? Colors.orange.shade800
                                          : Colors.red,
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Color(0xFF1B5E20),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade200,
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                fileType.toUpperCase(),
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.black87,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'Tap to view file',
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.open_in_new_rounded,
                                    size: 18,
                                    color: Color(0xFF2E7D32),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }, childCount: docs.length),
                    ),
                  ),
                ],
              );
            },
          ),

          // -----------------------------------------------------------------
          // SECTION 5: BOTTOM QUOTES
          // -----------------------------------------------------------------
          SliverToBoxAdapter(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _bottomQuoteFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  );
                }

                final quotesList = snapshot.data ?? [];

                if (quotesList.isEmpty) {
                  return const SizedBox.shrink();
                }

                return Container(
                  margin: EdgeInsets.fromLTRB(
                    isMobile ? 16 : 24,
                    32,
                    isMobile ? 16 : 24,
                    48,
                  ),
                  padding: EdgeInsets.all(isMobile ? 18 : 28),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE0E0E0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.format_quote_rounded,
                        size: 32,
                        color: Color(0xFF81C784),
                      ),
                      const SizedBox(height: 8),

                      for (int i = 0; i < quotesList.length; i++) ...[
                        if (i > 0) ...[
                          const SizedBox(height: 16),
                          const Divider(color: Color(0xFFE0E0E0)),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          quotesList[i]['quote_text'] ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1B5E20),
                            height: 1.4,
                          ),
                        ),
                        if (quotesList[i]['author_or_subtext'] != null &&
                            quotesList[i]['author_or_subtext']
                                .toString()
                                .isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            '- ${quotesList[i]['author_or_subtext']}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ],

                      const SizedBox(height: 14),
                      const Divider(color: Color(0xFFE0E0E0)),
                      const SizedBox(height: 10),
                      Text(
                        '© 2026 HNB Cherished Memories. All rights reserved.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Nav Button Component
class _BannerNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isHighlight;
  final VoidCallback onTap;

  const _BannerNavButton({
    required this.icon,
    required this.label,
    this.isHighlight = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: isHighlight
                  ? [
                      const Color(0xFF81C784).withOpacity(0.50),
                      const Color(0xFF4CAF50).withOpacity(0.60),
                    ]
                  : [
                      Colors.white.withOpacity(0.20),
                      Colors.white.withOpacity(0.10),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(
              color: isHighlight
                  ? const Color(0xFFA5D6A7)
                  : Colors.white.withOpacity(0.35),
              width: 1.1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isHighlight ? Colors.white : const Color(0xFFA5D6A7),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VIDEO THUMBNAIL CARD & MODAL
// ---------------------------------------------------------------------------
class _VideoThumbnailCard extends StatefulWidget {
  final int index;
  final String youtubeUrl;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _VideoThumbnailCard({
    required this.index,
    required this.youtubeUrl,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  State<_VideoThumbnailCard> createState() => _VideoThumbnailCardState();
}

class _VideoThumbnailCardState extends State<_VideoThumbnailCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final videoId =
        YoutubePlayerController.convertUrlToId(widget.youtubeUrl) ?? '';
    final thumbnailUrl = videoId.isNotEmpty
        ? 'https://img.youtube.com/vi/$videoId/hqdefault.jpg'
        : '';

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        transform: _isHovered
            ? (Matrix4.identity()..translate(0, -3, 0))
            : Matrix4.identity(),
        child: Card(
          elevation: _isHovered ? 6 : 3,
          shadowColor: Colors.black12,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: const Color(0xFF81C784).withOpacity(0.3),
              width: 1,
            ),
          ),
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      thumbnailUrl.isNotEmpty
                          ? Image.network(
                              thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: Colors.black12),
                            )
                          : Container(color: Colors.black12),
                      Container(color: Colors.black.withOpacity(0.25)),
                      Center(
                        child: AnimatedScale(
                          scale: _isHovered ? 1.10 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: Color(0xFF2E7D32),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 26,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VideoPlayerDialog extends StatefulWidget {
  final String youtubeUrl;
  final String title;
  final String description;

  const _VideoPlayerDialog({
    required this.youtubeUrl,
    required this.title,
    required this.description,
  });

  @override
  State<_VideoPlayerDialog> createState() => _VideoPlayerDialogState();
}

class _VideoPlayerDialogState extends State<_VideoPlayerDialog> {
  YoutubePlayerController? _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    final videoId =
        YoutubePlayerController.convertUrlToId(widget.youtubeUrl) ?? '';
    if (videoId.isNotEmpty) {
      _controller = YoutubePlayerController.fromVideoId(
        videoId: videoId,
        autoPlay: true,
        params: const YoutubePlayerParams(
          showControls: true,
          showFullscreenButton: true,
          mute: false,
          strictRelatedVideos: true,
        ),
      );

      _controller?.listen((value) {
        if (value.playerState == PlayerState.playing ||
            value.playerState == PlayerState.cued) {
          if (mounted && _isLoading) {
            setState(() {
              _isLoading = false;
            });
          }
        }
      });

      Future.delayed(const Duration(milliseconds: 3000), () {
        if (mounted && _isLoading) {
          setState(() {
            _isLoading = false;
          });
        }
      });
    } else {
      _isLoading = false;
    }
  }

  @override
  void dispose() {
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final dialogWidth = width > 800 ? 760.0 : width * 0.92;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Center(
        child: Container(
          width: dialogWidth,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                color: const Color(0xFF1B5E20),
                child: Row(
                  children: [
                    const Icon(
                      Icons.play_circle_fill_rounded,
                      color: Color(0xFF81C784),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _controller != null
                        ? YoutubePlayer(controller: _controller!)
                        : Container(
                            color: Colors.black,
                            child: const Center(
                              child: Text(
                                'Invalid Video URL',
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ),
                          ),
                    if (_isLoading)
                      AnimatedOpacity(
                        opacity: _isLoading ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          color: const Color(0xFF0F172A),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                color: Color(0xFF81C784),
                                strokeWidth: 3,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Loading Video...',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.description.isNotEmpty)
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(14.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
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
}

// ---------------------------------------------------------------------------
// DATABASE-BACKED PHOTO CARD WITH USER LIKES & LIGHTBOX ON TAP
// ---------------------------------------------------------------------------
class _BeautifiedPhotoCard extends StatefulWidget {
  final int index;
  final Map<String, dynamic> momentData;
  final String userEmail;
  final VoidCallback onTap;
  final VoidCallback onDownload;

  const _BeautifiedPhotoCard({
    required this.index,
    required this.momentData,
    required this.userEmail,
    required this.onTap,
    required this.onDownload,
  });

  @override
  State<_BeautifiedPhotoCard> createState() => _BeautifiedPhotoCardState();
}

class _BeautifiedPhotoCardState extends State<_BeautifiedPhotoCard>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  late AnimationController _heartAnimController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _heartScaleAnimation;

  bool _isLiked = false;
  bool _isHovered = false;
  int _likesCount = 0;
  bool _isLikingProcess = false;

  @override
  void initState() {
    super.initState();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _heartAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _heartScaleAnimation =
        TweenSequence<double>([
          TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.4), weight: 50),
          TweenSequenceItem(tween: Tween(begin: 1.4, end: 1.0), weight: 50),
        ]).animate(
          CurvedAnimation(
            parent: _heartAnimController,
            curve: Curves.easeInOut,
          ),
        );

    _fetchLikesData();

    Future.delayed(
      Duration(milliseconds: (widget.index * 60).clamp(0, 600)),
      () {
        if (mounted) _animController.forward();
      },
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _heartAnimController.dispose();
    super.dispose();
  }

  Future<void> _fetchLikesData() async {
    final momentId = widget.momentData['id'];
    if (momentId == null) return;

    try {
      final likesResponse = await supabase
          .from('moment_likes')
          .select('id')
          .eq('moment_id', momentId);

      final totalCount = (likesResponse as List).length;

      final userLikeResponse = await supabase
          .from('moment_likes')
          .select()
          .eq('moment_id', momentId)
          .eq('user_email', widget.userEmail)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _likesCount = totalCount;
          _isLiked = userLikeResponse != null;
        });
      }
    } catch (_) {}
  }

  Future<void> _toggleLike() async {
    if (_isLikingProcess) return;
    _isLikingProcess = true;

    _heartAnimController.forward(from: 0.0);

    final momentId = widget.momentData['id'];
    if (momentId == null) {
      _isLikingProcess = false;
      return;
    }

    final wasLiked = _isLiked;
    setState(() {
      _isLiked = !_isLiked;
      _likesCount += _isLiked ? 1 : -1;
      if (_likesCount < 0) _likesCount = 0;
    });

    try {
      if (wasLiked) {
        await supabase
            .from('moment_likes')
            .delete()
            .eq('moment_id', momentId)
            .eq('user_email', widget.userEmail);
      } else {
        await supabase.from('moment_likes').insert({
          'moment_id': momentId,
          'user_email': widget.userEmail,
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLiked = wasLiked;
          _likesCount += wasLiked ? 1 : -1;
        });
      }
    } finally {
      _isLikingProcess = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaUrl = widget.momentData['media_url'] ?? '';
    final comment = widget.momentData['comment'] ?? '';

    return FadeTransition(
      opacity: _fadeAnimation,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          transform: _isHovered
              ? (Matrix4.identity()..translate(0, -3, 0))
              : Matrix4.identity(),
          child: Card(
            elevation: _isHovered ? 6 : 3,
            shadowColor: Colors.black12,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: const Color(0xFF81C784).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: InkWell(
                    onTap: widget.onTap,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: Icon(
                                Icons.broken_image,
                                size: 36,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.25),
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 11,
                                  color: Color(0xFF81C784),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Moment',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(10, 24, 10, 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withOpacity(0.75),
                                  Colors.transparent,
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                            ),
                            child: Text(
                              comment.isNotEmpty
                                  ? comment
                                  : 'Cherished memory from HNB visit ✨',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.white,
                  child: Row(
                    children: [
                      InkWell(
                        onTap: _toggleLike,
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 2,
                            horizontal: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ScaleTransition(
                                scale: _heartScaleAnimation,
                                child: Icon(
                                  _isLiked
                                      ? Icons.favorite
                                      : Icons.favorite_border_rounded,
                                  size: 18,
                                  color: _isLiked
                                      ? Colors.redAccent
                                      : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '$_likesCount',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: _isLiked
                                      ? Colors.redAccent
                                      : Colors.grey.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: widget.onDownload,
                        icon: const Icon(Icons.download, size: 11),
                        label: const Text(
                          'Download',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OTHER UI HELPER COMPONENTS
// ---------------------------------------------------------------------------

class _AnimatedBannerBackground extends StatefulWidget {
  const _AnimatedBannerBackground();

  @override
  State<_AnimatedBannerBackground> createState() =>
      _AnimatedBannerBackgroundState();
}

class _AnimatedBannerBackgroundState extends State<_AnimatedBannerBackground>
    with TickerProviderStateMixin {
  late AnimationController _motionController;
  late AnimationController _flashController;
  late Animation<double> _floatAnim;
  late Animation<double> _pulseAnim;
  late Animation<double> _flashAnim;

  @override
  void initState() {
    super.initState();

    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);

    _floatAnim = Tween<double>(begin: -8.0, end: 12.0).animate(
      CurvedAnimation(parent: _motionController, curve: Curves.easeInOut),
    );

    _pulseAnim = Tween<double>(begin: 0.90, end: 1.10).animate(
      CurvedAnimation(parent: _motionController, curve: Curves.easeInOut),
    );

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _flashAnim = Tween<double>(
      begin: -1.5,
      end: 2.5,
    ).animate(CurvedAnimation(parent: _flashController, curve: Curves.linear));
  }

  @override
  void dispose() {
    _motionController.dispose();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20), Color(0xFF0D3B12)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          AnimatedBuilder(
            animation: _motionController,
            builder: (context, child) {
              final floatVal = _floatAnim.value;
              final scaleVal = _pulseAnim.value;

              return Stack(
                children: [
                  Positioned(
                    top: -20 + floatVal,
                    right: -20,
                    child: Transform.scale(
                      scale: scaleVal,
                      child: Container(
                        width: 170,
                        height: 170,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 70 + floatVal,
                    left: -30,
                    child: Transform.scale(
                      scale: 2.0 * scaleVal,
                      child: Container(
                        width: 130,
                        height: 130,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF81C784).withOpacity(0.14),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -20 + floatVal,
                    right: 40,
                    child: Transform.scale(
                      scale: scaleVal,
                      child: Container(
                        width: 140,
                        height: 140,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.06),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 30 + (floatVal * 0.5),
                    left: 25,
                    child: Transform.scale(
                      scale: scaleVal,
                      child: const Text('⭐', style: TextStyle(fontSize: 17)),
                    ),
                  ),
                  Positioned(
                    top: 60 - (floatVal * 0.5),
                    right: 35,
                    child: Transform.scale(
                      scale: scaleVal,
                      child: const Text('✨', style: TextStyle(fontSize: 19)),
                    ),
                  ),
                  Positioned(
                    bottom: 70 + floatVal,
                    left: 20,
                    child: Transform.scale(
                      scale: scaleVal,
                      child: const Text('🌟', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  Positioned(
                    bottom: 40 + floatVal,
                    right: 25,
                    child: Transform.scale(
                      scale: scaleVal,
                      child: const Text('✨', style: TextStyle(fontSize: 17)),
                    ),
                  ),
                ],
              );
            },
          ),
          AnimatedBuilder(
            animation: _flashController,
            builder: (context, child) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment(_flashAnim.value - 1, -0.5),
                    end: Alignment(_flashAnim.value, 0.5),
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  State<_SectionHeader> createState() => _SectionHeaderState();
}

class _SectionHeaderState extends State<_SectionHeader>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            ScaleTransition(
              scale: _scaleAnimation,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFA5D6A7), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF81C784).withOpacity(0.3),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Icon(
                  widget.icon,
                  color: const Color(0xFF2E7D32),
                  size: 18,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1B5E20),
                      letterSpacing: -0.2,
                    ),
                  ),
                  Text(
                    widget.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          height: 2,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(1),
            gradient: LinearGradient(
              colors: [
                const Color(0xFF2E7D32),
                const Color(0xFF81C784).withOpacity(0.4),
                Colors.transparent,
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
          ),
        ),
      ],
    );
  }
}

class _HighlightsCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> highlights;
  final bool isMobile;

  const _HighlightsCarousel({required this.highlights, required this.isMobile});

  @override
  State<_HighlightsCarousel> createState() => _HighlightsCarouselState();
}

class _HighlightsCarouselState extends State<_HighlightsCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      viewportFraction: widget.isMobile ? 0.92 : 0.82,
      initialPage: 0,
    );

    _timer = Timer.periodic(const Duration(seconds: 4), (timer) {
      if (!mounted || widget.highlights.isEmpty || _isHovered) return;

      if (_currentPage < widget.highlights.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: SizedBox(
        height: widget.isMobile ? 250 : 300,
        child: PageView.builder(
          controller: _pageController,
          itemCount: widget.highlights.length,
          onPageChanged: (index) => setState(() => _currentPage = index),
          itemBuilder: (context, index) {
            final item = widget.highlights[index];

            return AnimatedBuilder(
              animation: _pageController,
              builder: (context, child) {
                double value = 1.0;
                if (_pageController.position.haveDimensions) {
                  value = (_pageController.page! - index).abs();
                  value = (1 - (value * 0.12)).clamp(0.88, 1.0);
                }
                return Transform.scale(scale: value, child: child);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 4.0,
                ),
                child: Card(
                  elevation: 4,
                  shadowColor: Colors.black12,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: const Color(0xFF81C784).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        item['image_url'] ?? '',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.broken_image,
                            size: 40,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.black.withOpacity(0.8),
                                Colors.transparent,
                              ],
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                item['title'] ?? 'Key Milestone',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item['description'] ??
                                    'HNB Official Visit Highlight',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
