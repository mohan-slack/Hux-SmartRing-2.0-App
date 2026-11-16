/// Today screen (Home). UI 2.0: the answer first, explanations on tap —
/// see widgets/hux/hux_kit.dart and the "HUX UI Redesign" canvas.
///
/// Talks only to [HealthStore] (to check "have we ever synced"),
/// [SyncService], [ReadoutService], and [ModeService] — never to a
/// RingAdapter or SQL.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/checkin/sleep_checkin.dart';
import '../core/coach/coach_nudges.dart';
import '../core/coach/coach_service.dart';
import '../core/food/nutrients.dart' show MealTypeLabel;
import '../core/home/home_extras.dart';
import '../core/water/water_log.dart';
import '../core/share/summary_text.dart';
import '../widgets/weight_card.dart';
import '../widgets/whatsapp_share.dart';
import '../core/home/home_insights.dart';
import '../core/meaning/daily_readout.dart';
import '../core/meaning/day_plan.dart';
import '../core/meaning/hux_charge.dart' show ChargeLevel, HuxCharge;
import '../core/meaning/evening_timing.dart';
import '../core/meaning/sleep_debt.dart';
import '../core/meaning/step_target.dart';
import '../core/meaning/readout_service.dart';
import '../core/modes/event_mode_engine.dart';
import '../core/modes/mode.dart';
import '../core/modes/mode_service.dart';
import '../core/profile/feature_catalog.dart';
import '../core/profile/profile_service.dart';
import '../core/ring/ring_models.dart';
import '../core/storage/health_store.dart';
import '../core/sync/sync_service.dart';
import '../theme/hux_cards.dart';
import '../theme/hux_glass.dart';
import '../theme/hux_motion.dart';
import '../theme/hux_theme_controller.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';
import 'coach/coach_screen.dart' show coachTopicLook;
import 'for_you.dart';
import '../widgets/hux/hux_3d.dart';
import '../widgets/hux/hux_kit.dart';
import '../widgets/wellness_note.dart';
import 'home/why_sheet.dart';

