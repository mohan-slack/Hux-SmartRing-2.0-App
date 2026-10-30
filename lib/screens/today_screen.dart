/// Today screen — deliberately undesigned plumbing UI. A later design
/// phase restyles this; keep widgets small and composable so that pass
/// is cheap.
///
/// Talks only to [HealthStore] (to check "have we ever synced"),
/// [SyncService], [ReadoutService], and [ModeService] — never to a
/// RingAdapter or SQL.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/cycle/cycle_service.dart';
import '../core/home/home_extras.dart';
import '../core/journeys/journey_service.dart';
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
import '../theme/hux_page.dart';
import '../theme/hux_tokens.dart';
import '../theme/hux_ui.dart';
import 'for_you.dart';
import '../widgets/wellness_note.dart';

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

/// Home (OxeAI-style): greeting + avatar, "Ask HUX" bar, three score
/// rings, today's insight, today's plan as an agenda, featured cards,
/// last night, body today, ring (when one is paired).
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

  @override
  Widget build(BuildContext context) {
    final chipText = _lifestyleChipText(activeContext);
    final plan = readout.plan;
    return ListView(
      // Bottom clearance: content scrolls behind the floating nav bar.
      padding: const EdgeInsets.fromLTRB(
          HuxSpacing.lg, HuxSpacing.sm, HuxSpacing.lg, HuxGlass.navClearance),
      children: [
        _HomeHeader(name: greetingName, onOpenProfile: onOpenProfile),
        if (chipText != null) ...[
          const SizedBox(height: HuxSpacing.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: const Icon(Icons.nightlight_round, size: 16, color: HuxColors.accentPurple),
              label: Text(chipText),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
        if (onAsk != null) ...[
          const SizedBox(height: HuxSpacing.md),
          HuxAskBar(onTap: onAsk!),
        ],
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(child: _ScoresCard(readout: readout, lastNight: lastNight)),
        if (extras.journey != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(index: 1, child: _JourneyCard(summary: extras.journey!, onOpen: onOpenJourney)),
        ],
        if (extras.cycle != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(index: 1, child: _CycleCard(summary: extras.cycle!, onOpen: onOpenCycle)),
        ],
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(index: 1, child: _InsightCard(readout: readout)),
        if ((plan != null && !plan.isEmpty) || extras.agenda.isNotEmpty) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(
            index: 2,
            child: _AgendaCard(plan: plan, entries: extras.agenda, onOpenFeature: onOpenFeature),
          ),
        ],
        if (extras.food != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(
            index: 2,
            child: _FoodCard(
              food: extras.food!,
              activeKcal: readout.activeEnergyKcal,
              onOpen: onOpenFeature == null ? null : () => onOpenFeature!(FeatureId.proteinGap),
            ),
          ),
        ],
        if (modeStrip != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(index: 2, child: _ModeStripCard(strip: modeStrip!)),
        ],
        if (featured.isNotEmpty && onOpenFeature != null && onSeeAllFeatures != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(
            index: 3,
            child: ForYouSection(
              featured: featured,
              onOpen: onOpenFeature!,
              onSeeAll: onSeeAllFeatures!,
            ),
          ),
        ],
        if (extras.sleep7.any((v) => v != null) || extras.steps7.any((v) => v != null)) ...[
          const SizedBox(height: HuxSpacing.lg),
          HuxEntrance(
            index: 3,
            child: _WeekCard(
              sleep7: extras.sleep7,
              steps7: extras.steps7,
              onOpen: onOpenFeature == null ? null : () => onOpenFeature!(FeatureId.sleepRegularity),
            ),
          ),
        ],
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(index: 3, child: _SleepCard(night: lastNight)),
        const SizedBox(height: HuxSpacing.lg),
        HuxEntrance(
          index: 4,
          child: _BodyCard(readout: readout, night: lastNight, heartRateBpm: heartRateBpm),
        ),
        if (batteryPercent != null) ...[
          const SizedBox(height: HuxSpacing.lg),
          _RingCard(batteryPercent: batteryPercent!, sendTestBuzz: sendTestBuzz),
        ],
        const SizedBox(height: HuxSpacing.md),
        Center(child: _DataQualityCaption(quality: readout.dataQuality)),
        const WellnessNote(),
      ],
    );
  }
}

class _HomeHeader extends StatelessWidget {
  final String? name;
  final VoidCallback? onOpenProfile;

  const _HomeHeader({required this.name, required this.onOpenProfile});

