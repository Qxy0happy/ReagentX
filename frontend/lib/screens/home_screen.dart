import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/inquiry_provider.dart';

class HomeScreen extends StatefulWidget {
  final Widget child;
  const HomeScreen({super.key, required this.child});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshBadge();
  }

  void _refreshBadge() {
    final auth = context.read<AuthProvider>();
    if (auth.isLoggedIn) {
      context.read<InquiryProvider>().fetchPendingCount(auth.userId);
    } else {
      context.read<InquiryProvider>().clear();
    }
  }


  int _currentIndex(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/search')) return 0;
    if (location.startsWith('/publish')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex(context),
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/search');
            case 1: context.go('/publish');
            case 2: context.go('/profile');
          }
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.search), label: '搜索'),
          const NavigationDestination(icon: Icon(Icons.add_circle_outline), label: '发布'),
          NavigationDestination(
            icon: Consumer<InquiryProvider>(
              builder: (_, ip, __) => ip.pendingCount > 0
                  ? Badge(
                      label: Text('${ip.pendingCount}'),
                      isLabelVisible: true,
                      child: const Icon(Icons.person_outline),
                    )
                  : const Icon(Icons.person_outline),
            ),
            selectedIcon: Consumer<InquiryProvider>(
              builder: (_, ip, __) => ip.pendingCount > 0
                  ? Badge(
                      label: Text('${ip.pendingCount}'),
                      isLabelVisible: true,
                      child: const Icon(Icons.person),
                    )
                  : const Icon(Icons.person),
            ),
            label: '我的',
          ),
        ],
      ),
    );
  }
}