/// One line combining whichever lifestyle modes are active, or null if
/// none are. Deliberately just concatenation, not a wall of chips —
/// Today's readout is the hero; this rides alongside the event-mode
/// strip as at most one extra line, never a second card.
String? _lifestyleChipText(ActiveContext context) {
  final parts = <String>[];
  if (context.nightShiftActive) parts.add('Night shift');
  if (context.fastDayNumber != null && context.fasting != null) {
    parts.add('${context.fasting!.type.displayName} — '
        'day ${context.fastDayNumber}');
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

enum _Phase { priming, syncing, loadingReadout, ready, error }

/// Some adapters (e.g. the health-app one) use a negative sentinel for
/// "battery read failed/unavailable" rather than a plausible-looking
/// percent — never render that sentinel as a literal number here.
int? _sanitizeBattery(int? raw) => (raw == null || raw < 0) ? null : raw;

class TodayScreen extends StatefulWidget {
  final HealthStore store;
  final SyncService syncService;
  final ReadoutService readoutService;
  final ModeService modeService;

  /// Pinged whenever this tab becomes visible again after the user
  /// switched away and back (see AppShell) — IndexedStack keeps this
  /// screen's State alive rather than rebuilding it, so without this
  /// it would never notice something changed elsewhere (e.g. a mode
  /// started from the Modes tab). Optional: tests that mount
  /// TodayScreen on its own don't need one.
  final Listenable? refreshSignal;

  /// Personalisation — all optional so tests that mount TodayScreen on
  /// its own are unaffected (no "For you" section without them).
  final ProfileService? profileService;
  final FeatureTap? onOpenFeature;
  final VoidCallback? onSeeAllFeatures;

  /// Home header: first name / initial, and taps.
  final String? greetingName;
  final VoidCallback? onOpenProfile;

  /// The "Ask HUX anything" bar (opens the Coach tab); null hides it.
  final VoidCallback? onAsk;

  /// Agenda, food and mini trends for the richer Home; null = none.
  final Future<HomeExtras> Function()? extrasLoader;

  /// Opens the running journey from its Home card.
  final VoidCallback? onOpenJourney;

  /// Opens Cycle from its Home card.
  final VoidCallback? onOpenCycle;

  /// "Coach noticed" card: open the right coach with the question ready.
  final ValueChanged<CoachNudge>? onCoachNudge;

  /// "Not now" on that card (hidden for a few days).
  final ValueChanged<CoachNudge>? onHideCoachNudge;

  /// Called after each readout load (e.g. to re-plan tonight's reminders).
  final ValueChanged<DailyReadout>? onReadout;

  /// Morning "How did you sleep?" card. The app turns it on; widget
  /// tests leave it off (it depends on the real clock).
  final bool morningCheckIn;

  /// Sync in the background on open and whenever the app comes back to
  /// the foreground (throttled), so Home never shows yesterday's data.
  /// Off by default so widget tests stay deterministic.
  final bool autoSync;

  const TodayScreen({
    super.key,
    required this.store,
    required this.syncService,
    required this.readoutService,
    required this.modeService,
    this.refreshSignal,
    this.profileService,
    this.onOpenFeature,
    this.onSeeAllFeatures,
    this.greetingName,
    this.onOpenProfile,
    this.onAsk,
    this.extrasLoader,
    this.autoSync = false,
    this.onOpenJourney,
    this.onOpenCycle,
    this.onCoachNudge,
    this.onHideCoachNudge,
    this.morningCheckIn = false,
    this.onReadout,
  });

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> with WidgetsBindingObserver {
  _Phase _phase = _Phase.loadingReadout;
  DailyReadout? _readout;
  SleepSession? _lastNight;
  ModeStrip? _modeStrip;
  ActiveContext _activeContext = const ActiveContext();
  List<FeatureId> _featured = const [];
  HomeExtras _extras = HomeExtras.empty;
  String? _errorMessage;

  late final SleepCheckInService _checkIns = SleepCheckInService(widget.store);
  bool _askCheckIn = false;
  SleepCheckIn? _previousCheckIn;

  /// Seeded from `syncService.lastRingInfo` right after each sync/load
  /// (an immediate, correct reading), then kept fresh by the live
  /// [SyncService.batteryPercent] subscription below.
  int? _batteryPercent;
  StreamSubscription<int>? _batterySub;

  /// Live instantaneous heart rate for the Home heart-rate stat — a genuine
  /// point reading, not last night's stored average (that comes from
  /// [_lastNight] instead). Null between readings is normal.
  double? _heartRateBpm;

  /// When the last LIVE heart reading arrived (a connected ring only).
  DateTime? _heartLiveAt;
  StreamSubscription<int?>? _heartRateSub;

  @override
  void initState() {
    super.initState();
    widget.refreshSignal?.addListener(_onRefreshSignal);
    if (widget.autoSync) WidgetsBinding.instance.addObserver(this);
    _batterySub = widget.syncService.batteryPercent.listen((percent) {
      if (mounted) setState(() => _batteryPercent = _sanitizeBattery(percent));
    });
    // A missed live reading (motion, poor contact) is normal — only a
    // REAL non-null tick updates the display; it never regresses an
    // already-known-good reading back to a blank dash.
    _heartRateSub = widget.syncService.heartRateBpm.listen((bpm) {
      if (mounted && bpm != null) {
        setState(() {
          _heartRateBpm = bpm.toDouble();
          _heartLiveAt = DateTime.now();
        });
      }
    });
    _bootstrap();
  }

  @override
  void dispose() {
    widget.refreshSignal?.removeListener(_onRefreshSignal);
    if (widget.autoSync) WidgetsBinding.instance.removeObserver(this);
    _batterySub?.cancel();
    _heartRateSub?.cancel();
    super.dispose();
  }

  /// Re-reads the store, but only once we actually have something on
  /// screen to refresh — while still syncing/loading/erroring, the
  /// in-flight bootstrap already has this covered.
  void _onRefreshSignal() {
    if (_phase == _Phase.ready) _loadReadout();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _backgroundSync();
  }

  bool _bgSyncing = false;

  static const _primedKey = 'health_permission_primed';

  /// "Continue without health data": phone-only / denied users still
  /// get Home (check-in, food, plans, coach). Cleared by Connect.
  static const _skippedKey = 'health_skipped';
  bool _healthSkipped = false;

  Future<void> _connectHealth() async {
    try {
      await widget.store.writeSetting(_primedKey, 'yes');
      await widget.store.writeSetting(_skippedKey, 'no');
    } catch (_) {}
    _healthSkipped = false;
    await _bootstrap();
  }

  Future<void> _skipHealth() async {
    try {
      await widget.store.writeSetting(_primedKey, 'yes');
      await widget.store.writeSetting(_skippedKey, 'yes');
    } catch (_) {}
    _healthSkipped = true;
    await _loadReadout();
  }

  /// Quiet sync: pulls new health data without blanking the screen; on
  /// success the readout reloads in place. Failures stay silent here —
  /// pull-to-refresh is where the user asks and hears back.
  Future<void> _backgroundSync() async {
    if (!widget.autoSync || _bgSyncing || _healthSkipped || _phase != _Phase.ready) return;
    _bgSyncing = true;
    try {
      final outcome = await widget.syncService.syncIfStale();
      if (outcome != null && outcome.success && mounted) await _loadReadout();
    } catch (_) {
      // Quiet by design.
    } finally {
      _bgSyncing = false;
    }
  }

  /// First open: sync automatically only if we've never synced before.
  /// Every later open just loads whatever is already on disk.
  Future<void> _bootstrap() async {
    setState(() {
      _phase = _Phase.loadingReadout;
      _errorMessage = null;
    });

    try {
      final everSynced = await widget.store.lastSyncedUpTo() != null;
      _healthSkipped = await widget.store.readSetting(_skippedKey) == 'yes';
      if (!mounted) return;

      if (!everSynced && !_healthSkipped) {
        // First run (app only): explain WHY before the OS permission
        // sheet appears — a cold Health prompt gets denied far more.
        if (widget.autoSync && await widget.store.readSetting(_primedKey) != 'yes') {
          if (mounted) setState(() => _phase = _Phase.priming);
          return;
        }
        setState(() => _phase = _Phase.syncing);
        final outcome = await widget.syncService.syncNow();
        if (!mounted) return;
        if (!outcome.success) {
          _showError(outcome.error);
          return;
        }
      }
    } catch (e) {
      _showError(e.toString());
      return;
    }

    await _loadReadout();
    // Already-synced users: show what's on disk at once, then fetch
    // what's new since last time in the background.
    if (mounted) _backgroundSync();
  }

  /// Any failure lands on the error view (with Retry) — never an endless
  /// "Loading…"/"Syncing…" spinner.
  void _showError(String? message) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _errorMessage = message;
    });
  }

  /// A synced night that ended today: then the card only asks "how
  /// rested?" (the times are already known).
  SleepSession? _deviceNightToday() {
    final n = _lastNight;
    if (n == null) return null;
    final w = n.wakeTime.toLocal(), now = DateTime.now();
    return w.year == now.year && w.month == now.month && w.day == now.day ? n : null;
  }

  Future<void> _saveCheckIn(SleepCheckIn c) async {
    try {
      await _checkIns.save(c);
    } on ArgumentError {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That night looks too short or long — check the times.')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _askCheckIn = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved. Thanks — Charge updated.')));
    await _loadReadout();
  }

  Future<void> _loadReadout() async {
    // Only the very first load shows the full-screen spinner; later
    // reloads (tab switch, background sync) keep the current readout
    // on screen and swap in the new one — no flash, scroll kept.
    if (mounted && _readout == null) setState(() => _phase = _Phase.loadingReadout);
    final DailyReadout readout;
    final SleepSession? lastNight;
    final ModeStrip? modeStrip;
    final ActiveContext activeContext;
    List<FeatureId> featured = const [];
    try {
      readout = await widget.readoutService.today();
      lastNight = await widget.readoutService.lastNight();
      modeStrip = await widget.modeService.currentStrip(readout: readout);
      activeContext = await widget.modeService.activeContext();
      final profileService = widget.profileService;
      if (profileService != null) {
        try {
          featured = await profileService.featured();
        } catch (_) {
          // Personalisation is a bonus: if it fails, Today still shows.
          featured = const [];
        }
      }
    } catch (e) {
      // A failed background reload keeps what's already on screen.
      if (_readout != null) {
        if (mounted) setState(() => _phase = _Phase.ready);
        return;
      }
      _showError(e.toString());
      return;
    }
    var extras = HomeExtras.empty;
    try {
      extras = await widget.extrasLoader?.call() ?? HomeExtras.empty;
    } catch (_) {
      // Extras are a bonus: Home still shows the readout without them.
    }
    var ask = false;
    SleepCheckIn? previous;
    if (widget.morningCheckIn) {
      try {
        ask = await _checkIns.shouldAsk();
        previous = (await _checkIns.all()).lastOrNull;
      } catch (_) {}
    }
    if (!mounted) return;
    try {
      widget.onReadout?.call(readout);
    } catch (_) {}
    setState(() {
      _askCheckIn = ask;
      _previousCheckIn = previous;
      _extras = extras;
      _readout = readout;
      _lastNight = lastNight;
      _modeStrip = modeStrip;
      _activeContext = activeContext;
      _featured = featured;
      // Immediate, correct reading right after a sync — see the field's
      // doc comment. Only overwrites when we actually have one; a
      // subsequent live update from _batterySub can still refine it.
      _batteryPercent = _sanitizeBattery(widget.syncService.lastRingInfo?.batteryPercent) ?? _batteryPercent;
      // Same idea for heart rate: seed from the readout's latest-known
      // reading immediately (see DailyReadout.currentHeartRateBpm), so
      // the card never sits blank waiting for the next live tick.
      _heartRateBpm = readout.currentHeartRateBpm?.toDouble() ?? _heartRateBpm;
      _phase = _Phase.ready;
    });
  }

  /// Pull-to-refresh: sync, then reload. A sync failure here doesn't
  /// blank out an already-visible readout — it just says so quietly.
  Future<void> _refresh() async {
    if (_healthSkipped) {
      await _loadReadout(); // nothing to sync until they connect
      return;
    }
    final outcome = await widget.syncService.syncNow();
    if (!mounted) return;
    if (!outcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // Say WHY (no permission, no Health Connect…), not just "failed".
          content: Text(outcome.error == null || outcome.error!.isEmpty
              ? "Couldn't sync your health data — try again."
              : "Couldn't sync: ${outcome.error!.replaceFirst(RegExp(r'^\w*Exception(\([^)]*\))?:\s*'), '')}"),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'Retry', onPressed: _refresh),
        ),
      );
      return;
    }
    await _loadReadout();
  }

  /// Today as a WhatsApp message (built when the user taps share).
  Future<String?> _todaySummary() async {
    final r = _readout;
    if (r == null) return null;
    final food = _extras.food;
    var water = _extras.water?.glasses;
    try {
      water = await WaterLog(widget.store).today(); // the tile counts taps itself
    } catch (_) {}
    final steps = r.plan?.steps;
    return SummaryText.daily(
      now: DateTime.now(),
      name: widget.greetingName,
      charge: r.charge?.value,
      chargeLabel: r.charge?.value == null ? null : r.charge?.label,
      sleepMin: _lastNight?.totalSleep.inMinutes,
      steps: steps?.today,
      stepGoal: steps?.target,
      proteinG: food?.proteinG.round(),
      proteinGoalG: food?.proteinGoalG.round(),
      kcal: food?.kcal.round(),
      waterGlasses: water,
      waterGoal: _extras.water?.goal.glasses,
    );
  }

  @override
  Widget build(BuildContext context) => _buildBody();

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.priming:
        return _HealthPrimingView(onConnect: _connectHealth, onSkip: _skipHealth);
      case _Phase.syncing:
        return const _MessageView(message: 'Syncing your health data…');
      case _Phase.loadingReadout:
        return const _MessageView(message: 'Loading your readout…');
      case _Phase.error:
        return _ErrorView(
          message: _errorMessage,
          onRetry: _bootstrap,
          onSkip: _skipHealth,
        );
      case _Phase.ready:
        return RefreshIndicator(
          onRefresh: _refresh,
          child: _ReadoutBody(
            readout: _readout!,
            lastNight: _lastNight,
            modeStrip: _modeStrip,
            activeContext: _activeContext,
            batteryPercent: _batteryPercent,
            heartRateBpm: _heartRateBpm,
            heartLive: _heartLiveAt != null && DateTime.now().difference(_heartLiveAt!) < const Duration(seconds: 30),
            sendTestBuzz: widget.syncService.sendTestBuzz,
            featured: _featured,
            onOpenFeature: widget.onOpenFeature,
            onSeeAllFeatures: widget.onSeeAllFeatures,
            greetingName: widget.greetingName,
            onOpenProfile: widget.onOpenProfile,
            onAsk: widget.onAsk,
            extras: _extras,
            onOpenJourney: widget.onOpenJourney,
            onOpenCycle: widget.onOpenCycle,
            onCoachNudge: widget.onCoachNudge,
            onHideCoachNudge: widget.onHideCoachNudge,
            connectCard: _healthSkipped ? _ConnectHealthTile(onConnect: _connectHealth) : null,
            shareCard: _extras.water == null
                ? null
                : WhatsAppShareButton(label: 'Share today on WhatsApp', text: _todaySummary),
            weightCard: _extras.water == null
                ? null
                : WeightCard(
                    store: widget.store,
                    onlyWhenDue: true,
                    refreshSignal: widget.refreshSignal,
                    padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, 12, HuxSpacing.lg, 0),
                  ),
            waterCard: _extras.water == null
                ? null
                : _WaterTile(
                    key: ValueKey('water-${_extras.water!.glasses}-${_extras.water!.goal.glasses}'),
                    log: WaterLog(widget.store),
                    today: _extras.water!,
                  ),
            checkInCard: _askCheckIn
                ? _SleepCheckInCard(
                    deviceNight: _deviceNightToday(),
                    previous: _previousCheckIn,
                    onSave: _saveCheckIn,
                    onSkip: () {
                      setState(() => _askCheckIn = false);
                      _checkIns.skipToday().catchError((Object _) {});
                    },
                  )
                : null,
          ),
        );
    }
  }
}