  static String _greeting(int hour) => hour < 5
      ? 'Good night'
      : hour < 12
          ? 'Good morning'
          : hour < 17
              ? 'Good afternoon'
              : 'Good evening';

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final now = DateTime.now();
    final n = (name ?? '').trim();
    return Row(
      children: [
        if (onOpenProfile != null) ...[
          HuxAvatar(initial: n.isEmpty ? 'H' : n[0].toUpperCase(), onTap: onOpenProfile),
          const SizedBox(width: HuxSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_days[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}', style: text.labelMedium),
              Text(
                n.isEmpty ? _greeting(now.hour) : '${_greeting(now.hour)}, $n',
                style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Three rings: HUX Charge, Sleep, Steps.
class _ScoresCard extends StatelessWidget {
  final DailyReadout readout;
  final SleepSession? lastNight;

  const _ScoresCard({required this.readout, required this.lastNight});

  static String _hours(int minutes) => '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}';

  static String _compactSteps(int n) => n >= 1000 ? '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k' : '$n';

  @override
  Widget build(BuildContext context) {
    final charge = readout.charge;
    final steps = readout.plan?.steps;
    final goal = readout.plan?.bedtime?.sleepGoal ?? const Duration(hours: 8);
    final asleep = lastNight?.totalSleep.inMinutes;
    return GlassPanel(
      padding: const EdgeInsets.symmetric(vertical: HuxSpacing.md, horizontal: HuxSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: HuxRingTile(
              label: 'Charge',
              value: charge?.value == null ? '—' : '${charge!.value}',
              caption: charge?.label,
              progress: charge?.value == null ? null : charge!.value! / 100,
              color: HuxColors.ringCharge,
            ),
          ),
          Expanded(
            child: HuxRingTile(
              label: 'Sleep',
              value: asleep == null ? '—' : _hours(asleep),
              caption: 'goal ${DayPlanner.duration(goal)}',
              progress: asleep == null ? null : asleep / goal.inMinutes,
              color: HuxColors.ringSleep,
            ),
          ),
          Expanded(
            child: HuxRingTile(
              label: 'Steps',
              value: steps == null ? '—' : _compactSteps(steps.today),
              caption: steps == null ? null : 'of ${StepTargetCalculator.formatSteps(steps.target)}',
              progress: steps?.progress,
              color: HuxColors.ringSteps,
            ),
          ),
        ],
      ),
    );
  }
}

/// Today's headline, what it means, and the suggested actions.
class _InsightCard extends StatelessWidget {
  final DailyReadout readout;

  const _InsightCard({required this.readout});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = readout.state.huxColor;
    final reason = readout.charge?.reason;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HuxPulseDot(color: color),
              const SizedBox(width: HuxSpacing.sm),
              Text("TODAY'S READ", style: text.labelMedium?.copyWith(letterSpacing: 0.8, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: HuxSpacing.sm),
          Text(readout.headline, style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: HuxSpacing.sm),
          Text(readout.meaning, style: text.bodyMedium?.copyWith(height: 1.4)),
          if (reason != null) ...[
            const SizedBox(height: HuxSpacing.sm),
            Text(reason, style: text.bodySmall),
          ],
          if (readout.actions.isNotEmpty) ...[
            const SizedBox(height: HuxSpacing.md),
            for (final action in readout.actions)
              Padding(
                padding: const EdgeInsets.only(bottom: HuxSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline_rounded, size: 18, color: color),
                    const SizedBox(width: HuxSpacing.sm),
                    Expanded(child: Text(action, style: text.bodyMedium)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Today's agenda: effort and steps for the day, then timed items
/// (best walk time, walks after meals, plan session, journal, bedtime).
class _AgendaCard extends StatelessWidget {
  final DayPlan? plan;
  final List<AgendaEntry> entries;
  final FeatureTap? onOpenFeature;

  const _AgendaCard({required this.plan, required this.entries, required this.onOpenFeature});

  static (IconData, Color) _style(AgendaKind k) => switch (k) {
        AgendaKind.air => (Icons.air_rounded, HuxColors.steady),
        AgendaKind.walk => (Icons.directions_walk_rounded, HuxColors.ringFood),
        AgendaKind.plan => (Icons.directions_run_rounded, HuxColors.ringSteps),
        AgendaKind.journal => (Icons.edit_note_rounded, HuxColors.ringHabit),
      };

  @override
  Widget build(BuildContext context) {
    final effort = plan?.effort;
    final steps = plan?.steps;
    final bedtime = plan?.bedtime;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;

    final timed = <({int minute, Widget row})>[
      for (final e in entries)
        (
          minute: e.minuteOfDay,
          row: HuxAgendaItem(
            time: e.time,
            icon: _style(e.kind).$1,
            color: _style(e.kind).$2,
            title: e.title,
            detail: e.detail,
            done: e.done,
            past: e.minuteOfDay + 60 < nowMin,
            onTap: e.feature == null || onOpenFeature == null ? null : () => onOpenFeature!(e.feature!),
          ),
        ),
      if (bedtime != null)
        (
          minute: () {
            final b = bedtime.bedtime.toLocal();
            final m = b.hour * 60 + b.minute;
            return m < 12 * 60 ? m + 24 * 60 : m; // after midnight sorts last
          }(),
          row: HuxAgendaItem(
            time: DayPlanner.clock(bedtime.bedtime),
            icon: Icons.bedtime_rounded,
            color: HuxColors.ringSleep,
            title: 'Sleep by ${DayPlanner.clock(bedtime.bedtime)}',
            detail: 'Aim for ${DayPlanner.duration(bedtime.sleepGoal)}. ${bedtime.reason}',
          ),
        ),
    ]..sort((a, b) => a.minute.compareTo(b.minute));

    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(HuxSpacing.lg, HuxSpacing.lg, HuxSpacing.lg, HuxSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HuxSectionTitle("Today's agenda", icon: Icons.event_note_rounded, iconColor: HuxColors.accentPurple),
          if (effort != null)
            HuxAgendaItem(
              time: 'Today',
              icon: Icons.bolt_rounded,
              color: HuxColors.ringCharge,
              title: 'Effort: ${effort.label} (${effort.range} of 10)',
              detail: effort.suggestion,
            ),
          if (steps != null)
            HuxAgendaItem(
              time: 'Today',
              icon: Icons.directions_walk_rounded,
              color: HuxColors.ringSteps,
              done: steps.done,
              title: steps.done
                  ? 'Step goal reached: ${StepTargetCalculator.formatSteps(steps.today)}'
                  : 'Walk ${steps.minutesToGo} more min',
              detail: steps.done
                  ? steps.reason
                  : '${StepTargetCalculator.formatSteps(steps.today)} of '
                      '${StepTargetCalculator.formatSteps(steps.target)} steps. ${steps.reason}',
            ),
          if ((effort != null || steps != null) && timed.isNotEmpty)
            const Divider(height: HuxSpacing.lg, color: HuxColors.hairline),
          for (final t in timed) t.row,
        ],
      ),
    );
  }
}

/// Calories and macros eaten today, plus the eaten-vs-burned balance.
class _FoodCard extends StatelessWidget {
  final FoodToday food;
  final int? activeKcal;
  final VoidCallback? onOpen;

  const _FoodCard({required this.food, required this.activeKcal, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final proteinPct = food.proteinGoalG <= 0 ? 0.0 : (food.proteinG / food.proteinGoalG).clamp(0.0, 1.0);
    final burned = activeKcal;
    final balance = burned == null ? null : food.kcal.round() - burned;

    Widget macro(String label, double grams, Color color, {double? goal}) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.labelMedium),
              const SizedBox(height: 2),
              Text(goal == null ? '${grams.round()} g' : '${grams.round()} / ${goal.round()} g',
                  style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: goal == null ? (grams > 0 ? 1 : 0) : proteinPct,
                  minHeight: 5,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.14),
                ),
              ),
            ],
          ),
        );

    return GestureDetector(
      onTap: onOpen,
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const HuxIconBadge(icon: Icons.restaurant_rounded, color: HuxColors.ringFood),
                const SizedBox(width: HuxSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Calories & macros', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(food.meals == 0 ? 'No meals logged yet' : '${food.meals} meal${food.meals == 1 ? '' : 's'} today',
                          style: text.bodySmall),
                    ],
                  ),
                ),
                Text.rich(TextSpan(children: [
                  TextSpan(text: '${food.kcal.round()}', style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' kcal', style: text.labelSmall),
                ])),
              ],
            ),
            const SizedBox(height: HuxSpacing.md),
            Row(
              children: [
                macro('Protein', food.proteinG, HuxColors.ringFood, goal: food.proteinGoalG),
                const SizedBox(width: HuxSpacing.md),
                macro('Carbs', food.carbsG, HuxColors.ringSteps),
                const SizedBox(width: HuxSpacing.md),
                macro('Fat', food.fatG, HuxColors.ringCharge),
              ],
            ),
            if (balance != null) ...[
              const SizedBox(height: HuxSpacing.md),
              const Divider(height: 1, color: HuxColors.hairline),
              const SizedBox(height: HuxSpacing.sm),
              Row(
                children: [
                  _BalanceSide(label: 'Eaten', value: food.kcal.round(), color: HuxColors.ringFood),
                  Expanded(
                    child: Column(
                      children: [
                        Icon(Icons.balance_rounded, color: HuxColors.mutedText.withValues(alpha: 0.8)),
                        Text(
                          balance >= 0 ? '+$balance kcal' : '$balance kcal',
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  _BalanceSide(label: 'Burned (active)', value: burned!, color: HuxColors.ringSteps, end: true),
                ],
              ),
              const SizedBox(height: 2),
              Text('Burned counts movement only, not your resting energy.', style: text.labelSmall),
            ],
            if (food.meals == 0 && onOpen != null) ...[
              const SizedBox(height: HuxSpacing.sm),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Log a meal'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BalanceSide extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final bool end;

  const _BalanceSide({required this.label, required this.value, required this.color, this.end = false});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(label, style: text.labelMedium),
        Text('$value kcal', style: text.titleSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
      ],
    );
  }
}

/// Last 7 days: sleep and steps as mini bar charts.
class _WeekCard extends StatelessWidget {
  final List<int?> sleep7;
  final List<int?> steps7;
  final VoidCallback? onOpen;

  const _WeekCard({required this.sleep7, required this.steps7, required this.onOpen});

  static int? _avg(List<int?> v) {
    final x = v.whereType<int>().toList();
    return x.isEmpty ? null : (x.reduce((a, b) => a + b) / x.length).round();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final sleepAvg = _avg(sleep7);
    final stepsAvg = _avg(steps7);

    Widget column(String label, String value, List<int?> values, Color color) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: text.labelMedium),
              Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: HuxSpacing.sm),
              HuxMiniBars(values: [for (final v in values) v?.toDouble()], color: color),
            ],
          ),
        );

    return GestureDetector(
      onTap: onOpen,
      child: GlassPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HuxSectionTitle('Your week',
                icon: Icons.insights_rounded,
                iconColor: HuxColors.accentPurple,
                actionLabel: onOpen == null ? null : 'Trends',
                onAction: onOpen),
            Row(
              children: [
                column('Sleep · avg', sleepAvg == null ? '—' : '${sleepAvg ~/ 60}h ${(sleepAvg % 60).toString().padLeft(2, '0')}m',
                    sleep7, HuxColors.ringSleep),
                const SizedBox(width: HuxSpacing.lg),
                column('Steps · avg', stepsAvg == null ? '—' : StepTargetCalculator.formatSteps(stepsAvg), steps7,
                    HuxColors.ringSteps),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Last night: total, efficiency, stages, breathing and oxygen.
class _SleepCard extends StatelessWidget {
  final SleepSession? night;

  const _SleepCard({required this.night});

  static bool _hasStages(SleepSession n) =>
      n.stageTotal(SleepStage.deep) > Duration.zero || n.stageTotal(SleepStage.rem) > Duration.zero;

  static String _hm(Duration d) => '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final n = night;
    final text = Theme.of(context).textTheme;
    final inBed = n?.totalTimeInBed.inMinutes ?? 0;
    final eff = (n == null || inBed <= 0) ? null : (n.totalSleep.inMinutes / inBed * 100).clamp(0, 100).round();
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              HuxScoreRing(
                progress: eff == null ? null : eff / 100,
                centerText: eff == null ? '—' : '$eff',
                color: HuxColors.ringSleep,
                size: 52,
                stroke: 6,
              ),
              const SizedBox(width: HuxSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Last night', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text(
                      n == null ? 'No sleep recorded yet' : '${_hm(n.totalSleep)} asleep · sleep efficiency ${eff ?? '—'}%',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (n != null) ...[
            const SizedBox(height: HuxSpacing.sm),
            // Only what the source really measured: phones and many bands
            // give one plain "asleep" block (no stages), and most have no
            // breathing rate or SpO2 — never show "Deep 0:00" or "—" rows.
            HuxStatGrid(stats: [
              if (_hasStages(n)) ...[
                HuxStat('Deep sleep', _hm(n.stageTotal(SleepStage.deep))),
                HuxStat('REM sleep', _hm(n.stageTotal(SleepStage.rem))),
                HuxStat('Light sleep', _hm(n.stageTotal(SleepStage.light))),
              ] else
                HuxStat('Asleep', _hm(n.totalSleep)),
              HuxStat('Awake time', _hm(n.stageTotal(SleepStage.awake))),
              if (n.avgRespiratoryRateBrpm != null)
                HuxStat('Resp. rate', n.avgRespiratoryRateBrpm!.round().toString(), unit: 'brpm'),
              if (n.minSpo2Percent != null) HuxStat('Min SpO2', '${n.minSpo2Percent}', unit: '%'),
            ]),
            if (!_hasStages(n))
              Padding(
                padding: const EdgeInsets.only(top: HuxSpacing.xs),
                child: Text('Your source doesn\'t report sleep stages (deep/REM).',
                    style: text.labelSmall?.copyWith(color: HuxColors.mutedText)),
              ),
          ],
        ],
      ),
    );
  }
}

