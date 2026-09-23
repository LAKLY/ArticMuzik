part of 'main_screen.dart';

class _SettingsContent extends StatefulWidget {
  const _SettingsContent();

  @override
  State<_SettingsContent> createState() => __SettingsContentState();
}

class __SettingsContentState extends State<_SettingsContent> with AutomaticKeepAliveClientMixin {
  bool _hapticEnabled = true;
  AppTheme _currentTheme = AppTheme.defaultTheme;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeName = prefs.getString('app_theme') ?? 'defaultTheme';
    setState(() {
      _currentTheme = _parseTheme(themeName);
    });
  }

  AppTheme _parseTheme(String name) {
    switch (name) {
      case 'darkCrimson': return AppTheme.darkCrimson;
      case 'neonCyber': return AppTheme.neonCyber;
      case 'matrixGreen': return AppTheme.matrixGreen;
      default: return AppTheme.defaultTheme;
    }
  }

  Future<void> _changeTheme(AppTheme theme) async {
    final notifier = Provider.of<ThemeNotifier>(context, listen: false);
    notifier.applyTheme(theme);
    setState(() => _currentTheme = theme);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Тема изменена'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _logout() async {
    final auth = Provider.of<YandexAuthService>(context, listen: false);
    await auth.logout();
    if (mounted) Navigator.pushReplacementNamed(context, '/token');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenWidth = MediaQuery.of(context).size.width;
    return Container(
      padding: EdgeInsets.all(screenWidth * 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text("Настройки", style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: ArticTheme.primary)),
          const SizedBox(height: 24),
          _buildTile(
            title: "Тактильная отдача",
            subtitle: "Вибрация при смене вкладок",
            icon: Icons.vibration,
            trailing: Switch(
              value: _hapticEnabled,
              onChanged: (v) => setState(() => _hapticEnabled = v),
              activeThumbColor: ArticTheme.accent,
            ),
          ),
          _buildThemeSelector(),
          _buildTile(
            title: "Выйти из Яндекс.Музыки",
            subtitle: "Сбросить токен и выйти из аккаунта",
            icon: Icons.logout,
            iconColor: ArticTheme.accent,
            onTap: _logout,
          ),
          _buildTile(
            title: "О приложении",
            subtitle: "ArticMuzik 3.0 с Яндекс.Музыкой",
            icon: Icons.info_outline,
            iconColor: ArticTheme.accent,
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: ArticTheme.backgroundDarkest,
                title: Text("ArticMuzik", style: TextStyle(color: ArticTheme.primary)),
                content: Text(
                  "Минималистичный музыкальный плеер с поддержкой Яндекс.Музыки.",
                  style: TextStyle(color: ArticTheme.secondary),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Закрыть", style: TextStyle(color: ArticTheme.accent)),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text("Оформление", style: TextStyle(color: ArticTheme.primary, fontWeight: FontWeight.w500)),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _ThemeChip(
              label: "По умолчанию",
              theme: AppTheme.defaultTheme,
              isSelected: _currentTheme == AppTheme.defaultTheme,
              onTap: () => _changeTheme(AppTheme.defaultTheme),
            ),
            _ThemeChip(
              label: "Тёмный багровый",
              theme: AppTheme.darkCrimson,
              isSelected: _currentTheme == AppTheme.darkCrimson,
              onTap: () => _changeTheme(AppTheme.darkCrimson),
            ),
            _ThemeChip(
              label: "Неон кибер",
              theme: AppTheme.neonCyber,
              isSelected: _currentTheme == AppTheme.neonCyber,
              onTap: () => _changeTheme(AppTheme.neonCyber),
            ),
            _ThemeChip(
              label: "Матрица",
              theme: AppTheme.matrixGreen,
              isSelected: _currentTheme == AppTheme.matrixGreen,
              onTap: () => _changeTheme(AppTheme.matrixGreen),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTile({
    required String title,
    required String subtitle,
    required IconData icon,
    Color? iconColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? ArticTheme.accent),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: ArticTheme.primary, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(color: ArticTheme.secondary, fontSize: 12)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}

class _ThemeChip extends StatelessWidget {
  final String label;
  final AppTheme theme;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeChip({
    required this.label,
    required this.theme,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      backgroundColor: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
      selectedColor: ArticTheme.accent,
      checkmarkColor: ArticTheme.primary,
      labelStyle: TextStyle(color: isSelected ? ArticTheme.primary : ArticTheme.secondary),
    );
  }
}