class _MessageView extends StatelessWidget {
  final String message;

  const _MessageView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: HuxSpacing.lg),
          Text(message, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// A failed BLE sync is normal, not an emergency — no red dialogs.
class _ErrorView extends StatelessWidget {
  final String? message;
  final VoidCallback onRetry;
  final VoidCallback? onSkip;

  const _ErrorView({required this.message, required this.onRetry, this.onSkip});

  /// Strips a raw exception's `SomeException: ` prefix — the detail text
  /// underneath the calm headline should read like a sentence, not a
  /// stack trace.
  static String _friendly(String? raw) {
    if (raw == null || raw.isEmpty) {
      return 'It happens — check your health app is set up, then try again.';
    }
    return raw.replaceFirst(RegExp(r'^\w*Exception:\s*'), '');
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(HuxSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_problem_rounded,
                size: 40, color: HuxColors.mutedText),
            const SizedBox(height: HuxSpacing.md),
            Text("Couldn't sync your health data",
                style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: HuxSpacing.xs),
            Text(
              _friendly(message),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: HuxSpacing.lg),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
            const SizedBox(height: HuxSpacing.sm),
            // Denied access or no Health Connect: give a way forward,
            // not just "Retry" (Android stops re-showing the dialog).
            if (Platform.isIOS)
              TextButton.icon(
                onPressed: () => openHealthHelp(context, Uri.parse('x-apple-health://')),
                icon: const Icon(Icons.favorite_border_rounded),
                label: const Text('Open the Health app'),
              )
            else if (Platform.isAndroid) ...[
              TextButton.icon(
                onPressed: () => openHealthHelp(
                    context, Uri.parse('market://details?id=com.google.android.apps.healthdata'),
                    fallback: Uri.parse('https://play.google.com/store/apps/details?id=com.google.android.apps.healthdata')),
                icon: const Icon(Icons.download_rounded),
                label: const Text('Get Health Connect'),
              ),
            ],
            if (Platform.isIOS)
              Padding(
                padding: const EdgeInsets.only(top: HuxSpacing.xs),
                child: Text('In Health: your profile → Apps → HUX → turn on the data to share.',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
              )
            else if (Platform.isAndroid)
              Padding(
                padding: const EdgeInsets.only(top: HuxSpacing.xs),
                child: Text('Then: Settings → Health Connect → App permissions → HUX → Allow all.',
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
              ),
            if (onSkip != null) ...[
              const SizedBox(height: HuxSpacing.lg),
              OutlinedButton(onPressed: onSkip, child: const Text('Continue without health data')),
              const SizedBox(height: HuxSpacing.xs),
              Text('You can tell HUX how you slept each morning instead. Connect any time from Home.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.labelSmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Opens [uri] (the Health app / Play Store page), falling back to
/// [fallback], and says so if neither can open.
Future<void> openHealthHelp(BuildContext context, Uri uri, {Uri? fallback}) async {
  var ok = false;
  try {
    ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && fallback != null) {
    try {
      ok = await launchUrl(fallback, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open it — find it in your phone's settings.")));
  }
}

/// Shown once, before the first Health permission sheet: what HUX
/// reads and why, so the OS prompt isn't a surprise.
class _HealthPrimingView extends StatelessWidget {
  final VoidCallback onConnect;
  final VoidCallback? onSkip;

  const _HealthPrimingView({required this.onConnect, this.onSkip});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final app = Platform.isIOS ? 'Apple Health' : 'Health Connect';
    Widget row(IconData icon, Color color, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: HuxSpacing.xs),
          child: Row(
            children: [
              HuxIconBadge(icon: icon, color: color, size: 36),
              const SizedBox(width: HuxSpacing.md),
              Expanded(child: Text(label, style: text.bodyMedium)),
            ],
          ),
        );
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(HuxSpacing.xl, HuxSpacing.xl, HuxSpacing.xl, HuxGlass.navClearance),
        children: [
          const HuxIconBadge(icon: Icons.favorite_rounded, color: HuxColors.ringHeart, size: 64),
          const SizedBox(height: HuxSpacing.lg),
          Text('Connect your health data', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: HuxSpacing.sm),
          Text(
            'HUX reads from $app — whatever your phone, watch or band already records — '
            'to show your charge, sleep, steps and plans.',
            style: text.bodyMedium?.copyWith(color: HuxColors.mutedText),
          ),
          const SizedBox(height: HuxSpacing.lg),
          row(Icons.directions_walk_rounded, HuxColors.ringSteps, 'Steps and active energy'),
          row(Icons.bedtime_rounded, HuxColors.ringSleep, 'Sleep'),
          row(Icons.monitor_heart_outlined, HuxColors.ringHeart, 'Heart rate, HRV, blood oxygen, breathing rate'),
          const SizedBox(height: HuxSpacing.lg),
          Text(
            'Read-only: HUX never writes to $app. Your data stays on this phone and is never '
            'used for ads. On the next screen, tap "Allow" / turn on all categories.',
            style: text.bodySmall?.copyWith(color: HuxColors.mutedText),
          ),
          const SizedBox(height: HuxSpacing.xl),
          SizedBox(
            height: 52,
            child: FilledButton(onPressed: onConnect, child: const Text('Continue')),
          ),
          if (onSkip != null) ...[
            const SizedBox(height: HuxSpacing.sm),
            TextButton(onPressed: onSkip, child: const Text('Skip — I don\'t use a health app')),
          ],
        ],
      ),
    );
  }
}

/// Home (UI 2.0): the answer first, explanations on tap.
/// Charge hero → Next up → your day → last night → steps / protein →
/// heart / programs → mode → bedtimes this week. Paragraphs live in
/// the Why sheet (see screens/home/why_sheet.dart).
class _ReadoutBody extends StatelessWidget {
  final DailyReadout readout;
  final SleepSession? lastNight;
  final ModeStrip? modeStrip;
  final ActiveContext activeContext;
  final int? batteryPercent;
  final double? heartRateBpm;
  final bool heartLive;
  final Future<void> Function() sendTestBuzz;
  final List<FeatureId> featured;
  final FeatureTap? onOpenFeature;
  final VoidCallback? onSeeAllFeatures;
  final String? greetingName;
  final VoidCallback? onOpenProfile;
  final VoidCallback? onAsk;
  final HomeExtras extras;
  final VoidCallback? onOpenJourney;
  final VoidCallback? onOpenCycle;
  final ValueChanged<CoachNudge>? onCoachNudge;
  final ValueChanged<CoachNudge>? onHideCoachNudge;
  final Widget? checkInCard;
  final Widget? connectCard;
  final Widget? waterCard;
  final Widget? weightCard;
  final Widget? shareCard;

  const _ReadoutBody({
    required this.readout,
    required this.lastNight,
    required this.modeStrip,
    required this.activeContext,
    required this.batteryPercent,
    required this.heartRateBpm,
    this.heartLive = false,
    required this.sendTestBuzz,
    this.featured = const [],
    this.onOpenFeature,
    this.onSeeAllFeatures,
    this.greetingName,
    this.onOpenProfile,
    this.onAsk,
    this.extras = HomeExtras.empty,
    this.onOpenJourney,
    this.onOpenCycle,
    this.onCoachNudge,
    this.onHideCoachNudge,
    this.checkInCard,
    this.connectCard,
    this.waterCard,
    this.weightCard,
    this.shareCard,
  });

  void _open(FeatureId id) => onOpenFeature?.call(id);

  void _why(BuildContext context) => showWhySheet(
        context,
        readout: readout,
        insights: extras.insights,
        lastNight: lastNight,
        heartRateBpm: heartRateBpm,
      );

  @override
  Widget build(BuildContext context) {
    final chipText = _lifestyleChipText(activeContext);
    final plan = readout.plan;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final insights = extras.insights;
    const gap = SizedBox(height: 12);
    const side = EdgeInsets.symmetric(horizontal: HuxSpacing.lg);

    Widget pad(Widget w) => Padding(padding: side, child: w);

    final next = _nextUp(plan, nowMin);
    final events = _dayEvents(plan, nowMin);
    final night = lastNight;
    final food = extras.food;
    final rhr = insights.restingHr7;
    final lastRhr = rhr.whereType<int>().isEmpty ? null : rhr.whereType<int>().last;
    final programs = <Widget>[
      if (extras.journey != null)
        HuxProgramPill(
          progress: extras.journey!.doneToday ? 1 : extras.journey!.ticksDone / 3,
          center: extras.journey!.doneToday ? '✓' : '${extras.journey!.ticksDone}/3',
          title: extras.journey!.title,
          subtitle: extras.journey!.paused ? 'paused' : 'day ${extras.journey!.day}',
          color: HuxColors.accentPurple,
          onTap: onOpenJourney,
        ),
      if (extras.cycle != null)
        HuxProgramPill(
          progress: extras.cycle!.day == null ? 0 : extras.cycle!.day! / extras.cycle!.cycleDays,
          center: extras.cycle!.locked || extras.cycle!.day == null ? '·' : '${extras.cycle!.day}',
          title: extras.cycle!.locked ? 'Cycle' : extras.cycle!.title,
          subtitle: extras.cycle!.locked ? 'locked' : extras.cycle!.line,
          color: HuxColors.accentPink,
          onTap: onOpenCycle,
        ),
    ];

    return ListView(
      // Bottom clearance: content scrolls behind the floating nav bar.
      padding: const EdgeInsets.fromLTRB(0, HuxSpacing.sm, 0, HuxGlass.navClearance),
      children: [
        pad(HuxEntrance(child: _Hero(
          readout: readout,
          name: greetingName,
          chipText: chipText,
          onOpenProfile: onOpenProfile,
          onWhy: () => _why(context),
          sleep: lastNight?.totalSleep,
          restingBpm: lastRhr,
          onSleep: () => _open(FeatureId.sleepRegularity),
          onEffort: () => _open(FeatureId.effortTarget),
        ))),
        if (checkInCard != null) ...[gap, pad(HuxEntrance(index: 1, child: checkInCard!))],
        if (connectCard != null) ...[gap, pad(connectCard!)],
        if (next != null) ...[gap, pad(HuxEntrance(index: 1, child: next))],
        if (extras.coachNudge != null && onCoachNudge != null) ...[
          gap,
          pad(HuxEntrance(
            index: 1,
            child: _CoachNoticedCard(
              nudge: extras.coachNudge!,
              onAsk: () => onCoachNudge!(extras.coachNudge!),
              onLogMeal: () => _open(FeatureId.proteinGap),
              onHide: onHideCoachNudge == null ? null : () => onHideCoachNudge!(extras.coachNudge!),
            ),
          )),
        ],
        if (events.isNotEmpty) ...[
          gap,
          pad(HuxEntrance(
            index: 1,
            child: HuxTile(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HuxTileLabel('Your day'),
                  const SizedBox(height: 4),
                  HuxDayLine(events: events, nowMinute: nowMin),
                ],
              ),
            ),
          )),
        ],
        if (night != null) ...[
          gap,
          pad(HuxEntrance(index: 2, child: _LastNightTile(
            night: night,
            debt: extras.sleepDebt,
            goal: plan?.bedtime?.sleepGoal ?? const Duration(hours: 8),
            targetBed: plan?.bedtime?.bedtime.toLocal(),
            onTap: () => _open(FeatureId.sleepRegularity),
          ))),
        ],
        gap,
        pad(HuxEntrance(
          index: 2,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _StepsTile(steps: plan?.steps, byHour: insights.stepsByHour, distanceM: extras.distanceTodayM)),
              const SizedBox(width: 12),
              Expanded(
                child: food == null
                    ? _LogMealTile(onTap: () => _open(FeatureId.proteinGap))
                    : _ProteinTile(food: food, onTap: () => _open(FeatureId.proteinGap)),
              ),
            ],
          ),
        )),
        if (waterCard != null) ...[
          gap,
          pad(HuxEntrance(index: 3, child: waterCard!)),
        ],
        if (weightCard != null) weightCard!,
        if (lastRhr != null || heartRateBpm != null) ...[
          gap,
          pad(HuxEntrance(
            index: 3,
            child: _HeartTile(
              bpm: heartRateBpm?.round(),
              live: heartLive,
              resting: lastRhr,
              resting7: rhr,
              hrvMs: lastNight?.avgHrvMs,
              stress: readout.stressIndex,
              onTap: () => _why(context),
            ),
          )),
        ],
        if (programs.isNotEmpty) ...[
          gap,
          pad(HuxEntrance(
            index: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < programs.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: programs[i]),
                ],
              ],
            ),
          )),
        ],
        if (modeStrip != null) ...[gap, pad(HuxEntrance(index: 3, child: _ModeStripCard(strip: modeStrip!)))],
        if (insights.hasWeek) ...[
          gap,
          pad(HuxEntrance(index: 3, child: _BedtimesTile(
            insights: insights,
            targetBed: plan?.bedtime?.bedtime.toLocal(),
            onTap: () => _open(FeatureId.sleepRegularity),
          ))),
        ],
        if (batteryPercent != null) ...[
          gap,
          pad(_RingCard(batteryPercent: batteryPercent!, sendTestBuzz: sendTestBuzz)),
        ],
        if (featured.isNotEmpty && onOpenFeature != null && onSeeAllFeatures != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          pad(ForYouSection(featured: featured, onOpen: onOpenFeature!, onSeeAll: onSeeAllFeatures!)),
        ],
        if (shareCard != null) ...[
          const SizedBox(height: HuxSpacing.sm),
          shareCard!,
        ],
        const SizedBox(height: HuxSpacing.md),
        Center(child: _DataQualityCaption(quality: readout.dataQuality)),
        pad(const WellnessNote()),
      ],
    );
  }

  /// ONE thing to do next: the first agenda item still ahead, else the
  /// step goal. Null when there's nothing worth a button.
  Widget? _nextUp(DayPlan? plan, int nowMin) {
    for (final e in extras.agenda) {
      if (e.done || e.minuteOfDay < nowMin - 30) continue;
      final (icon, color) = _agendaStyle(e.kind);
      return HuxNextUp(
        icon: icon,
        object: switch (e.kind) {
          AgendaKind.air => Hux3D.sun,
          AgendaKind.walk => Hux3D.shoe,
          AgendaKind.plan => Hux3D.pin,
          AgendaKind.journal => Hux3D.book,
        },
        color: color,
        title: e.title,
        subtitle: e.time,
        actionLabel: 'Open',
        onAction: e.feature == null || onOpenFeature == null ? null : () => _open(e.feature!),
      );
    }
    final steps = plan?.steps;
    if (steps != null && !steps.done) {
      return HuxNextUp(
        icon: Icons.directions_walk_rounded,
        object: Hux3D.shoe,
        color: HuxColors.ringFood,
        title: 'Walk ${steps.minutesToGo} min',
        subtitle: '${StepTargetCalculator.formatSteps(steps.remaining)} steps to go',
        actionLabel: 'Plans',
        onAction: onOpenFeature == null ? null : () => _open(FeatureId.beginnerWalkPlan),
      );
    }
    return null;
  }

  static (IconData, Color) _agendaStyle(AgendaKind k) => switch (k) {
        AgendaKind.air => (Icons.air_rounded, HuxColors.steady),
        AgendaKind.walk => (Icons.directions_walk_rounded, HuxColors.ringFood),
        AgendaKind.plan => (Icons.directions_run_rounded, HuxColors.ringSteps),
        AgendaKind.journal => (Icons.edit_note_rounded, HuxColors.ringHabit),
      };

  static String _short(AgendaKind k) => switch (k) {
        AgendaKind.air => 'Walk',
        AgendaKind.walk => 'Walk',
        AgendaKind.plan => 'Plan',
        AgendaKind.journal => 'Journal',
      };

  List<HuxDayEvent> _dayEvents(DayPlan? plan, int nowMin) {
    final out = <HuxDayEvent>[];
    final wake = lastNight?.wakeTime.toLocal();
    final today = DateTime.now();
    if (wake != null && wake.day == today.day && wake.hour >= 4) {
      out.add(HuxDayEvent(minuteOfDay: wake.hour * 60 + wake.minute, label: 'Wake', color: huxInk, done: true));
    }
    for (final e in extras.agenda) {
      out.add(HuxDayEvent(minuteOfDay: e.minuteOfDay, label: _short(e.kind), color: _agendaStyle(e.kind).$2, done: e.done));
    }
    final bed = plan?.bedtime?.bedtime.toLocal();
    if (bed != null) {
      var m = bed.hour * 60 + bed.minute;
      if (m < 6 * 60) m += 24 * 60; // after midnight: the line extends to it
      out.add(HuxDayEvent(minuteOfDay: m, label: 'Bed', color: HuxColors.ringSleep, time: huxClock(bed)));
      // Tonight's timing, only while it's still ahead (it's what you can act on).
      final t = EveningTiming.forBed(bed);
      final now = DateTime.now();
      for (final (at, label, color) in [
        (t.lastCaffeine, 'Last chai', HuxColors.ringSteps),
        (t.lastMeal, 'Dinner by', HuxColors.ringFood),
      ]) {
        if (!at.isAfter(now) || at.day != now.day) continue;
        out.add(HuxDayEvent(minuteOfDay: at.hour * 60 + at.minute, label: label, color: color, time: huxClock(at)));
      }
    }
    // At most 5, so labels stay readable: the next 4 coming up, plus the
    // most recent one done (so the line still shows where you are).
    out.sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));
    if (out.length <= 5) return out;
    final ahead = out.where((e) => e.minuteOfDay >= nowMin).toList();
    final past = out.where((e) => e.minuteOfDay < nowMin).toList();
    if (ahead.length >= 5) return ahead.take(5).toList();
    return [...past.sublist(past.length - (5 - ahead.length)), ...ahead];
  }
}

