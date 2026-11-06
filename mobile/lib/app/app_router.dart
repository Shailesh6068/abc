import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:racezone/core/constants/app_colors.dart';
import 'package:racezone/core/network/supabase_client.dart';
import 'package:racezone/features/auth/presentation/forgot_password_screen.dart';
import 'package:racezone/features/auth/presentation/login_screen.dart';
import 'package:racezone/features/auth/presentation/register_screen.dart';
import 'package:racezone/features/home/presentation/home_screen.dart';
import 'package:racezone/features/leaderboard/presentation/leaderboard_screen.dart';
import 'package:racezone/features/live_race/presentation/live_race_screen.dart';
import 'package:racezone/features/notifications/presentation/notifications_screen.dart';
import 'package:racezone/features/onboarding/presentation/onboarding_screen.dart';
import 'package:racezone/features/profile/presentation/profile_screen.dart';
import 'package:racezone/features/races/presentation/create_race_screen.dart';
import 'package:racezone/features/races/presentation/race_lobby_screen.dart';
import 'package:racezone/features/results/presentation/race_results_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const _SplashScreen(),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) => const LoginScreen(),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/onboarding',
      builder: (context, state) => const OnboardingScreen(),
    ),
    GoRoute(
      path: '/home',
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/create-race',
      builder: (context, state) {
        final challengeUser = state.uri.queryParameters['challengeUser'];
        final challengeName = state.uri.queryParameters['challengeName'];
        return CreateRaceScreen(
          challengeUserId: challengeUser,
          challengeUserName: challengeName,
        );
      },
    ),
    GoRoute(
      path: '/lobby/:raceId',
      builder: (context, state) {
        final raceId = state.pathParameters['raceId']!;
        return RaceLobbyScreen(raceId: raceId);
      },
    ),
    GoRoute(
      path: '/live-race/:raceId',
      builder: (context, state) {
        final raceId = state.pathParameters['raceId']!;
        return LiveRaceScreen(raceId: raceId);
      },
    ),
    GoRoute(
      path: '/results/:raceId',
      builder: (context, state) {
        final raceId = state.pathParameters['raceId']!;
        return RaceResultsScreen(raceId: raceId);
      },
    ),
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
    ),
    GoRoute(
      path: '/leaderboards',
      builder: (context, state) => const LeaderboardScreen(),
    ),
    GoRoute(
      path: '/notifications',
      builder: (context, state) => const NotificationsScreen(),
    ),
  ],
);

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();

  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    // Automatically establish/restore authenticated Supabase session
    await SupabaseService.ensureAuthenticatedSession();

    if (mounted) {
      if (SupabaseService.isAuthenticated) {
        context.go('/home');
      } else {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.primaryGreen, width: 2),
                boxShadow: [
                  BoxShadow(color: AppColors.primaryGreen.withValues(alpha: 0.3), blurRadius: 20),
                ],
              ),
              child: const Icon(Icons.flash_on, color: AppColors.primaryGreen, size: 54),
            ),
            const SizedBox(height: 24),
            const Text(
              'RaceZone',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              'REAL-TIME GPS RACING',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, color: AppColors.primaryGreen),
            ),
            const SizedBox(height: 36),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primaryGreen),
            ),
          ],
        ),
      ),
    );
  }
}