/// Heart rate now / resting, stress and active energy.
class _BodyCard extends StatelessWidget {
  final DailyReadout readout;
  final SleepSession? night;
  final double? heartRateBpm;

  const _BodyCard({required this.readout, required this.night, required this.heartRateBpm});

  static const _stressElevatedThreshold = 50;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final stress = readout.stressIndex;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const HuxIconBadge(icon: Icons.favorite_rounded, color: HuxColors.ringHeart),
              const SizedBox(width: HuxSpacing.md),
              Text('Body today', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: HuxSpacing.sm),
          HuxStatGrid(stats: [
            HuxStat('Heart rate', heartRateBpm == null ? '—' : heartRateBpm!.round().toString(), unit: 'bpm'),
            HuxStat('Night avg HR', night?.avgHeartRateBpm == null ? '—' : '${night!.avgHeartRateBpm}', unit: 'bpm'),
            if (night?.avgHrvMs != null) HuxStat('Night HRV', '${night!.avgHrvMs}', unit: 'ms'),
            // An estimate from HRV — shown only when there's a reading.
            if (stress != null)
              HuxStat('Stress', '$stress',
                  unit: stress > _stressElevatedThreshold ? '/100 · est. high' : '/100 · est. calm'),
            HuxStat('Active cal', readout.activeEnergyKcal == null ? '—' : '${readout.activeEnergyKcal}', unit: 'kcal'),
          ]),
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

/// ONE quiet line for the running journey: "Day 5 of 21 · in bed by 10:45".
class _JourneyCard extends StatelessWidget {
  final JourneyHomeSummary summary;
  final VoidCallback? onOpen;