/// The one dark surface: greeting, the Charge ring, one line.
class _Hero extends StatelessWidget {
  final DailyReadout readout;
  final String? name;
  final String? chipText;
  final VoidCallback? onOpenProfile;
  final VoidCallback onWhy;

  /// The three glass stats under the orb (each hidden without data).
  final Duration? sleep;
  final int? restingBpm;
  final VoidCallback? onSleep;
  final VoidCallback? onEffort;

  const _Hero({
    required this.readout,
    required this.name,
    required this.chipText,
    required this.onOpenProfile,
    required this.onWhy,
    this.sleep,
    this.restingBpm,
    this.onSleep,
    this.onEffort,
  });

  static String _sleepText(Duration d) => '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  static String _greeting(int hour) => hour < 5
      ? 'Good night'
      : hour < 12
          ? 'Morning'
          : hour < 17
              ? 'Afternoon'
              : 'Evening';

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final charge = readout.charge;
    final state = readout.state;
    final first = name?.trim().split(' ').first;
    final stateLabel = charge?.label ?? 'Learning';
    // The label is about Charge NOW; the readout headline is about last
    // night's recovery. When the day has drained a normal morning, say so
    // instead of "Running low · Right in your normal range".
    final labelColor = switch (charge?.level) {
      ChargeLevel.full || ChargeLevel.good => HuxColors.recharged,
      ChargeLevel.low => HuxColors.stretched,
      ChargeLevel.veryLow => HuxColors.rundown,
      null => state.huxColor,
    };
    final morning = charge?.morningCharge;
    final drained = charge?.value != null && morning != null && morning - charge!.value! >= 15;
    final lowNow = charge?.level == ChargeLevel.low || charge?.level == ChargeLevel.veryLow;
    final recoveredOk = state == RecoveryState.recharged || state == RecoveryState.steady;
    // Keep last night's headline; add one line that explains the drop.
    final dayUsedIt = drained && lowNow && recoveredOk;
    // A short night explains a low number even when it was "usual" for you.
    final dayNote = charge?.shortSleep == true
        ? charge!.reason
        : dayUsedIt
            ? 'You started at $morning this morning — the day used the rest.'
            : null;
    final effort = readout.plan?.effort;
    final dark = HuxPalette.current.dark;
    final stats = <Widget>[
      if (sleep != null && sleep!.inMinutes >= 60)
        _HeroStat(object: Hux3D.moon, color: HuxColors.ringSleep, value: _sleepText(sleep!), label: 'Sleep', onTap: onSleep),
      if (effort != null)
        _HeroStat(
            object: Hux3D.flame,
            color: HuxColors.ringSteps,
            value: '${effort.min}–${effort.max}',
            label: 'Effort today',
            onTap: onEffort),
      if (restingBpm != null)
        _HeroStat(object: Hux3D.heart, color: HuxColors.ringHeart, value: '$restingBpm', label: 'Resting bpm', onTap: onWhy),
    ];
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: dark ? const Color(0xFF24123E) : huxNight, borderRadius: BorderRadius.circular(28)),
      child: Stack(
        children: [
          // Two soft brand glows behind the content.
          const Positioned(left: -50, top: 30, child: _HeroGlow(Color(0x61F567B5), 240)),
          const Positioned(right: -70, bottom: -70, child: _HeroGlow(Color(0x575B6CF0), 230)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            // The buttons inside need a Material above them for ink.
            child: Material(
              type: MaterialType.transparency,
              child: _content(context, first, now, charge, stateLabel, labelColor, dayUsedIt, dayNote, stats, dark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, String? first, DateTime now, HuxCharge? charge, String stateLabel,
      Color labelColor, bool dayUsedIt, String? dayNote, List<Widget> stats, bool dark) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_days[now.weekday - 1]} ${now.day} ${_months[now.month - 1]}',
                        style: const TextStyle(fontSize: 15, color: huxNightMuted)),
                    Text(first == null || first.isEmpty ? _greeting(now.hour) : '${_greeting(now.hour)}, $first',
                        style: huxDisplay(21, color: Colors.white)),
                  ],
                ),
              ),
              // Quick light / dark switch (the full choice is in Profile).
              Semantics(
                button: true,
                label: dark ? 'Switch to light theme' : 'Switch to dark theme',
                child: InkWell(
                  onTap: () => HuxThemeController.instance.setChoice(dark ? HuxThemeChoice.light : HuxThemeChoice.dark),
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0x14FFFFFF),
                      border: Border.all(color: const Color(0xFF4A3A63)),
                    ),
                    child: Icon(dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                        size: 20, color: dark ? const Color(0xFFFFD98A) : const Color(0xFFC9CFFF)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (onOpenProfile != null)
                Semantics(
                  button: true,
                  label: 'Profile and settings',
                  child: InkWell(
                    onTap: onOpenProfile,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 44,
                      height: 44,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF2A1A40),
                        border: Border.all(color: const Color(0xFF4A3A63)),
                      ),
                      child: Text((first == null || first.isEmpty ? 'H' : first[0]).toUpperCase(),
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                    ),
                  ),
                ),
            ],
          ),
          if (chipText != null) ...[
            const SizedBox(height: 10),
            HuxStatChip(chipText!, onDark: true),
          ],
          const SizedBox(height: 18),
          Row(
            children: [
              Semantics(
                button: true,
                label: charge?.value == null ? 'Charge not ready yet' : 'Charge ${charge!.value}, $stateLabel. See why.',
                excludeSemantics: true,
                child: GestureDetector(onTap: onWhy, child: HuxChargeOrb(value: charge?.value, size: 140, animate: true)),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // State as a pill with a dot: readable at a glance.
                    Container(
                      padding: const EdgeInsets.fromLTRB(9, 4, 11, 4),
                      decoration: BoxDecoration(
                        color: labelColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: labelColor.withValues(alpha: 0.45)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 7, height: 7, decoration: BoxDecoration(color: labelColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(dayUsedIt && !(charge?.shortSleep ?? false) ? '$stateLabel now' : stateLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color.lerp(labelColor, Colors.white, 0.55),
                                )),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(readout.headline, style: huxDisplay(19, color: Colors.white, height: 1.22)),
                    if (dayNote != null) ...[
                      const SizedBox(height: 4),
                      Text(dayNote, style: const TextStyle(fontSize: 13, height: 1.3, color: Color(0xCCFFFFFF))),
                    ],
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: onWhy,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFFD6EE),
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 36),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                      child: Text(charge?.value == null ? 'What HUX needs →' : 'Why ${charge!.value} →',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                for (var i = 0; i < stats.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: stats[i]),
                ],
              ],
            ),
          ],
        ],
    );
  }
}

