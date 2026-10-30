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

import '../core/home/home_extras.dart';
import '../core/home/home_insights.dart';
import '../core/meaning/daily_readout.dart';
import '../core/meaning/day_plan.dart';
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
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';
import 'for_you.dart';
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

  /// Seeded from `syncService.lastRingInfo` right after each sync/load
  /// (an immediate, correct reading), then kept fresh by the live
  /// [SyncService.batteryPercent] subscription below.
  int? _batteryPercent;
  StreamSubscription<int>? _batterySub;

  /// Live instantaneous heart rate for the Home heart-rate stat — a genuine
  /// point reading, not last night's stored average (that comes from
  /// [_lastNight] instead). Null between readings is normal.
  double? _heartRateBpm;
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
      if (mounted && bpm != null) setState(() => _heartRateBpm = bpm.toDouble());
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

  Future<void> _connectHealth() async {
    try {
      await widget.store.writeSetting(_primedKey, 'yes');
    } catch (_) {}
    await _bootstrap();
  }

  /// Quiet sync: pulls new health data without blanking the screen; on
  /// success the readout reloads in place. Failures stay silent here —
  /// pull-to-refresh is where the user asks and hears back.
  Future<void> _backgroundSync() async {
    if (!widget.autoSync || _bgSyncing || _phase != _Phase.ready) return;
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
      if (!mounted) return;

      if (!everSynced) {
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
    if (!mounted) return;
    setState(() {
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
    final outcome = await widget.syncService.syncNow();
    if (!mounted) return;
    if (!outcome.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Couldn't sync your health data — try again."),
          action: SnackBarAction(label: 'Retry', onPressed: _refresh),
        ),
      );
      return;
    }
    await _loadReadout();
  }

  @override
  Widget build(BuildContext context) => _buildBody();

  Widget _buildBody() {
    switch (_phase) {
      case _Phase.priming:
        return _HealthPrimingView(onConnect: _connectHealth);
      case _Phase.syncing:
        return const _MessageView(message: 'Syncing your health data…');
      case _Phase.loadingReadout:
        return const _MessageView(message: 'Loading your readout…');
      case _Phase.error:
        return _ErrorView(
          message: _errorMessage,
          onRetry: _bootstrap,
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

  const _ErrorView({required this.message, required this.onRetry});

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
            const Icon(Icons.sync_problem_rounded,
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

  const _HealthPrimingView({required this.onConnect});

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

  const _ReadoutBody({
    required this.readout,
    required this.lastNight,
    required this.modeStrip,
    required this.activeContext,
    required this.batteryPercent,
    required this.heartRateBpm,
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
        ))),
        if (next != null) ...[gap, pad(HuxEntrance(index: 1, child: next))],
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
              Expanded(child: _StepsTile(steps: plan?.steps, byHour: insights.stepsByHour)),
              const SizedBox(width: 12),
              Expanded(
                child: food == null
                    ? _LogMealTile(onTap: () => _open(FeatureId.proteinGap))
                    : _ProteinTile(food: food, onTap: () => _open(FeatureId.proteinGap)),
              ),
            ],
          ),
        )),
        if (lastRhr != null || programs.isNotEmpty) ...[
          gap,
          pad(HuxEntrance(
            index: 3,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (lastRhr != null)
                  Expanded(
                    child: HuxTile(
                      onTap: () => _why(context),
                      semanticLabel: 'Resting heart $lastRhr bpm',
                      child: ExcludeSemantics(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const HuxTileLabel('Resting heart'),
                            const SizedBox(height: 8),
                            HuxTileValue('$lastRhr', unit: 'bpm'),
                            const SizedBox(height: 8),
                            HuxSparkline(values: rhr, color: HuxColors.ringHeart),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (lastRhr != null && programs.isNotEmpty) const SizedBox(width: 12),
                if (programs.isNotEmpty)
                  Expanded(
                    child: Column(
                      children: [
                        for (var i = 0; i < programs.length; i++) ...[
                          if (i > 0) const SizedBox(height: 12),
                          programs[i],
                        ],
                      ],
                    ),
                  ),
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
      if (m < 6 * 60) m = 24 * 60 - 1; // after midnight: pin to the end
      out.add(HuxDayEvent(minuteOfDay: m, label: 'Bed', color: HuxColors.ringSleep, time: huxClock(bed)));
    }
    // At most 5, so labels stay readable.
    out.sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));
    return out.length <= 5 ? out : [out.first, ...out.sublist(out.length - 4)];
  }
}

/// The one dark surface: greeting, the Charge ring, one line.
class _Hero extends StatelessWidget {
  final DailyReadout readout;
  final String? name;
  final String? chipText;
  final VoidCallback? onOpenProfile;
  final VoidCallback onWhy;

  const _Hero({required this.readout, required this.name, required this.chipText, required this.onOpenProfile, required this.onWhy});

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
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
      decoration: BoxDecoration(color: huxNight, borderRadius: BorderRadius.circular(28)),
      child: Column(
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
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
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
                child: GestureDetector(onTap: onWhy, child: HuxChargeOrb(value: charge?.value, size: 140)),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stateLabel,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color.lerp(state.huxColor, Colors.white, 0.45),
                        )),
                    const SizedBox(height: 6),
                    Text(readout.headline,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white, height: 1.2)),
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
        ],
      ),
    );
  }
}

class _LastNightTile extends StatelessWidget {
  final SleepSession night;
  final Duration goal;
  final DateTime? targetBed;
  final VoidCallback onTap;

  const _LastNightTile({required this.night, required this.goal, required this.targetBed, required this.onTap});

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
    return HuxTile(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HuxTileLabel('Last night', trailing: Text('goal ${goal.inHours}h${goal.inMinutes % 60 == 0 ? '' : ' ${goal.inMinutes % 60}m'}',
              style: const TextStyle(fontSize: 14, color: huxMuted))),
          const SizedBox(height: 8),
          HuxTileValue(_hm(night.totalSleep), size: 32),
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

  const _StepsTile({required this.steps, required this.byHour});

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
            HuxTileValue(s == null ? '—' : StepTargetCalculator.formatSteps(s.today)),
            const SizedBox(height: 8),
            HuxHourBars(values: byHour, color: HuxColors.ringSteps),
            const SizedBox(height: 6),
            Text(s == null ? 'no data yet' : (s.done ? 'goal reached' : 'of ${StepTargetCalculator.formatSteps(s.target)}'),
                style: const TextStyle(fontSize: 14, color: huxMuted)),
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
            HuxTileValue('${food.proteinG.round()}', unit: 'g'),
            const SizedBox(height: 10),
            HuxSegmentBar(value: food.proteinG, max: food.proteinGoalG, color: HuxColors.ringFood),
            const SizedBox(height: 8),
            Text(toGo > 0 ? '+$toGo g to go' : 'goal reached',
                style: const TextStyle(fontSize: 14, color: huxMuted)),
          ],
        ),
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
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HuxTileLabel('Food'),
            SizedBox(height: 14),
            Icon(Icons.add_a_photo_outlined, color: HuxColors.ringFood, size: 30),
            SizedBox(height: 10),
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