  const _JourneyCard({required this.summary, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const color = HuxColors.accentPurple;
    return Semantics(
      button: onOpen != null,
      label: '${summary.title}, day ${summary.day} of ${summary.totalDays}. ${summary.line}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(HuxRadii.card),
          child: GlassPanel(
            tint: color.withValues(alpha: 0.06),
            child: Row(
              children: [
                HuxScoreRing(
                  progress: summary.doneToday ? 1 : summary.ticksDone / 3,
                  centerText: summary.doneToday ? '✓' : '${summary.ticksDone}/3',
                  color: summary.doneToday ? HuxColors.recharged : color,
                  size: 52,
                  stroke: 6,
                ),
                const SizedBox(width: HuxSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${summary.title} · Day ${summary.day} of ${summary.totalDays}',
                          style: text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(summary.line, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (onOpen != null) const Icon(Icons.chevron_right, color: HuxColors.mutedText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Cycle's ONE quiet line: "Day 18 · Luteal — next period likely 12–15 Nov".
/// Locked: no details at all.
class _CycleCard extends StatelessWidget {
  final CycleHomeSummary summary;
  final VoidCallback? onOpen;

  const _CycleCard({required this.summary, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const color = HuxColors.accentPink;
    final day = summary.day;
    return Semantics(
      button: onOpen != null,
      label: '${summary.title}. ${summary.line}',
      excludeSemantics: true,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(HuxRadii.card),
          child: GlassPanel(
            tint: color.withValues(alpha: 0.05),
            child: Row(
              children: [
                if (summary.locked || day == null)
                  const HuxIconBadge(icon: Icons.water_drop_rounded, color: color, size: 52)
                else
                  HuxScoreRing(
                    progress: (day / summary.cycleDays).clamp(0.0, 1.0),
                    centerText: '$day',
                    color: color,
                    size: 52,
                    stroke: 6,
                  ),
                const SizedBox(width: HuxSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(summary.title,
                          style: text.labelLarge?.copyWith(color: color, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(summary.line, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                if (summary.showLogButton)
                  const HuxPill(label: 'Log', color: color, icon: Icons.add_rounded)
                else if (onOpen != null)
                  const Icon(Icons.chevron_right, color: HuxColors.mutedText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