/// Heart: the latest reading with a beating heart and a moving trace.
/// "LIVE" only while a connected ring is streaming; from the health app
/// it is the latest synced reading, and says so.
class _HeartTile extends StatefulWidget {
  final int? bpm;
  final bool live;
  final int? resting;
  final List<int?> resting7;
  final int? hrvMs;
  final int? stress;
  final VoidCallback onTap;

  const _HeartTile({
    required this.bpm,
    required this.live,
    required this.resting,
    required this.resting7,
    required this.hrvMs,
    required this.stress,
    required this.onTap,
  });

  @override
  State<_HeartTile> createState() => _HeartTileState();
}

class _HeartTileState extends State<_HeartTile> with SingleTickerProviderStateMixin {
  static final bool _inTest = Platform.environment.containsKey('FLUTTER_TEST');

  // One loop = one beat of the heart and one sweep of the trace.
  late final AnimationController _c = AnimationController(vsync: this, duration: _beat);

  Duration get _beat => Duration(milliseconds: (60000 / (widget.bpm ?? widget.resting ?? 60).clamp(40, 180)).round());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final on = !reduce && !_inTest;
    if (on && !_c.isAnimating) {
      _c.repeat();
    } else if (!on && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didUpdateWidget(_HeartTile old) {
    super.didUpdateWidget(old);
    if (_c.duration != _beat) {
      _c.duration = _beat;
      if (_c.isAnimating) _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static String _stressWord(int v) => v < 34
      ? 'Low'
      : v < 67
          ? 'Medium'
          : 'High';

  @override
  Widget build(BuildContext context) {
    final shown = widget.bpm ?? widget.resting;
    final resting = widget.resting;
    final bpm = widget.bpm;
    // Compared with YOUR resting heart, in plain words.
    final (String word, HuxTone tone)? state = bpm == null || resting == null
        ? null
        : bpm <= resting + 15
            ? ('Calm', HuxTone.good)
            : bpm <= resting + 45
                ? ('Active', HuxTone.neutral)
                : ('High', HuxTone.watch);
    final stats = <(String, String)>[
      if (bpm != null && resting != null) ('At rest', '$resting bpm'),
      if (widget.hrvMs != null) ('Night HRV', '${widget.hrvMs} ms'),
      if (widget.stress != null) ('Stress now', _stressWord(widget.stress!)),
    ];
    return HuxTile(
      onTap: widget.onTap,
      semanticLabel: shown == null
          ? 'Heart rate not available yet'
          : '${bpm == null ? 'Resting heart' : 'Heart rate'} $shown beats per minute',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: HuxTileLabel(bpm == null ? 'Resting heart' : 'Heart now')),
                if (widget.live)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFC8323A), borderRadius: BorderRadius.circular(8)),
                    child: const Text('LIVE',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white)),
                  )
                else if (bpm != null)
                  Text('latest reading', style: TextStyle(fontSize: 13, color: huxMuted)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                AnimatedBuilder(
                  animation: _c,
                  builder: (context, child) {
                    // Two quick pulses per loop, like a heartbeat.
                    final t = _c.value;
                    final pulse = t < 0.12
                        ? t / 0.12
                        : t < 0.24
                            ? 1 - (t - 0.12) / 0.12
                            : t < 0.36
                                ? (t - 0.24) / 0.12 * 0.6
                                : t < 0.48
                                    ? 0.6 * (1 - (t - 0.36) / 0.12)
                                    : 0.0;
                    return Transform.scale(scale: 1 + 0.12 * pulse, child: child);
                  },
                  child: const Hux3DObject(Hux3D.heart, color: HuxColors.ringHeart, size: 52, animate: false),
                ),
                const SizedBox(width: 10),
                HuxTileValue(shown == null ? '—' : '$shown', unit: 'bpm', size: 40),
                const Spacer(),
                if (state != null) HuxStatChip(state.$1, tone: state.$2),
              ],
            ),
            const SizedBox(height: 10),
            if (bpm != null)
              SizedBox(
                height: 54,
                width: double.infinity,
                child: AnimatedBuilder(
                  animation: _c,
                  builder: (context, _) => CustomPaint(painter: _HeartTracePainter(phase: _c.value)),
                ),
              )
            else
              HuxSparkline(values: widget.resting7, color: HuxColors.ringHeart),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
                        decoration: BoxDecoration(color: HuxColors.bg, borderRadius: BorderRadius.circular(14)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(stats[i].$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: huxMuted)),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(stats[i].$2, style: huxDisplay(15)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A heartbeat-shaped trace that scrolls with [phase] (0..1 = one beat).
class _HeartTracePainter extends CustomPainter {
  final double phase;

  _HeartTracePainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    const beatW = 96.0;
    final mid = size.height * 0.62;
    final path = Path();
    var x = -beatW * phase;
    path.moveTo(x, mid);
    while (x < size.width + beatW) {
      path
        ..lineTo(x + 26, mid)
        ..lineTo(x + 33, mid - 7)
        ..lineTo(x + 40, mid)
        ..lineTo(x + 50, mid)
        ..lineTo(x + 56, mid - size.height * 0.56)
        ..lineTo(x + 64, mid + size.height * 0.34)
        ..lineTo(x + 71, mid)
        ..lineTo(x + beatW, mid);
      x += beatW;
    }
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);
    // Soft fill under the line, then the line itself in the brand sweep.
    final fill = Path.from(path)
      ..lineTo(size.width + beatW, size.height)
      ..lineTo(-beatW, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x29E5484D), Color(0x00E5484D)],
        ).createShader(rect),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..shader = const LinearGradient(colors: [Color(0xFFFF8FCB), Color(0xFFE5484D), Color(0xFF8B3FD0)]).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeartTracePainter o) => o.phase != phase;
}

