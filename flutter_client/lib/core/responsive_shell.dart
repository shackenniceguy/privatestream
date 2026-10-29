import 'package:flutter/material.dart';
import 'package:privatestream/core/theme.dart';

enum DeviceLayoutCategory {
  verticalMobile,    // 9:16, 9:20 (aspectRatio < 0.7)
  foldableTablet,    // 3:4, 4:3, 1:1 (0.7 <= aspectRatio <= 1.2)
  widescreenDesktop, // 16:9, 16:10, 21:9 (aspectRatio > 1.2)
}

class ResponsiveLayout {
  static DeviceLayoutCategory getCategory(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final ratio = size.width / (size.height > 0 ? size.height : 1.0);

    if (ratio < 0.72) {
      return DeviceLayoutCategory.verticalMobile;
    } else if (ratio <= 1.25) {
      return DeviceLayoutCategory.foldableTablet;
    } else {
      return DeviceLayoutCategory.widescreenDesktop;
    }
  }

  static int getGridColumnCount(BuildContext context) {
    final cat = getCategory(context);
    final width = MediaQuery.of(context).size.width;

    switch (cat) {
      case DeviceLayoutCategory.verticalMobile:
        return width < 380 ? 2 : 3;
      case DeviceLayoutCategory.foldableTablet:
        return width < 700 ? 3 : 4;
      case DeviceLayoutCategory.widescreenDesktop:
        if (width >= 1600) return 6;
        if (width >= 1200) return 5;
        return 4;
    }
  }

  static double getCardAspectRatio(BuildContext context, {bool isVerticalMedia = false}) {
    if (isVerticalMedia) {
      return 9 / 16;
    }
    return 2 / 3; // Standard movie poster ratio
  }
}

class ResponsiveShell extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavigationChanged;
  final List<Widget> pages;
  final Widget? floatingActionButton;

  const ResponsiveShell({
    super.key,
    required this.currentIndex,
    required this.onNavigationChanged,
    required this.pages,
    this.floatingActionButton,
  });

  @override
  Widget build(BuildContext context) {
    final category = ResponsiveLayout.getCategory(context);

    switch (category) {
      case DeviceLayoutCategory.verticalMobile:
        return _buildMobilePortrait(context);
      case DeviceLayoutCategory.foldableTablet:
        return _buildFoldableTablet(context);
      case DeviceLayoutCategory.widescreenDesktop:
        return _buildWidescreenDesktop(context);
    }
  }

  Widget _buildMobilePortrait(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: pages,
      ),
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(top: BorderSide(color: AppTheme.surfaceBorder, width: 0.8)),
        ),
        child: BottomNavigationBar(
          currentIndex: currentIndex,
          onTap: onNavigationChanged,
          backgroundColor: Colors.transparent,
          elevation: 0,
          selectedItemColor: AppTheme.cyberCyan,
          unselectedItemColor: AppTheme.textMuted,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 12),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.movie_creation_outlined),
              activeIcon: Icon(Icons.movie_creation, color: AppTheme.cyberCyan),
              label: 'Catalog',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.download_for_offline_outlined),
              activeIcon: Icon(Icons.download_for_offline, color: AppTheme.cyberCyan),
              label: 'Downloads',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.cloud_download_outlined),
              activeIcon: Icon(Icons.cloud_download, color: AppTheme.cyberCyan),
              label: 'Torrents',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFoldableTablet(BuildContext context) {
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: currentIndex,
            onDestinationSelected: onNavigationChanged,
            backgroundColor: AppTheme.surface,
            labelType: NavigationRailLabelType.selected,
            selectedIconTheme: const IconThemeData(color: AppTheme.cyberCyan),
            unselectedIconTheme: const IconThemeData(color: AppTheme.textMuted),
            selectedLabelTextStyle: const TextStyle(
              color: AppTheme.cyberCyan,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.netflixRed.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_arrow_rounded, color: AppTheme.netflixRed, size: 28),
              ),
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.movie_creation_outlined),
                selectedIcon: Icon(Icons.movie_creation),
                label: Text('Catalog'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.download_for_offline_outlined),
                selectedIcon: Icon(Icons.download_for_offline),
                label: Text('Offline'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.cloud_download_outlined),
                selectedIcon: Icon(Icons.cloud_download),
                label: Text('Torrents'),
              ),
            ],
          ),
          const VerticalDivider(width: 1, color: AppTheme.surfaceBorder),
          Expanded(
            child: IndexedStack(
              index: currentIndex,
              children: pages,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWidescreenDesktop(BuildContext context) {
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: Row(
        children: [
          Container(
            width: 240,
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(right: BorderSide(color: AppTheme.surfaceBorder, width: 1)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.netflixRed,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.netflixRed.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PRIVATE',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                              letterSpacing: 2,
                            ),
                          ),
                          Text(
                            'STREAM',
                            style: TextStyle(
                              color: AppTheme.cyberCyan,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.surfaceBorder),
                const SizedBox(height: 16),
                _buildSidebarItem(0, 'Media Catalog', Icons.movie_outlined, Icons.movie),
                _buildSidebarItem(1, 'Offline Downloads', Icons.download_for_offline_outlined, Icons.download_for_offline),
                _buildSidebarItem(2, 'Cloud Ingestion', Icons.cloud_download_outlined, Icons.cloud_download),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.surfaceBorder),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined, color: AppTheme.accentGreen, size: 18),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Anti-Ban VFS Active',
                            style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: currentIndex,
              children: pages,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem(int index, String label, IconData icon, IconData activeIcon) {
    final isSelected = currentIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () => onNavigationChanged(index),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.surfaceLight : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected ? Border.all(color: AppTheme.cyberCyan.withValues(alpha: 0.4)) : null,
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? activeIcon : icon,
                color: isSelected ? AppTheme.cyberCyan : AppTheme.textMuted,
                size: 20,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 14,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
