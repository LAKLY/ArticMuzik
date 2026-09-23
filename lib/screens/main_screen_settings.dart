part of 'main_screen.dart';

class _SettingsContent extends StatefulWidget {
  const _SettingsContent();

  @override
  State<_SettingsContent> createState() => __SettingsContentState();
}

class __SettingsContentState extends State<_SettingsContent>
    with AutomaticKeepAliveClientMixin {
  bool _hapticEnabled = true;
  AppTheme _currentTheme = AppTheme.defaultTheme;
  int _crossfadeSeconds = 0;

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
    final crossfade = prefs.getInt('crossfade_seconds') ?? 0;
    setState(() {
      _currentTheme = _parseTheme(themeName);
      _crossfadeSeconds = crossfade.clamp(0, 5);
    });
  }

  AppTheme _parseTheme(String name) {
    switch (name) {
      case 'darkCrimson':
        return AppTheme.darkCrimson;
      case 'neonCyber':
        return AppTheme.neonCyber;
      case 'matrixGreen':
        return AppTheme.matrixGreen;
      default:
        return AppTheme.defaultTheme;
    }
  }

  Future<void> _changeTheme(AppTheme theme) async {
    final notifier = Provider.of<ThemeNotifier>(context, listen: false);
    notifier.applyTheme(theme);
    setState(() => _currentTheme = theme);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Тема изменена'), duration: Duration(seconds: 1)),
    );
  }

  Future<void> _changeCrossfade(int seconds) async {
    final handler = Provider.of<AppAudioHandler>(context, listen: false);
    await handler.setCrossfadeSeconds(seconds);
    setState(() => _crossfadeSeconds = seconds);
  }

  Future<void> _logout() async {
    final auth = Provider.of<YandexAuthService>(context, listen: false);
    await auth.logout();
    if (mounted) Navigator.pushReplacementNamed(context, '/token');
  }

  void _openStorage() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const StorageManagerScreen()));
  }

  void _openDownloads() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const DownloadsScreen()));
  }

  void _openHistory() {
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => const HistoryScreen()));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final screenWidth = MediaQuery.of(context).size.width;
    return SingleChildScrollView(
      padding: EdgeInsets.all(screenWidth * 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          Text("Настройки",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: ArticTheme.primary)),
          const SizedBox(height: 24),

          // ---------- Плеер ----------
          _sectionLabel("Плеер"),
          _buildCrossfadeTile(),
          const SizedBox(height: 8),

          // ---------- Интерфейс ----------
          _sectionLabel("Интерфейс"),
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

          // ---------- Хранилище ----------
          _sectionLabel("Хранилище"),
          _buildTile(
            title: "Хранилище",
            subtitle: "Управление кэшем и закреплёнными треками",
            icon: Icons.storage,
            iconColor: ArticTheme.accent,
            onTap: _openStorage,
          ),
          _buildTile(
            title: "Загрузки",
            subtitle: "Активные и завершённые загрузки",
            icon: Icons.download,
            iconColor: ArticTheme.accent,
            onTap: _openDownloads,
          ),
          _buildTile(
            title: "История",
            subtitle: "Недавно прослушанные треки",
            icon: Icons.history,
            iconColor: ArticTheme.accent,
            onTap: _openHistory,
          ),

          // ---------- Аккаунт ----------
          _sectionLabel("Аккаунт"),
          _buildTile(
            title: "Выйти из Яндекс.Музыки",
            subtitle: "Сбросить токен и выйти из аккаунта",
            icon: Icons.logout,
            iconColor: ArticTheme.accent,
            onTap: _logout,
          ),
          _buildTile(
            title: "О приложении",
            subtitle: "ArticMuzik 0.1.0",
            icon: Icons.info_outline,
            iconColor: ArticTheme.accent,
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                backgroundColor: ArticTheme.backgroundDarkest,
                title: Text("ArticMuzik",
                    style: TextStyle(color: ArticTheme.primary)),
                content: Text(
                  "Минималистичный музыкальный плеер с поддержкой Яндекс.Музыки.",
                  style: TextStyle(color: ArticTheme.secondary),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text("Закрыть",
                        style: TextStyle(color: ArticTheme.accent)),
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: ArticTheme.secondary.withValues(alpha: 0.7),
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCrossfadeTile() {
    final value = _crossfadeSeconds;
    final subtitle = value == 0 ? 'Выключен' : '$value ${_pluralSeconds(value)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      decoration: BoxDecoration(
        color: ArticTheme.backgroundDarkest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gradient, color: ArticTheme.accent),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Кроссфейд",
                        style: TextStyle(
                            color: ArticTheme.primary,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(
                      'Плавное затухание в конце трека • $subtitle',
                      style: TextStyle(
                          color: ArticTheme.secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 2,
              activeTrackColor: ArticTheme.accent,
              inactiveTrackColor:
                  ArticTheme.secondary.withValues(alpha: 0.3),
              thumbColor: ArticTheme.primary,
              overlayColor: ArticTheme.accent.withValues(alpha: 0.15),
              thumbShape:
                  const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape:
                  const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.toDouble(),
              min: 0,
              max: 5,
              divisions: 5,
              label: value == 0 ? 'Выкл' : '$value с',
              onChanged: (v) => _changeCrossfade(v.round()),
            ),
          ),
        ],
      ),
    );
  }

  String _pluralSeconds(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'секунда';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) {
      return 'секунды';
    }
    return 'секунд';
  }

  Widget _buildThemeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8),
          child: Text("Оформление",
              style: TextStyle(
                  color: ArticTheme.primary, fontWeight: FontWeight.w500)),
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
                  Text(title,
                      style: TextStyle(
                          color: ArticTheme.primary,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: TextStyle(
                          color: ArticTheme.secondary, fontSize: 12)),
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
      labelStyle: TextStyle(
          color: isSelected ? ArticTheme.primary : ArticTheme.secondary),
    );
  }
}