/// A soft round glow painted behind the hero's content.
class _HeroGlow extends StatelessWidget {
  final Color color;
  final double size;

  const _HeroGlow(this.color, this.size);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
          ),
        ),
      );
}

/// One glass stat inside the hero: 3D object, value, label.
class _HeroStat extends StatelessWidget {
  final Hux3D object;
  final Color color;
  final String value;
  final String label;
  final VoidCallback? onTap;

  const _HeroStat({required this.object, required this.color, required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: onTap != null,
      label: '$label $value',
      excludeSemantics: true,
      child: Material(
        color: const Color(0x12FFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFF4A3A63)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 10),
            child: Column(
              children: [
                Hux3DObject(object, color: color, size: 36),
                const SizedBox(height: 2),
                FittedBox(fit: BoxFit.scaleDown, child: Text(value, style: huxDisplay(15, color: Colors.white, height: 1.1))),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: huxNightMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LastNightTile extends StatelessWidget {
  final SleepSession night;
  final Duration goal;
  final DateTime? targetBed;
  final VoidCallback onTap;
  final SleepDebt? debt;

  const _LastNightTile({required this.night, required this.goal, required this.targetBed, required this.onTap, this.debt});

  static String _hm(Duration d) => '${d.inHours}h ${(d.inMinutes % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final hasStages = night.stageTotal(SleepStage.deep) > Duration.zero || night.stageTotal(SleepStage.rem) > Duration.zero;
    final chips = <String>[
      if (hasStages) 'Deep ${_hm(night.stageTotal(SleepStage.deep))}',
      if (hasStages) 'REM ${_hm(night.stageTotal(SleepStage.rem))}',
      if (night.avgRespiratoryRateBrpm != null) 'Breathing ${night.avgRespiratoryRateBrpm!.round()}/min',
      if (night.minSpo2Percent != null) 'SpO2 min ${night.minSpo2Percent}%',
    ];
    final d = debt;
    // The week, not just the night: debt first, it's what you can act on.
    if (d != null && d.hasDebt) {
      chips.insert(0, 'Sleep debt ${d.label} this week');
    } else if (d != null && d.nights >= 5) {
      chips.insert(0, 'No sleep debt this week');
    }
    return HuxTile(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HuxTileLabel('Last night', trailing: Text('goal ${goal.inHours}h${goal.inMinutes % 60 == 0 ? '' : ' ${goal.inMinutes % 60}m'}',
              style: TextStyle(fontSize: 14, color: huxMuted))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: HuxTileValue(_hm(night.totalSleep), size: 32)),
              const Hux3DObject(Hux3D.moon, color: HuxColors.ringSleep, size: 44),
            ],
          ),
          const SizedBox(height: 12),
          HuxSleepWindow(bed: night.bedtime.toLocal(), wake: night.wakeTime.toLocal(), targetBed: targetBed),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final c in chips) HuxStatChip(c)]),
          ],
        ],
      ),
    );
  }
}

