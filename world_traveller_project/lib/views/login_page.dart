import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:world_traveller_project/main.dart';
import 'package:world_traveller_project/providers/social_controller.dart';
import 'package:world_traveller_project/services/profile_service.dart';

enum _FormStatus { neutral, error, success }

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  /// The form shows the name fields only while signing up.
  bool _isSignUpMode = false;

  String? _emailError;
  String? _passwordError;
  String? _firstNameError;
  String? _lastNameError;

  /// Error that does not belong to a single field (network problems, ...),
  /// shown as a banner above the buttons.
  String? _generalError;

  _FormStatus _status = _FormStatus.neutral;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Color _borderColor(ThemeData theme) {
    switch (_status) {
      case _FormStatus.error:
        return theme.colorScheme.error;
      case _FormStatus.success:
        return Colors.green.shade500;
      case _FormStatus.neutral:
        return Colors.transparent;
    }
  }

  void _clearFieldError(String field) {
    if (field == 'email' && _emailError != null) {
      setState(() => _emailError = null);
    } else if (field == 'password' && _passwordError != null) {
      setState(() => _passwordError = null);
    } else if (field == 'firstName' && _firstNameError != null) {
      setState(() => _firstNameError = null);
    } else if (field == 'lastName' && _lastNameError != null) {
      setState(() => _lastNameError = null);
    }
  }

  /// Checks the fields BEFORE contacting Supabase. Without this, sending an
  /// empty form is read by the server as an anonymous login attempt (which
  /// is disabled here), producing a confusing error message.
  bool _validateFields({required bool requireName}) {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    String? emailError;
    String? passwordError;
    String? firstNameError;
    String? lastNameError;

    if (email.isEmpty) {
      emailError = 'Enter your email address.';
    } else if (!email.contains('@') || !email.contains('.')) {
      emailError = 'Enter a valid email address.';
    }

    if (password.isEmpty) {
      passwordError = 'Enter your password.';
    } else if (password.length < 6) {
      passwordError = 'At least 6 characters.';
    }

    if (requireName) {
      if (firstName.isEmpty) {
        firstNameError = 'Enter your first name.';
      }
      if (lastName.isEmpty) {
        lastNameError = 'Enter your last name.';
      }
    }

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _firstNameError = firstNameError;
      _lastNameError = lastNameError;
      _generalError = null;
      _status = (emailError != null ||
              passwordError != null ||
              firstNameError != null ||
              lastNameError != null)
          ? _FormStatus.error
          : _FormStatus.neutral;
    });

    return emailError == null &&
        passwordError == null &&
        firstNameError == null &&
        lastNameError == null;
  }

  /// Tries to attach the error coming back from Supabase to the right field,
  /// so the user immediately sees where to fix things.
  void _handleAuthError(Object error) {
    String? emailError;
    String? passwordError;
    String? generalError;

    if (error is AuthWeakPasswordException) {
      passwordError = 'The password must be at least 6 characters long.';
    } else if (error is AuthException) {
      final raw = error.message.toLowerCase();

      if (raw.contains('already registered') || raw.contains('already exists')) {
        emailError = 'This email address is already registered.';
      } else if (raw.contains('invalid login credentials')) {
        // For security reasons Supabase does not say whether the email or
        // the password was wrong, so we flag it under the password.
        passwordError = 'Wrong email or password.';
      } else if (raw.contains('email') && raw.contains('invalid')) {
        emailError = 'Invalid email address.';
      } else if (raw.contains('password')) {
        passwordError = error.message;
      } else {
        generalError = error.message;
      }
    } else if (error is PostgrestException) {
      // The account itself was created fine, but saving the row in
      // "profiles" failed (a database constraint, a permissions rule,
      // ...). Showing the real message — instead of a generic banner —
      // is what let us actually find and fix the missing-username bug
      // this exact error was hiding.
      generalError = 'Account created, but the profile could not be saved: '
          '${error.message}';
    } else {
      generalError = 'Something went wrong: $error';
    }

    setState(() {
      _emailError = emailError;
      _passwordError = passwordError;
      _generalError = generalError;
      _status = _FormStatus.error;
    });
  }

  Future<void> _signUp() async {
    // First tap on "Sign up" only reveals the name fields, so people
    // never create an account without a name attached to it.
    if (!_isSignUpMode) {
      setState(() {
        _isSignUpMode = true;
        _status = _FormStatus.neutral;
        _generalError = null;
      });
      return;
    }

    if (!_validateFields(requireName: true)) return;

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();

    setState(() => _isLoading = true);
    try {
      final profileService = ProfileService();

      final response = await supabase.auth.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
        data: {'first_name': firstName, 'last_name': lastName},
      );

      final newUser = response.user;
      if (newUser != null) {
        // The profiles row is normally created by a database trigger
        // (see 00_new_project_fix.sql), which runs with its own
        // permissions and always succeeds. This call is only a shortcut
        // so the name is saved without waiting for a refresh.
        //
        // When "Confirm email" is switched on in Supabase there is no
        // session yet at this exact point (auth.uid() is still null),
        // so this specific call is REJECTED by Row Level Security even
        // though the trigger already created the row correctly. That
        // is expected, not a real failure, so it must not be shown to
        // the person as an error — only genuine problems should be.
        try {
          await profileService.saveProfile(
            userId: newUser.id,
            firstName: firstName,
            lastName: lastName,
            email: _emailController.text.trim(),
          );
        } on PostgrestException catch (e) {
          debugPrint('Profile upsert skipped right after sign-up (expected '
              'before email confirmation): $e');
        }
      }

      if (!mounted) return;

      await context.read<SocialController>().refreshForCurrentUser();

      if (!mounted) return;

      setState(() {
        _status = _FormStatus.success;
        _generalError = null;
      });

      // When email confirmation is switched off in Supabase the user is
      // already signed in at this point, so we can go straight back.
      if (supabase.auth.currentUser != null) {
        Navigator.of(context).pop(true);
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account created! Confirm your email, then sign in.'),
        ),
      );
    } catch (e) {
      if (mounted) _handleAuthError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signIn() async {
    if (!_validateFields(requireName: false)) return;

    setState(() => _isLoading = true);
    try {
      await supabase.auth.signInWithPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      if (!mounted) return;

      final social = context.read<SocialController>();
      await social.refreshForCurrentUser();

      if (!mounted) return;

      // Accounts created before this profile shape existed get a
      // placeholder name now, so every picture can still show an author.
      //
      // A profile that looks "missing" right here can just as easily be
      // a slow connection or the sign-up trigger not having committed
      // yet as a genuinely old account — so this retries a couple of
      // times before giving up, and even then only ever CREATES a row
      // when none exists; it can never overwrite a name the person
      // already typed in, which is what used to make a real "First Last"
      // occasionally get replaced by a guessed one.
      if (social.myProfile == null) {
        for (var attempt = 0; attempt < 2 && social.myProfile == null; attempt++) {
          await Future.delayed(const Duration(milliseconds: 400));
          if (!mounted) return;
          await social.refreshForCurrentUser();
          if (!mounted) return;
        }

        if (social.myProfile == null) {
          final user = supabase.auth.currentUser;
          if (user != null) {
            await _createFallbackProfile(user);
            if (!mounted) return;
            await social.refreshForCurrentUser();
            if (!mounted) return;
          }
        }
      }

      // A blocked account never gets in: sign back out immediately and
      // explain why, instead of leaving them signed in with a read-only
      // app. They can still browse the public "General World" like any
      // signed-out visitor — just not add or edit anything.
      if (social.isCurrentUserBlocked) {
        await supabase.auth.signOut();
        if (!mounted) return;
        await social.refreshForCurrentUser();
        if (!mounted) return;
        setState(() {
          _status = _FormStatus.error;
          _generalError = 'This account has been blocked by the administrator '
              'for breaking the terms of use. You can still browse the public '
              'pictures, but you cannot sign in.';
        });
        return;
      }

      setState(() => _status = _FormStatus.success);
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _handleAuthError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createFallbackProfile(User user) async {
    final service = ProfileService();
    final base = (user.email ?? 'traveller').split('@').first;

    try {
      // insert-only (ignores the row if one already exists): a guessed
      // name from the email address must never replace a real one.
      await service.createProfileIfMissing(
        userId: user.id,
        firstName: base.isEmpty ? 'Traveller' : base,
        lastName: '',
        email: user.email,
      );
    } catch (e) {
      debugPrint('Could not create fallback profile: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = _borderColor(theme);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.colorScheme.primary,
              theme.colorScheme.primaryContainer,
            ],
          ),
        ),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned(
                top: 8,
                left: 8,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  tooltip: 'Cancel',
                  onPressed: () => Navigator.of(context).maybePop(false),
                ),
              ),
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: borderColor, width: 2),
                        boxShadow: const [
                          BoxShadow(
                            blurRadius: 24,
                            offset: Offset(0, 10),
                            color: Colors.black26,
                          ),
                        ],
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(32, 40, 32, 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: theme.colorScheme.primaryContainer,
                              child: Icon(
                                Icons.public,
                                size: 36,
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'World Traveller',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isSignUpMode
                                  ? 'Tell us your name — other travellers will see it'
                                  : 'Sign in to add or edit your memories',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (_isSignUpMode) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _firstNameController,
                                      textInputAction: TextInputAction.next,
                                      onChanged: (_) => _clearFieldError('firstName'),
                                      decoration: InputDecoration(
                                        labelText: 'First name',
                                        errorText: _firstNameError,
                                        prefixIcon: const Icon(Icons.badge_outlined),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: _lastNameController,
                                      textInputAction: TextInputAction.next,
                                      onChanged: (_) => _clearFieldError('lastName'),
                                      decoration: InputDecoration(
                                        labelText: 'Last name',
                                        errorText: _lastNameError,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'A unique ID is generated for you automatically, '
                                'in case another traveller has the same name.',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.hintColor),
                              ),
                              const SizedBox(height: 16),
                            ],
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => _clearFieldError('email'),
                              decoration: InputDecoration(
                                labelText: 'Email',
                                errorText: _emailError,
                                prefixIcon: const Icon(Icons.mail_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.done,
                              onChanged: (_) => _clearFieldError('password'),
                              onSubmitted: (_) =>
                                  _isSignUpMode ? _signUp() : _signIn(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                errorText: _passwordError,
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            if (_generalError != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      size: 18,
                                      color: theme.colorScheme.onErrorContainer,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _generalError!,
                                        style: TextStyle(
                                          color: theme.colorScheme.onErrorContainer,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),
                            if (_isLoading)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: CircularProgressIndicator(),
                              )
                            else ...[
                              if (!_isSignUpMode)
                                SizedBox(
                                  width: double.infinity,
                                  height: 48,
                                  child: FilledButton(
                                    onPressed: _signIn,
                                    style: FilledButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Sign in',
                                        style: TextStyle(fontSize: 16)),
                                  ),
                                ),
                              if (!_isSignUpMode) const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: _isSignUpMode
                                    ? FilledButton(
                                        onPressed: _signUp,
                                        style: FilledButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text('Create account',
                                            style: TextStyle(fontSize: 16)),
                                      )
                                    : OutlinedButton(
                                        onPressed: _signUp,
                                        style: OutlinedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text('Sign up',
                                            style: TextStyle(fontSize: 16)),
                                      ),
                              ),
                              if (_isSignUpMode) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () => setState(() {
                                    _isSignUpMode = false;
                                    _firstNameError = null;
                                    _lastNameError = null;
                                    _status = _FormStatus.neutral;
                                  }),
                                  child: const Text('I already have an account'),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
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




