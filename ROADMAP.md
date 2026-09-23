```markdown
# ArticMuzik — Roadmap

> Внутренний документ. Живой. Обновляется после каждой волны.
> Последнее обновление: после двух аудитов (функционального и визуального).

---

## 🎯 Философия проекта

**ArticMuzik — это музыкальный плеер.** Он им остаётся.

Мы не превращаем проект в витрину эффектов или терминал ради терминальности. Но мы **не боимся экспериментировать** — просто каждый эксперимент должен усиливать плеер, а не заменять его.

**Правило:** любой эффект и любая фича должны подчиняться концепции «музыкальный плеер с характером». Если что-то не про музыку и не про UX — в долгий backlog, но не в мусор. Через год может пригодиться.

**Девиз:** `Dark / atmospheric / musical / technical / reactive / customizable`.

---

## 📌 Легенда приоритетов

- 🔴 **Срочно** — текущая волна, фиксим в ближайших коммитах
- 🟠 **Важно** — следующая волна
- 🟡 **Желательно** — через волну-две
- 🟢 **Идея / долгий backlog** — когда-нибудь, если руки дойдут
- ⏸️ **Отложено** — не сейчас, но вернёмся
- ❌ **Не делаем** — осознанно отклонено (сохраняем причину)

---

## 🧭 Горизонт планирования

Мы растягиваем работу **на несколько месяцев**, а не на «1-2 недели».

```
Волна 0 → стабилизация текущего
Волна 1 → критичные баги
Волна 2 → качество и UX
Волна 3 → тесты и надёжность
Волна 4 → Artic UI Kit (визуальная база)
Волна 5 → Dynamic Environment + Full Player 2.0
Волна 6 → Motion и micro-interactions
Волна 7 → фичи (playlists, lyrics, diagnostics)
Волна 8 → Artic Lab (кастомизация)
Волна 9 → продвинутый визуал (shaders, режимы)
Волна 10 → релизная подготовка
```

Никаких искусственных дедлайнов. Каждая волна — только когда предыдущая действительно стабильна.

---

# 🌊 ВОЛНА 0. Стабилизация текущего состояния

**Статус:** практически закрыта. Осталось только проверить на реальных сценариях.

- [x] SQLite для очереди, истории, кэша
- [x] Единый `TrackCacheManager` с миграцией
- [x] `HistoryStore` с дедупликацией
- [x] Offline mode с автодетектом
- [x] Расширенный `QueueSheet` (свайп, reorder, play next)
- [x] Storage Manager v2
- [x] Сериализация операций через `_opChain`
- [x] MiniPlayer через `StreamBuilder` + throttle
- [x] Smart preloading следующего трека
- [ ] Проверить все сценарии на реальном устройстве в течение 2-3 дней
- [ ] Собрать список неожиданных багов

**Когда закрывается:** когда 3 дня подряд нет новых багов из этой категории.

---

# 🔴 ВОЛНА 1. Критичные баги

Из функционального аудита. Всё это фиксим **до** новых фич.

## 1.1. `AudioHandler.setTracksAndPlay` — recovery без синхронизации
**Файл:** `lib/services/audio_handler.dart`

- [ ] В recovery-ветке синхронизировать: `queue.add(items)`, `mediaItem.add(items[startIndex])`, `_lastSwitchAt`, `onTrackStarted`
- [ ] Или полностью переписать recovery: `setAudioSource` → `play` → полная пересборка state
- [ ] Тест: сломанный source → recovery → queue соответствует реальности

## 1.2. `_queueOp` — правило неизменности
**Файл:** `lib/services/audio_handler.dart`

- [ ] Зафиксировать правило: **internal-методы не вызывают public `_queueOp`-методы**
- [ ] Комментарий-предупреждение у `_queueOp`
- [ ] Ревизия текущих вызовов

## 1.3. `_restoreState` — clamping
**Файл:** `lib/services/audio_handler.dart`

- [ ] `savedIndex.clamp(0, validItems.length - 1)`
- [ ] `savedPositionMs = max(0, savedPositionMs)`

## 1.4. JSON-in-JSON в сохранении очереди
**Файл:** `lib/services/audio_handler.dart`

- [ ] Переписать на `jsonEncode(List<Map>)` — массив объектов
- [ ] Обработчик чтения — поддержать оба формата (старый + новый)
- [ ] Одноразовая миграция при следующем сохранении

## 1.5. `TrackCacheManager` — duplicate downloads
**Файл:** `lib/services/cache/track_cache_manager.dart`

- [ ] Убедиться, что `_downloadAndSave` сериализует через `_pending` по `trackId`
- [ ] Тест: параллельный `cacheTemp('id42')` x2 → один download

## 1.6. `clearTemp` / `clearAll` — удаление только из БД
**Файлы:** `track_cache_manager.dart`, `cache_repository.dart`

- [ ] UI никогда не вызывает `CacheRepository.clearTemp()` напрямую
- [ ] Вся очистка — через `TrackCacheManager`: файлы + БД
- [ ] Комментарий-предупреждение в `CacheRepository`: только DB-операция

## 1.7. Playback error → auto-skip
**Файл:** `lib/services/audio_handler.dart`

- [ ] Разделить: **авто-переход** (закончился) vs **ручной** (тапнул)
- [ ] Ручной → **retry 1 раз**, потом skip
- [ ] При пропуске — toast: «Не удалось воспроизвести: [название]»
- [ ] `_brokenTrackIds` — только постоянные ошибки

## 1.8. `checkConnectivity()` — лёгкий ping
**Файл:** `lib/services/yandex/yandex_audio_provider.dart`

- [ ] Найти лёгкий endpoint (или реагировать на ошибки реальных запросов)
- [ ] Или увеличить интервал до 30-60 сек
- [ ] Комбинировать: system connectivity + real request по требованию

## 1.9. `dispose()` в `AppAudioHandler`
**Файл:** `lib/services/audio_handler.dart`

- [ ] Полная очистка: `_player.dispose()`, таймеры, stream-подписки
- [ ] `_opChain` — pending-операции корректно отменяются
- [ ] Lifecycle observer — `removeObserver()`

**Критерий завершения волны:** на реальном устройстве нельзя воспроизвести ни один из багов. Все коммиты влиты в main.

---

# 🟠 ВОЛНА 2. Качество и UX

Из обоих аудитов. Всё это улучшает поведение и UX, но не ломает ничего существующего.

## 2.1. Различать типы ошибок
**Файлы:** `yandex_audio_provider.dart` + все вызовы

- [ ] Ввести `sealed class AppResult<T>` или `AppError { debugMessage, userMessage, type }`
- [ ] Типы: `network`, `auth`, `api`, `empty`, `rateLimit`
- [ ] UI показывает `userMessage`, лог — `debugMessage`
- [ ] Убрать `catch (e) { return []; }` из yandex-слоя

## 2.2. `preloadNextTrack` — max 1 concurrent
**Файл:** `yandex_audio_provider.dart`

- [ ] Отменять старый preload при новом
- [ ] Или очередь на 1 preload
- [ ] TTL — не более 5 минут

## 2.3. `onTrackStarted` — не god-callback
**Правило:**

- [ ] Зафиксировать: не более 3-4 действий
- [ ] Если больше — переделать в событийную шину `StreamController<TrackStartedEvent>`

## 2.4. MiniPlayer — StreamBuilder nesting
**Файл:** `main_screen_miniplayer.dart`

- [ ] Объединить position + duration в один стрим
- [ ] Или `rxdart`'s `combineLatest` (уже в pubspec)

## 2.5. Pulse animation только при playing
**Файл:** `main_screen_miniplayer.dart`

- [ ] `if (isPlaying && !_pulseController.isAnimating) repeat()`
- [ ] `else if (!isPlaying && _pulseController.isAnimating) stop()`

## 2.6. `getArtistTracks` — кэш и лимит
**Файл:** `yandex_audio_provider.dart`

- [ ] Кэш `artistId → List<tracks>` с TTL 1 час
- [ ] Лимит на N альбомов за раз
- [ ] Прогресс для долгих операций

## 2.7. `getAlbumTracks` через ID
**Файл:** `yandex_audio_provider.dart`

- [ ] Передавать `albumId` из UI
- [ ] Использовать `albums.getInformation(int id)`
- [ ] Fallback на поиск — как исключение

## 2.8. `_brokenTrackIds` — permanent vs temporary
**Файл:** `lib/services/audio_handler.dart`

- [ ] Различать: недоступен в аккаунте (permanent) vs network hiccup (temporary)
- [ ] Temporary — retry с backoff
- [ ] Permanent — skip + пометка

## 2.9. SnackBar / Toast — фирменный стиль
- [ ] Единая точка `ArticToast.show(context, text, type)`
- [ ] Типы: `success / error / info`

## 2.10. Loading states — единый язык
- [ ] Везде `ArticLoader` с фирменной анимацией
- [ ] Не `CircularProgressIndicator` в каждом месте по-своему

**Критерий завершения волны:** UI нигде не показывает пользователю `DioException` / `SocketException`. Все ошибки различаются по типу.

---

# 🔴 ВОЛНА 3. Тесты и надёжность

Теперь действительно пора. Логика выросла.

## 3.1. AudioHandler (10+ тестов)
**Папка:** `test/services/audio_handler_test.dart`

- [ ] set queue
- [ ] skip next / previous
- [ ] repeat off / one / all
- [ ] remove from queue
- [ ] move in queue
- [ ] clear queue
- [ ] restore state
- [ ] concurrent skip (защита от double-tap)
- [ ] recovery path
- [ ] JSON-in-JSON migration

## 3.2. CacheManager (10+ тестов)
**Папка:** `test/services/track_cache_manager_test.dart`

- [ ] download
- [ ] duplicate download (защита `_pending`)
- [ ] pin / unpin
- [ ] missing file → cleanup
- [ ] temp limit 10
- [ ] clearTemp (файлы + БД)
- [ ] clearAll (файлы + БД)
- [ ] migration из v1
- [ ] migration из prefs
- [ ] concurrent cacheTemp

## 3.3. HistoryStore (5 тестов)
**Папка:** `test/services/history_store_test.dart`

- [ ] insert
- [ ] duplicate → переставить наверх
- [ ] limit 100
- [ ] clear
- [ ] load

## 3.4. Database (3 теста)
**Папка:** `test/services/app_database_test.dart`

- [ ] create schema
- [ ] persistence across re-open
- [ ] upgrade stub

## 3.5. CI — минимальный
**Файл:** `.github/workflows/ci.yml`

- [ ] `flutter pub get`
- [ ] `dart format --set-exit-if-changed`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] Опционально: Android build

**Критерий завершения волны:** `flutter test` — зелёный. CI проходит на push.

---

# 🎨 ВОЛНА 4. Artic UI Kit — визуальная база

Фундамент для всего визуального. **Постепенная замена Material-компонентов**, которые видны пользователю.

## 4.1. Структура
**Создать:** `lib/ui/artic/`

## 4.2. Базовые виджеты

- [ ] `ArticSurface` — контейнер с фирменными тенями/glow
- [ ] `ArticIconButton` — замена `IconButton`
- [ ] `ArticButton` — замена `ElevatedButton`
- [ ] `ArticTile` — замена `ListTile`
- [ ] `ArticSheet` — замена `showModalBottomSheet`
- [ ] `ArticDialog` — замена `AlertDialog`
- [ ] `ArticChip` — замена `FilterChip`
- [ ] `ArticSlider` — вынести общий
- [ ] `ArticToast` — фирменный snackbar
- [ ] `ArticDivider`
- [ ] `ArticBadge`

## 4.3. Правило замены
**Не переписываем всё сразу.** Один виджет за раз, коммит после каждого. При этом функциональность не меняется — только внешний вид.

## 4.4. Внедрение по приоритету
1. [ ] FullPlayerPage
2. [ ] MiniPlayer
3. [ ] QueueSheet
4. [ ] StorageManager
5. [ ] LibraryTabs
6. [ ] SearchContent
7. [ ] Settings

**Критерий завершения волны:** ни один `showModalBottomSheet` / `AlertDialog` / `SnackBar` / `IconButton` не вызывается напрямую. Всё через `Artic*`.

---

# 🎨 ВОЛНА 5. Dynamic Environment + Full Player 2.0

Самое заметное улучшение визуала.

## 5.1. Динамическая палитра
**Файлы:** `color_utils.dart`, `main_screen.dart`, `full_player_page.dart`

- [ ] Из обложки генерировать: `primary`, `secondary`, `accent`, `glow`, `muted`
- [ ] Плавный morph между треками через `TweenAnimationBuilder`
- [ ] Ambient background — мягкое цветовое облако (усилить текущий radial gradient)
- [ ] Glow layer — свечение от обложки, реагирует на playing/paused

## 5.2. Cover art modes
**Файл:** `full_player_page.dart`

- [ ] `Square` (текущий)
- [ ] `Floating` — лёгкий parallax по движению пальца
- [ ] `Vinyl` — обложка в стиле пластинки
- [ ] Переключатель в настройках

## 5.3. Visualizer modes
**Файл:** `full_player_page.dart`

- [ ] `Bars` (текущий)
- [ ] `Wave` — бегущая волна
- [ ] `Orbital` — линии вокруг обложки
- [ ] `Off`
- [ ] Переключатель в настройках
- [ ] Все режимы — псевдо (кроме реального FFT в волне 9)

## 5.4. Progress bar styles
- [ ] `Line` (текущий)
- [ ] `Wave` — с модуляцией
- [ ] Выбор в настройках

## 5.5. Track transition
- [ ] Плавный morph цвета при смене
- [ ] Лёгкий fade между обложками

**Критерий завершения волны:** каждый трек реально меняет атмосферу интерфейса. Переключение modes работает из настроек.

---

# 🎨 ВОЛНА 6. Artic Motion — micro-interactions

Полируем ощущение «дорогого» интерфейса.

- [ ] Play → pulse + glow
- [ ] Pause → flat, без анимации
- [ ] Like → burst частиц вокруг иконки
- [ ] Download → прогресс-кружок, встроенный в иконку
- [ ] Queue add → трек «влетает» в очередь
- [ ] Error → лёгкий shake
- [ ] Track change → сдвиг информации с fade
- [ ] Skip next/prev → лёгкий slide в сторону

**Критерий завершения волны:** пользователь чувствует отклик на каждое действие.

---

# 🟢 ВОЛНА 7. Фичи

Собственно функциональность, которая превращает плеер в «полноценный».

## 7.1. Плейлисты
- [ ] Просмотр плейлистов пользователя (`playlists.getUsersPlaylists`)
- [ ] Воспроизведение плейлиста
- [ ] Сохранить текущую очередь как плейлист

## 7.2. Synced lyrics
- [ ] Парсинг LRC
- [ ] Автоскролл
- [ ] Highlight активной строки
- [ ] Font scaling

## 7.3. Shuffle
- [ ] Простое `player.shuffle()` — не переписывая очередь
- [ ] Индикатор в UI

## 7.4. Crossfade
- [ ] `just_audio` + таймер на `setVolume`
- [ ] 1–3 сек в настройках

## 7.5. Sleep timer
- [ ] 15 / 30 / 60 мин
- [ ] Fade out за 10 сек до конца

## 7.6. Diagnostics экран
- [ ] Версия приложения
- [ ] Состояние БД, кэша, сети
- [ ] Последняя ошибка
- [ ] Кнопки: очистить кэш, сбросить состояние

## 7.7. Smart queue
- [ ] «Играть похожие после очереди»
- [ ] «Продолжить трек исполнителя»

**Критерий завершения волны:** есть чем пользоваться, а не только чем восхищаться.

---

# 🎨 ВОЛНА 8. Artic Lab — кастомизация

**Осторожно.** Минимум, без конструктора интерфейса.

## 8.1. Appearance
- [ ] Accent intensity slider
- [ ] Glow intensity slider
- [ ] Animation speed slider

## 8.2. Visualizer
- [ ] Режим: `Bars / Wave / Orbital / Off`
- [ ] Интенсивность

## 8.3. Cover
- [ ] Стиль: `Square / Floating / Vinyl`

## 8.4. Presets
- [ ] Save current settings as preset
- [ ] Load preset
- [ ] Export / import JSON

## 8.5. Что НЕ делаем в Lab
- ❌ «Собери интерфейс сам» (из блоков)
- ❌ Кастомные страницы
- ❌ Изменение навигации

**Критерий завершения волны:** пользователь может настроить интенсивность визуала, но не может превратить плеер в другое приложение.

---

# 🎨 ВОЛНА 9. Продвинутый визуал

Здесь можно экспериментировать. Не обязательно всё делать.

## 9.1. Visual Modes
Дополнительные режимы **поверх существующих настроек**:

- [ ] `Aurora` — soft / fluid / atmospheric
- [ ] `Terminal` — technical / green / scanlines (умеренно)
- [ ] `Cyber` — neon / glow / glitch
- [ ] `Noir` — grain / shadows / cinematic
- [ ] `Dream` — blur / particles / soft gradients

## 9.2. Shaders (только если хочется реально глубоко копать)
- [ ] `artic_ambient.frag` — мягкое цветовое облако с distortion
- [ ] Передавать: `dominantColor`, `secondaryColor`, `time`, `progress`, `isPlaying`
- [ ] Не на весь экран — только под плеером
- [ ] При паузе — медленное движение, при воспроизведении — быстрее

## 9.3. Grain / texture
- [ ] `noise: 3-6%` максимум
- [ ] Лёгкий, через `CustomPainter` или шейдер
- [ ] Настройка в Lab

## 9.4. Real FFT visualizer
- [ ] Платформенный визуализатор для Android
- [ ] Только один режим — real-time
- [ ] Остальные — псевдо

## 9.5. Custom page transitions
- [ ] Player → Queue
- [ ] Search → Artist
- [ ] Shared element на обложке

**Критерий завершения волны:** приложение узнаётся по визуалу даже без логотипа.

---

# 🚀 ВОЛНА 10. Релизная подготовка

Когда **всё выше** реально стабильно.

- [ ] Убрать тестовый токен
- [ ] Убрать debug prints
- [ ] Ревью всех зависимостей (`flutter pub deps`)
- [ ] Удалить dead code
- [ ] Настроить signing Android / iOS
- [ ] Privacy policy
- [ ] Licenses экран
- [ ] Обновить README (публичная версия, не внутренняя)
- [ ] Проверить versioning
- [ ] Финальный прогон тестов на 3+ реальных устройствах
- [ ] Crash reporting (Sentry / Firebase)
- [ ] Логирование

**Критерий:** можно выпускать без стыда.

---

# 📋 Правило обновления roadmap

После каждой волны:

1. **Пересмотреть** — что потеряло актуальность, что появилось нового
2. **Закрыть** выполненные пункты
3. **Перенести** застрявшее
4. **Добавить** новые находки

Roadmap — **живой документ**. Если пункт висит 2 волны и не делается — либо закрыть, либо честно перенести в долгий backlog с пометкой ⏸️.

---

# 📅 Отметки прогресса

## Волна 0
- [ ] Все сценарии проверены на реальном устройстве

## Волна 1
- [ ] 1.1 Recovery
- [ ] 1.2 `_queueOp` правило
- [ ] 1.3 Clamping
- [ ] 1.4 JSON-in-JSON
- [ ] 1.5 Duplicate downloads
- [ ] 1.6 clearTemp/clearAll
- [ ] 1.7 Playback retry
- [ ] 1.8 checkConnectivity
- [ ] 1.9 dispose

## Волна 2
- [ ] 2.1 AppError types
- [ ] 2.2 Preload limit
- [ ] 2.3 onTrackStarted
- [ ] 2.4 MiniPlayer nesting
- [ ] 2.5 Pulse при playing
- [ ] 2.6 Artist cache
- [ ] 2.7 Album by ID
- [ ] 2.8 broken permanent/temporary
- [ ] 2.9 ArticToast
- [ ] 2.10 ArticLoader

## Волна 3
- [ ] 3.1 AudioHandler tests
- [ ] 3.2 CacheManager tests
- [ ] 3.3 History tests
- [ ] 3.4 DB tests
- [ ] 3.5 CI

## Волна 4
- [ ] 4.1 Структура ui/artic
- [ ] 4.2 Базовые виджеты
- [ ] 4.3 Замена в FullPlayer
- [ ] 4.4 Замена в MiniPlayer
- [ ] 4.5 Замена в остальных

## Волна 5
- [ ] 5.1 Динамическая палитра
- [ ] 5.2 Cover modes
- [ ] 5.3 Visualizer modes
- [ ] 5.4 Progress styles
- [ ] 5.5 Track transition

## Волна 6
- [ ] Micro-interactions

## Волна 7
- [ ] Playlists
- [ ] Synced lyrics
- [ ] Shuffle
- [ ] Crossfade
- [ ] Sleep timer
- [ ] Diagnostics
- [ ] Smart queue

## Волна 8
- [ ] Artic Lab

## Волна 9
- [ ] Visual Modes
- [ ] Shaders (опционально)
- [ ] Grain
- [ ] Real FFT
- [ ] Page transitions

## Волна 10
- [ ] Релизная подготовка

---

# ❌ Что точно НЕ делаем

Совсем. Даже в долгом backlog.

- ❌ Chromecast / AirPlay
- ❌ UGC upload
- ❌ Соц. функции (профили, подписки)
- ❌ Эквалайзер (нет нормального API)
- ❌ Собственный state-management
- ❌ Полный DI-контейнер
- ❌ Замена Flutter на что-то другое
- ❌ Микро-сервисы на каждый чих
- ❌ Локализация (пока)
- ❌ «Собери интерфейс сам» из блоков
```