class _StepsTile extends StatelessWidget {
  final StepTarget? steps;
  final List<int> byHour;

  /// Today's walking distance in metres (from the health app), if any.
  final double? distanceM;

  const _StepsTile({required this.steps, required this.byHour, this.distanceM});

  @override
  Widget build(BuildContext context) {
    final s = steps;
    return HuxTile(
      semanticLabel: s == null ? 'Steps not available yet' : 'Steps ${s.today} of ${s.target}',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HuxTileLabel('Steps'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: HuxTileValue(s == null ? '—' : StepTargetCalculator.formatSteps(s.today))),
                const Hux3DObject(Hux3D.steps, color: HuxColors.ringSteps, size: 38),
              ],
            ),
            const SizedBox(height: 8),
            HuxHourBars(values: byHour, color: HuxColors.ringSteps),
            const SizedBox(height: 6),
            Text(
                (s == null ? 'no data yet' : (s.done ? 'goal reached' : 'of ${StepTargetCalculator.formatSteps(s.target)}')) +
                    (distanceM == null || distanceM! < 50 ? '' : ' · ${(distanceM! / 1000).toStringAsFixed(1)} km'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: huxMuted)),
          ],
        ),
      ),
    );
  }
}

class _ProteinTile extends StatelessWidget {
  final FoodToday food;
  final VoidCallback onTap;

  const _ProteinTile({required this.food, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final toGo = (food.proteinGoalG - food.proteinG).round();
    return HuxTile(
      onTap: onTap,
      semanticLabel: 'Protein ${food.proteinG.round()} of ${food.proteinGoalG.round()} grams',
      child: ExcludeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HuxTileLabel('Protein'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: HuxTileValue('${food.proteinG.round()}', unit: 'g')),
                const Hux3DObject(Hux3D.egg, color: HuxColors.ringFood, size: 38),
              ],
            ),
            const SizedBox(height: 10),
            HuxSegmentBar(value: food.proteinG, max: food.proteinGoalG, color: HuxColors.ringFood),
            const SizedBox(height: 8),
            Text(toGo > 0 ? '+$toGo g to go' : 'goal reached',
                style: TextStyle(fontSize: 14, color: huxMuted)),
          ],
        ),
      ),
    );
  }
}

/// Water: tap + for each glass. Keeps its own count so a tap is instant.
class _WaterTile extends StatefulWidget {
  final WaterLog log;
  final WaterToday today;

  const _WaterTile({super.key, required this.log, required this.today});

  @override
  State<_WaterTile> createState() => _WaterTileState();
}

class _WaterTileState extends State<_WaterTile> {
  static const _blue = Color(0xFF2F8FE0);
  late int _glasses = widget.today.glasses;

  Future<void> _add(int delta) async {
    final before = _glasses;
    setState(() => _glasses = (_glasses + delta).clamp(0, WaterLog.maxPerDay));
    try {
      final saved = await widget.log.add(delta);
      if (mounted) setState(() => _glasses = saved);
    } catch (_) {
      if (mounted) setState(() => _glasses = before);
    }
  }

  @override
  Widget build(BuildContext context) {
    final goal = widget.today.goal;
    final left = goal.glasses - _glasses;
    final litres = (_glasses * WaterGoal.glassMl / 1000).toStringAsFixed(_glasses % 4 == 0 ? 0 : 2);
    return HuxTile(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
      semanticLabel: 'Water $_glasses of ${goal.glasses} glasses',
      child: Row(
        children: [
          const ExcludeSemantics(child: Hux3DObject(Hux3D.drop, color: _blue, size: 38)),
          const SizedBox(width: 12),
          Expanded(
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HuxTileLabel('Water'),
                  const SizedBox(height: 4),
                  HuxTileValue('$_glasses', unit: 'of ${goal.glasses} glasses'),
                  const SizedBox(height: 8),
                  HuxSegmentBar(value: _glasses.toDouble(), max: goal.glasses.toDouble(), segments: goal.glasses, color: _blue),
                  const SizedBox(height: 6),
                  Text(
                    left <= 0
                        ? 'Goal reached · $litres L'
                        : goal.why ?? (_glasses == 0 ? 'Tap + for each glass (250 ml)' : '$left to go · $litres L so far'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, color: huxMuted),
                  ),
                ],
              ),
            ),
          ),
          if (_glasses > 0)
            IconButton(
              tooltip: 'Remove a glass',
              onPressed: () => _add(-1),
              icon: Icon(Icons.remove_circle_outline_rounded, color: huxMuted),
            ),
          IconButton.filled(
            tooltip: 'Add a glass',
            onPressed: () => _add(1),
            style: IconButton.styleFrom(backgroundColor: _blue, minimumSize: const Size(48, 48)),
            icon: const Icon(Icons.add_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _LogMealTile extends StatelessWidget {
  final VoidCallback onTap;

  const _LogMealTile({required this.onTap});

  @override
  Widget build(BuildContext context) => HuxTile(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HuxTileLabel('Food'),
            const SizedBox(height: 6),
            const Hux3DObject(Hux3D.bowl, color: HuxColors.ringFood, size: 52),
            const SizedBox(height: 6),
            Text('Log a meal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: huxInk)),
          ],
        ),
      );
}

class _BedtimesTile extends StatelessWidget {
  final HomeInsights insights;
  final DateTime? targetBed;
  final VoidCallback onTap;

  const _BedtimesTile({required this.insights, required this.targetBed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final known = insights.nights7.whereType<NightWindow>().length;
    final lateCount = targetBed == null ? null : insights.lateNights(targetBed!);
    return HuxTile(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HuxTileLabel(
            'Bedtimes this week',
            trailing: lateCount == null || lateCount == 0
                ? null
                : Text('$lateCount of $known late',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFFA35F00))),
          ),
          const SizedBox(height: 12),
          HuxBedtimeWeek(
            nights: [for (final n in insights.nights7) n == null ? null : (bed: n.bed, wake: n.wake)],
            targetBed: targetBed,
          ),
        ],
      ),
    );
  }
}

/// Only when a ring is connected: battery and a test buzz.
class _RingCard extends StatelessWidget {
  final int batteryPercent;
  final Future<void> Function() sendTestBuzz;

  const _RingCard({required this.batteryPercent, required this.sendTestBuzz});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return GlassPanel(
      child: Row(
        children: [
          HuxScoreRing(
            progress: batteryPercent / 100,
            centerText: '$batteryPercent%',
            color: HuxColors.accentIndigo,
            size: 52,
            stroke: 6,
          ),
          const SizedBox(width: HuxSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your ring', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('Battery', style: text.bodySmall),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => NudgeModal.show(
              context,
              title: 'Test your ring',
              message: "Send one vibration to confirm it's connected.",
              icon: Icons.vibration,
              primaryLabel: 'Buzz now',
              onPrimary: sendTestBuzz,
            ),
            icon: const Icon(Icons.vibration, size: 18),
            label: const Text('Test ring'),
          ),
        ],
      ),
    );
  }
}

class _DataQualityCaption extends StatelessWidget {
  final DataQuality quality;

  const _DataQualityCaption({required this.quality});

