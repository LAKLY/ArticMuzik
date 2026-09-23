# 📘 ВНУТРЕННЯЯ ДОКУМЕНТАЦИЯ

> > ArticMuzik>  – Личный плеер

---

## 📌 Оглавление

- [Общая архитектура](#-общая-архитектура)
- [Основные файлы и модули](#-основные-файлы-и-модули)
  - [-1-точка-входа-main-dart](#-1-точка-входа-main-dart)
  - [-2-сервис-воспроизведения-audio-handler-dart](#-2-сервис-воспроизведения-audio-handler-dart)
  - [-3-работа-с-яндексмузыкой-yandex-audio-provider-dart](#-3-работа-с-яндексмузыкой-yandex-audio-provider-dart)
  - [-4-авторизация-yandex-auth-service-dart](#-4-авторизация-yandex-auth-service-dart)
  - [-5-главный-экран-main-screen-dart](#-5-главный-экран-main-screen-dart)
    - [5.1 – Вкладка «Библиотека» (main_screen_library.dart)](#-51--вкладка-библиотека-main-screen-library-dart)
    - [5.2 – Вкладка «Поиск» (main_screen_search.dart)](#-52--вкладка-поиск-main-screen-search-dart)
    - [5.3 – Вкладка «Настройки» (main_screen_settings.dart)](#-53--вкладка-настройки-main-screen-settings-dart)
    - [5.4 – Мини-плеер (main_screen_miniplayer.dart)](#-54--мини-плеер-main-screen-miniplayer-dart)
  - [-6-полноэкранный-плеер-full-player-page-dart](#-6-полноэкранный-плеер-full-player-page-dart)
  - [-7-тема-оформления-artic-theme-dart-и-theme-notifier-dart](#-7-тема-оформления-artic-theme-dart-и-theme-notifier-dart)
  - [-8-утилиты-color-utils-dart-matrix-background-dart](#-8-утилиты-color-utils-dart-matrix-background-dart)
  - [-9-splashscreen-splash-screen-dart](#-9-splashscreen-splash-screen-dart)
  - [-10-ввод-токена-yandex-token-input-screen-dart](#-10-ввод-токена-yandex-token-input-screen-dart)
- [Важные заметки](#-важные-заметки)
- [Баги/Исправления](#-баги-исправления)
- [Доработки](#-доработки)

---

## 🧱 Общая архитектура

-  >MVVM + Provider > – используется `provider` и `riverpod` (только для аннотаций).  
-  >Сервис аудио > – `AppAudioHandler` наследует `BaseAudioHandler` + `QueueHandler`, работает поверх `AudioPlayer`.  
-  >Провайдер Яндекс.Музыки > – `YandexAudioProvider` инкапсулирует всю работу с `yandex_music` (поиск, лайки, загрузка, кэш).  
-  >Темы > – `ThemeNotifier` управляет цветами, `ArticTheme` – статический доступ к ним.  
-  >Навигация > – `PageView` в `MainScreen`, переход на `FullPlayerPage` через `PageRouteBuilder`.

[🔙 К оглавлению](#-оглавление)

---

### -1-точка-входа-main-dart
[🔙 К оглавлению](#-оглавление)

>  >Назначение: >  
Глобальная инициализация:  
- Настройка `SystemChrome` (иммерсивный режим).  
- Инициализация `SharedPreferences`, `AudioService`.  
- Создание провайдеров (`YandexAuthService`, `AppAudioHandler`, `YandexAudioProvider`, `ThemeNotifier`).  
- Определение начального маршрута (токен или главный экран).

>  >Ключевые моменты: >  
- `ErrorWidget.builder` – кастомная обработка ошибок (файл [`lib/main.dart#L19-L35`](lib/main.dart#L19-L35)).  
- В `ArticMuzikApp` используется `SplashScreen` как `home`.  
- `AudioService.init` с `androidNotificationChannelId` ([строка 58-65](lib/main.dart#L58-L65)).  
- Подписка на `ThemeNotifier` для динамической смены темы.

>  >Связанные файлы: >  
- [`lib/screens/splash_screen.dart`](lib/screens/splash_screen.dart)  
- [`lib/screens/main_screen.dart`](lib/screens/main_screen.dart)  
- [`lib/screens/yandex_token_input_screen.dart`](lib/screens/yandex_token_input_screen.dart)  
- [`lib/services/audio_handler.dart`](lib/services/audio_handler.dart)

[🔙 К оглавлению](#-оглавление)

---

### -2-сервис-воспроизведения-audio-handler-dart
[🔙 К оглавлению](#-оглавление)

>  >Назначение: >  
Управление плеером, очередью, состоянием воспроизведения, сохранением позиции.  
Реализован в файле [`lib/services/audio_handler.dart`](lib/services/audio_handler.dart).

>  >Ключевые методы: >  
- `ready` – `Future`, дожидается инициализации пустого источника ([строка 22](lib/services/audio_handler.dart#L22)).  
- `setTracksAndPlay(items, startIndex)` – загрузка очереди и запуск ([строка 100](lib/services/audio_handler.dart#L100)).  
- `positionStream` / `durationStream` – стримы для слайдера ([строки 15-18](lib/services/audio_handler.dart#L15-L18)).  
- `saveCurrentState()` – сохраняет позицию в `SharedPreferences` (дебаунс 3 сек) ([строка 61](lib/services/audio_handler.dart#L61)).  
- `skipToNext()` / `skipToPrevious()` – с учётом `LoopMode` ([строки 141-151](lib/services/audio_handler.dart#L141-L151)).  
- `setLoopMode(LoopMode)` – установка режима повтора ([строка 95](lib/services/audio_handler.dart#L95)).  

>  >Особенности: >  
- При завершении трека автоматически переключает на следующий, если не включён повтор одного ([строка 37-44](lib/services/audio_handler.dart#L37-L44)).  
- В конструкторе восстанавливает состояние (пока частично) ([строка 56](lib/services/audio_handler.dart#L56)).  
- Используется `ConcatenatingAudioSource` для очереди ([строка 108](lib/services/audio_handler.dart#L108)).  

[🔙 К оглавлению](#-оглавление)

---

### -3-работа-с-яндексмузыкой-yandex-audio-provider-dart
[🔙 К оглавлению](#-оглавление)

>  >Назначение: >  
Основной провайдер для API Яндекс.Музыки через библиотеку [`yandex_music`](lib/Документация.md).  
Файл: [`lib/services/yandex/yandex_audio_provider.dart`](lib/services/yandex/yandex_audio_provider.dart).

>  >Ключевые методы: >  
- `init()` – инициализация `YandexMusic`, загрузка закреплённых треков и кэшированных метаданных, затем `loadFavorites()` ([строка 142](lib/services/yandex/yandex_audio_provider.dart#L142)).  
- `loadFavorites()` – получает лайки и формирует список `_tracks` ([строка 163](lib/services/yandex/yandex_audio_provider.dart#L163)).  
- `search(query, {type})` – поиск треков/исполнителей/альбомов, результат в `_searchResults` ([строка 195](lib/services/yandex/yandex_audio_provider.dart#L195)).  
- `pinTrackWithMetadata()` – скачивает трек, сохраняет в `_pinnedCache` и `_cachedTracks` с метаданными ([строка 372](lib/services/yandex/yandex_audio_provider.dart#L372)).  
- `unpinTrack()` – удаляет файл и метаданные ([строка 390](lib/services/yandex/yandex_audio_provider.dart#L390)).  
- `downloadAndCache()` – загрузка с качеством `lossless`, временное кэширование (макс. 10 треков) ([строка 419](lib/services/yandex/yandex_audio_provider.dart#L419)).  
- `getDirectUrl()` – возвращает путь к файлу (сперва закреплённый, потом временный, иначе скачивает) ([строка 460](lib/services/yandex/yandex_audio_provider.dart#L460)).  
- `getLyrics()`, `getSimilarTracks()`, `getArtistTracks()` – вспомогательные методы ([строки 330, 348, 250](lib/services/yandex/yandex_audio_provider.dart#L330) и далее).  

>  >Состояние: >  
- `_tracks` – список избранных треков.  
- `_cachedTracks` – список закреплённых треков (сохраняется в JSON).  
- `_pinnedTracks` – `Set` идентификаторов закреплённых треков.  
- `_tempCache` – временные файлы.  
- `_pendingDownloads` – защита от повторных загрузок.  

>  >Особенности: >  
- Загрузки защищены от повторных вызовов через `_pendingDownloads` ([строка 419](lib/services/yandex/yandex_audio_provider.dart#L419)).  
- При `dispose()` отменяются все загрузки ([строка 475](lib/services/yandex/yandex_audio_provider.dart#L475)).  
- Используется кэширование метаданных в `SharedPreferences` ([`_saveCachedTracks`](lib/services/yandex/yandex_audio_provider.dart#L137)).  

[🔙 К оглавлению](#-оглавление)

---

### -4-авторизация-yandex-auth-service-dart
[🔙 К оглавлению](#-оглавление)

>  >Назначение: >  
Управление токеном через `flutter_secure_storage`.  
Файл: [`lib/services/yandex/yandex_auth_service.dart`](lib/services/yandex/yandex_auth_service.dart).

>  >Методы: >  
- `saveToken(token)` – запись ([строка 8](lib/services/yandex/yandex_auth_service.dart#L8)).  
- `getAccessToken()` – чтение ([строка 12](lib/services/yandex/yandex_auth_service.dart#L12)).  
- `logout()` – удаление ([строка 16](lib/services/yandex/yandex_auth_service.dart#L16)).  
- `isAuthorized()` – проверка ([строка 20](lib/services/yandex/yandex_auth_service.dart#L20)).

[🔙 К оглавлению](#-оглавление)

---

### -5-главный-экран-main-screen-dart
[🔙 К оглавлению](#-оглавление)

>  >Назначение: >  
Главный экран с тремя вкладками: «Библиотека», «Поиск», «Настройки».  
Использует `PageView` с `PageController`.  
Файл: [`lib/screens/main_screen.dart`](lib/screens/main_screen.dart).

>  >Основная логика в `_MainScreenState`: >  
- `_selectTrackFromLibrary()` – выбор трека, поиск URL, установка очереди ([строка 428](lib/screens/main_screen.dart#L428)).  
- `_showTrackOptions()` – модальное окно с действиями ([строка 178](lib/screens/main_screen.dart#L178)).  
- `_refreshDominantColor()` – извлечение цвета обложки для фона ([строка 120](lib/screens/main_screen.dart#L120)).  
- `_openFullPlayer()` – переход на полноэкранный плеер ([строка 550](lib/screens/main_screen.dart#L550)).  
- `_changeTab()` – переключение вкладок с анимацией и обновлением библиотеки ([строка 147](lib/screens/main_screen.dart#L147)).  

>  >Партиалы (отдельные файлы вкладок): >

#### -51--вкладка-библиотека-main-screen-library-dart
[🔙 К оглавлению](#-оглавление)

Реализована в [`lib/screens/main_screen_library.dart`](lib/screens/main_screen_library.dart).  
Содержит `_LibraryTabs` (переключение между «Все» и «Кэш») и `_TrackList` с элементами `_TrackTile`.  
- `_TrackList` отображает список треков, поддерживает Pull-to-Refresh ([строка 98](lib/screens/main_screen_library.dart#L98)).  
- `_TrackTile` показывает обложку, название, исполнителя, иконки избранного/кэша и индикатор загрузки ([строка 166](lib/screens/main_screen_library.dart#L166)).  
- При долгом нажатии вызывается `_showTrackOptions` из основного файла.

#### -52--вкладка-поиск-main-screen-search-dart
[🔙 К оглавлению](#-оглавление)

Реализована в [`lib/screens/main_screen_search.dart`](lib/screens/main_screen_search.dart).  
Содержит поле ввода, фильтры (треки/исполнители/альбомы) и список результатов.  
- `_SearchContent` – управляет поиском через `YandexAudioProvider.search()` ([строка 18](lib/screens/main_screen_search.dart#L18)).  
- При нажатии на исполнителя/альбом открывается диалог со списком треков ([метод `_onItemTap`](lib/screens/main_screen_search.dart#L68)).  
- Поддерживается долгое нажатие для вызова контекстного меню.

#### -53--вкладка-настройки-main-screen-settings-dart
[🔙 К оглавлению](#-оглавление)

Реализована в [`lib/screens/main_screen_settings.dart`](lib/screens/main_screen_settings.dart).  
Содержит переключатель тактильной отдачи, выбор темы оформления, выход из аккаунта и информацию о приложении.  
- `__SettingsContentState` загружает текущую тему из `SharedPreferences` ([строка 16](lib/screens/main_screen_settings.dart#L16)).  
- `_changeTheme()` применяет тему через `ThemeNotifier` ([строка 33](lib/screens/main_screen_settings.dart#L33)).  
- `_logout()` очищает токен и перенаправляет на экран ввода токена ([строка 40](lib/screens/main_screen_settings.dart#L40)).

#### -54--мини-плеер-main-screen-miniplayer-dart
[🔙 К оглавлению](#-оглавление)

Реализована в [`lib/screens/main_screen_miniplayer.dart`](lib/screens/main_screen_miniplayer.dart).  
Отображается внизу главного экрана при наличии воспроизводимого трека.  
- `_MiniPlayer` – содержит обложку, название, кнопки управления (предыдущий/воспроизведение/пауза/следующий).  
- Поддерживает горизонтальные свайпы для переключения треков ([строка 33](lib/screens/main_screen_miniplayer.dart#L33)).  
- При нажатии на область плеера открывается `FullPlayerPage`.

[🔙 К оглавлению](#-оглавление)

---

### -6-полноэкранный-плеер-full-player-page-dart
[🔙 К оглавлению](#-оглавление)

>  >Назначение: >  
Экран для полноэкранного просмотра трека с анимацией, слайдером, кнопками и текстом песни.  
Файл: [`lib/screens/full_player_page.dart`](lib/screens/full_player_page.dart).

>  >Ключевые элементы: >  
- `_AnimatedGrid` – анимированная сетка ([строка 179](lib/screens/full_player_page.dart#L179)).  
- `_DynamicGradient` – радиальный градиент, цвет меняется от обложки ([строка 210](lib/screens/full_player_page.dart#L210)).  
- `_GlitchCover` – обложка с эффектом глитча при смене трека ([строка 311](lib/screens/full_player_page.dart#L311)).  
- `_SpectrumAnalyzer` – псевдо-эквалайзер ([строка 379](lib/screens/full_player_page.dart#L379)).  
- `_TerminalSlider` – прогресс-бар ([строка 447](lib/screens/full_player_page.dart#L447)).  
- `_ControlButtons` – кнопки управления ([строка 497](lib/screens/full_player_page.dart#L497)).  
- `_TerminalInfo` – информационные бейджи ([строка 540](lib/screens/full_player_page.dart#L540)).  
- `_LyricsView` – отображение текста песни ([строка 569](lib/screens/full_player_page.dart#L569)).

>  >Управление состоянием: >  
- `_dominantColor` – обновляется через `ColorUtils.extractDominantColor` ([строка 116](lib/screens/full_player_page.dart#L116)).  
- `_isLiked` – состояние лайка ([строка 92](lib/screens/full_player_page.dart#L92)).  
- `_loopMode` – режим повтора ([строка 85](lib/screens/full_player_page.dart#L85)).  
- `_showLyrics` – переключение на текст ([строка 86](lib/screens/full_player_page.dart#L86)).  

[🔙 К оглавлению](#-оглавление)

---

### -7-тема-оформления-artic-theme-dart-и-theme-notifier-dart
[🔙 К оглавлению](#-оглавление)

>  >Назначение: >  
Централизованное управление цветовой схемой.  
`ThemeNotifier` – `ChangeNotifier`, хранит текущие цвета.  
`ArticTheme` – статический доступ к ним.  
Файлы: [`lib/theme/theme_notifier.dart`](lib/theme/theme_notifier.dart) и [`lib/theme/artic_theme.dart`](lib/theme/artic_theme.dart).

>  >AppTheme (в `theme_notifier.dart`): >  
- `defaultTheme` – стандартная палитра.  
- `darkCrimson` – тёмно-багровая.  
- `neonCyber` – неоновая кибер-тема.  
- `matrixGreen` – зелёная матричная тема.  

>  >Методы ThemeNotifier: >  
- `loadTheme()` – загрузка из `SharedPreferences` ([строка 36](lib/theme/theme_notifier.dart#L36)).  
- `applyTheme(theme)` – применение и сохранение ([строка 43](lib/theme/theme_notifier.dart#L43)).  
- Геттеры: `babyBarnOwl`, `intrigue`, `burntCrimson`, `sealBrown`, `nulnOil` ([строки 28-33](lib/theme/theme_notifier.dart#L28-L33)).  

>  >ArticTheme (статический класс): >  
- Статические геттеры: `accent`, `primary`, `secondary`, `backgroundDeep`, `backgroundDarkest` ([строки 6-14](lib/theme/artic_theme.dart#L6-L14)).  
- Градиенты: `backgroundGradient`, `surfaceGradient`, `accentGradient` ([строки 17-30](lib/theme/artic_theme.dart#L17-L30)).  
- `glow()` – список `BoxShadow` для свечения ([строка 33](lib/theme/artic_theme.dart#L33)).  

[🔙 К оглавлению](#-оглавление)

---

### -8-утилиты-color-utils-dart-matrix-background-dart
[🔙 К оглавлению](#-оглавление)

>  >`color_utils.dart` > (файл [`lib/utils/color_utils.dart`](lib/utils/color_utils.dart)):  
- `extractDominantColor()` – извлекает доминирующий цвет обложки. Использует `compute` и кэширует в `SharedPreferences` ([строка 15](lib/utils/color_utils.dart#L15)).  
- Обрезает URL до `100x100` для экономии ([строка 46](lib/utils/color_utils.dart#L46)).  
- Использует `PaletteGenerator` для анализа изображения ([строка 55](lib/utils/color_utils.dart#L55)).  
- Поддерживает отмену через `CancelToken` ([строка 21](lib/utils/color_utils.dart#L21)).  

>  >`matrix_background.dart` > (файл [`lib/utils/matrix_background.dart`](lib/utils/matrix_background.dart)):  
- `MatrixBackground` – анимированный матричный фон (сетка + падающие строки с хроматической аберрацией).  
- Разделение на статическую (`_StaticBackgroundPainter`) и динамическую (`_DynamicTelemetryPainter`) части для оптимизации ([строки 34-49](lib/utils/matrix_background.dart#L34-L49)).  
- Управляется через `AnimationController` с длительностью 15 секунд ([строка 22](lib/utils/matrix_background.dart#L22)).  
- Количество падающих строк задаётся через `numberOfDrops` (по умолчанию 15) ([строка 9](lib/utils/matrix_background.dart#L9)).  

[🔙 К оглавлению](#-оглавление)

---

### -9-splashscreen-splash-screen-dart
[🔙 К оглавлению](#-оглавление)

>  >Назначение: >  
Заставка с ASCII-артом (логотип), анимация появления и сворачивания.  
Файл: [`lib/screens/splash_screen.dart`](lib/screens/splash_screen.dart).

>  >Логика: >  
- `AnimationController` на 4 секунды ([строка 88](lib/screens/splash_screen.dart#L88)).  
- Фоном отображается `MainScreen`, сверху – `ClipRect` с артом, который постепенно обрезается ([строка 199](lib/screens/splash_screen.dart#L199)).  
- Внизу – прогресс-бар с градиентом ([строка 240](lib/screens/splash_screen.dart#L240)).  
- После завершения анимации заставка исчезает, показывая основной экран.  
- ASCII-арт встроен в код как многострочная строка ([строка 59](lib/screens/splash_screen.dart#L59)).  

[🔙 К оглавлению](#-оглавление)

---

### -10-ввод-токена-yandex-token-input-screen-dart
[🔙 К оглавлению](#-оглавление)

>  >Назначение: >  
Экран для ввода OAuth-токена. Поле предзаполнено тестовым токеном.  
Файл: [`lib/screens/yandex_token_input_screen.dart`](lib/screens/yandex_token_input_screen.dart).

>  >Логика: >  
- `_saveToken()` – сохраняет токен, инициализирует провайдер и переходит на `/main` ([строка 20](lib/screens/yandex_token_input_screen.dart#L20)).  
- Показывает инструкцию по получению токена ([строка 62](lib/screens/yandex_token_input_screen.dart#L62)).  
- Встроенный тестовый токен для быстрого старта ([строка 16](lib/screens/yandex_token_input_screen.dart#L16)).  

[🔙 К оглавлению](#-оглавление)

---

## 📌 Важные заметки
[🔙 К оглавлению](#-оглавление)

-  >Токен Яндекс.Музыки > – используйте валидный OAuth-токен. Встроенный тестовый может истечь.  
-  >Кэширование > – закреплённые треки хранятся в `path_provider`. Метаданные – в `SharedPreferences` (JSON).  
-  >Качество загрузки > – `AudioQuality.lossless` (может занимать много места).  
-  >Режим повтора > – `LoopMode.off`, `.one`, `.all`.  
-  >Темы > – переключение применяется мгновенно через `ThemeNotifier`.  
-  >Обработка ошибок > – глобальный `ErrorWidget.builder`, в сервисах – через `_error` и `SnackBar`.  
-  >Производительность > – использованы `RepaintBoundary`, `compute`, кэширование цвета.  
-  >Зависимости > – основные пакеты: `audio_service`, `just_audio`, `yandex_music`, `provider`, `shared_preferences`, `flutter_secure_storage`, `cached_network_image`, `palette_generator`, `flutter_animate`.

> 📅  >Последнее обновление: > 2026-06-20  
[🔙 К оглавлению](#-оглавление)

---

## 📌 Баги Исправления
[🔙 К оглавлению](#-оглавление)

-  >Аудио-сервис >: при переходе в фоновый режим позиция может сбрасываться из-за отсутствия полного восстановления состояния – требуется доработка `_restoreState()` в [`audio_handler.dart`](lib/services/audio_handler.dart#L56).  
-  >Поиск >: при быстром переключении фильтров могут происходить дублирующиеся запросы – отсутствует отмена предыдущих.  
-  >Темы >: при смене темы некоторые элементы (например, слайдер) не перерисовываются мгновенно – требуется принудительное обновление.  
-  >Кэш >: временные файлы не очищаются при выходе из приложения – необходимо добавить вызов `_enforceTempCacheLimit()` при `dispose`.  

> 📅  >Последнее обновление: > 2026-06-20  
[🔙 К оглавлению](#-оглавление)

---

## 📌 Доработки
[🔙 К оглавлению](#-оглавление)

-  >Поддержка плейлистов > – добавить возможность просмотра и воспроизведения пользовательских плейлистов (использовать методы `YandexMusicPlaylists`).  
-  >Эквалайзер > – реализовать настоящий аудио-спектр с использованием `just_audio` (через `AudioPlayer` пока нет прямой поддержки).  

> 📅  >Последнее обновление: > 2026-06-20  
[🔙 К оглавлению](#-оглавление)