  String get _label => switch (quality) {
        DataQuality.full => 'based on full data from last night',
        DataQuality.partial => 'based on partial data from last night',
        DataQuality.sparse => 'based on sparse data from last night',
      };

  @override
  Widget build(BuildContext context) {
    // bodySmall is already muted-colored (see hux_theme.dart) — no
    // per-widget color override needed.
    return Text(_label, style: Theme.of(context).textTheme.bodySmall);
  }
}

/// The active event mode's compact strip: phase, days-to-go, and
/// today's themed action. On day 0 this is the readiness card instead
/// (same widget — [ModeStrip.phase] already reflects that).
class _ModeStripCard extends StatelessWidget {
  final ModeStrip strip;

  const _ModeStripCard({required this.strip});

  @override
  Widget build(BuildContext context) {
    final isDayZero = strip.phase == ModePhase.theDay;
    final labelStyle = Theme.of(context)
        .textTheme
        .labelLarge
        ?.copyWith(color: HuxModeAccent.background);

    // Day zero is the payoff moment — it gets the full mint glow; the
    // countdown phases stay a quieter mint-tinted glass.
    return GlassPanel(
      frosted: true,
      padding: const EdgeInsets.all(HuxSpacing.md),
      tint:
          HuxModeAccent.background.withValues(alpha: HuxOpacity.activeCardWash),
      glow: isDayZero ? HuxModeAccent.background : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(strip.phaseLabel, style: labelStyle),
              if (!strip.isWrapUp)
                Text(
                  strip.daysToGo == 0 ? 'Today' : '${strip.daysToGo}d to go',
                  style: labelStyle,
                ),
            ],
          ),
          const SizedBox(height: HuxSpacing.xs),
          Text(strip.themedAction,
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

/// "Coach noticed": one pattern from the user's own history, phrased as a
/// question, with ONE next step. Nothing is sent until they tap send in
/// the chat.
class _CoachNoticedCard extends StatelessWidget {
  final CoachNudge nudge;
  final VoidCallback onAsk;
  final VoidCallback onLogMeal;
  final VoidCallback? onHide;

  const _CoachNoticedCard({required this.nudge, required this.onAsk, required this.onLogMeal, this.onHide});

  @override
  Widget build(BuildContext context) {
    final look = coachTopicLook(nudge.topic);
    final logMeal = nudge.action == CoachNudgeAction.logMeal && nudge.meal != null;
    final coachName = nudge.topic == CoachTopic.general ? 'coach' : '${nudge.topic.label.toLowerCase()} coach';
    return Material(
      color: Color.alphaBlend(look.color.withValues(alpha: 0.10), HuxColors.card),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: look.color.withValues(alpha: 0.25)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 6, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hux3DObject(look.object, color: look.color, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nudge.positive ? 'Nice pattern' : 'Coach noticed',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800, color: Color.lerp(look.color, huxInk, 0.35))),
                      const SizedBox(height: 2),
                      Text(nudge.headline,
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.2, color: huxInk)),
                      const SizedBox(height: 4),
                      Text(nudge.detail, style: TextStyle(fontSize: 14, height: 1.35, color: huxMuted)),
                    ],
                  ),
                ),
                if (onHide != null)
                  IconButton(
                    tooltip: 'Not now',
                    visualDensity: VisualDensity.compact,
                    onPressed: onHide,
                    icon: Icon(Icons.close_rounded, size: 20, color: huxMuted),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(left: 56, right: 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (logMeal)
                    FilledButton.icon(
                      onPressed: onLogMeal,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Log ${nudge.meal!.label.toLowerCase()}'),
                    ),
                  if (logMeal)
                    OutlinedButton.icon(
                      onPressed: onAsk,
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      label: Text('Ask the $coachName'),
                    )
                  else
                    FilledButton.icon(
                      onPressed: onAsk,
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      label: Text('Ask the $coachName'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Morning check-in: when you slept + how rested you feel. With a synced
/// night it only asks how rested you feel.
class _SleepCheckInCard extends StatefulWidget {
  final SleepSession? deviceNight;
  final SleepCheckIn? previous;
  final Future<void> Function(SleepCheckIn) onSave;
  final VoidCallback onSkip;

  const _SleepCheckInCard({this.deviceNight, this.previous, required this.onSave, required this.onSkip});

  @override
  State<_SleepCheckInCard> createState() => _SleepCheckInCardState();
}

class _SleepCheckInCardState extends State<_SleepCheckInCard> {
  late TimeOfDay _bed = widget.previous == null
      ? const TimeOfDay(hour: 23, minute: 0)
      : TimeOfDay.fromDateTime(widget.previous!.bed.toLocal());
  late TimeOfDay _wake = widget.previous == null
      ? const TimeOfDay(hour: 7, minute: 0)
      : TimeOfDay.fromDateTime(widget.previous!.wake.toLocal());
  Rested? _feel;
  bool _saving = false;

  static String _t(TimeOfDay t) => huxClock(DateTime(2000, 1, 1, t.hour, t.minute));

  /// Wake today (never in the future); bed the evening before if needed.
  (DateTime, DateTime) _times() {
    final now = DateTime.now();
    var wake = DateTime(now.year, now.month, now.day, _wake.hour, _wake.minute);
    if (wake.isAfter(now)) wake = now;
    var bed = DateTime(wake.year, wake.month, wake.day, _bed.hour, _bed.minute);
    if (!bed.isBefore(wake)) bed = bed.subtract(const Duration(days: 1));
    return (bed, wake);
  }

  Future<void> _pick(bool bed) async {
    final picked = await showTimePicker(context: context, initialTime: bed ? _bed : _wake);
    if (picked == null || !mounted) return;
    setState(() {
      if (bed) {
        _bed = picked;
      } else {
        _wake = picked;
      }
    });
  }

  Future<void> _save() async {
    final feel = _feel;
    if (feel == null || _saving) return;
    setState(() => _saving = true);
    final n = widget.deviceNight;
    final (bed, wake) = n == null ? _times() : (n.bedtime, n.wakeTime);
    await widget.onSave(SleepCheckIn(bed: bed, wake: wake, feel: feel, fromDevice: n != null));
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final device = widget.deviceNight != null;
    final (bed, wake) = _times();
    final len = wake.difference(bed);
    final lenText = '${len.inHours}h ${(len.inMinutes % 60).toString().padLeft(2, '0')}m';
    return HuxTile(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Hux3DObject(Hux3D.pillow, color: HuxColors.ringSleep, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device ? 'How rested do you feel?' : 'How did you sleep?',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: huxInk)),
                    Text(device ? 'Your watch saw the night — only you know how it felt.' : 'Two taps. Charge uses it.',
                        style: TextStyle(fontSize: 13, color: huxMuted)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Not now',
                visualDensity: VisualDensity.compact,
                onPressed: widget.onSkip,
                icon: Icon(Icons.close_rounded, size: 20, color: huxMuted),
              ),
            ],
          ),
          if (!device) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _pick(true),
                  icon: const Icon(Icons.bedtime_outlined, size: 18),
                  label: Text('Slept ${_t(_bed)}'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pick(false),
                  icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                  label: Text('Up ${_t(_wake)}'),
                ),
                Text('= $lenText', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: huxMuted)),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final r in Rested.values)
                ChoiceChip(
                  label: Text(r.label),
                  selected: _feel == r,
                  showCheckmark: false,
                  selectedColor: huxSolid,
                  labelStyle: TextStyle(fontWeight: FontWeight.w700, color: _feel == r ? Colors.white : huxInk),
                  onSelected: (_) => setState(() => _feel = r),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  device ? 'Stays on your phone.' : 'Stays on your phone. Charge starts after 3 nights.',
                  style: TextStyle(fontSize: 12, color: huxMuted),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _feel == null || _saving ? null : _save,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Home, after "Continue without health data": one quiet way back.
class _ConnectHealthTile extends StatelessWidget {
  final VoidCallback onConnect;

  const _ConnectHealthTile({required this.onConnect});

  @override
  Widget build(BuildContext context) {
    final app = Platform.isIOS ? 'Apple Health' : 'Health Connect';
    return HuxTile(
      onTap: onConnect,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          const Hux3DObject(Hux3D.phone, color: HuxColors.ringSteps, size: 36, animate: false),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Connect $app',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: huxInk)),
                Text('Adds steps (your phone counts them) and sleep from any watch.',
                    style: TextStyle(fontSize: 13, color: huxMuted)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: huxMuted),
        ],
      ),
    );
  }
}
