/// HUX Ring Data Source
/// ---------------------
/// Which [RingAdapter] implementation the composition root wired up —
/// purely a labeling concern for the banner pinned above every tab
/// (see app_shell.dart). Every screen still only ever talks to
/// [RingAdapter] itself; nothing above the adapter branches on this.
///
/// Pure Dart, no Flutter — `bannerText` is plain text; the Color that
/// pairs with each source lives in app_shell.dart, the one UI file
/// allowed to import `package:flutter/material.dart` for it.
enum RingDataSource { mock, health, aizoBle }

extension RingDataSourceBanner on RingDataSource {
  /// The exact words shown in the banner. Must always truthfully say
  /// where the data came from — this is the one thing standing between
  /// a screenshot and someone mistaking dev/demo data for a real ring.
  ///
  /// [aizoBle] earns its own distinct banner rather than none at all:
  /// connection/battery/vibration are genuinely real, but the protocol is
  /// an unofficial, reverse-engineered decode of the vendor's Android app
  /// (see aizo_ble/aizo_protocol.dart) and almost every health metric is
  /// still permanently absent. Suppressing the banner here would recreate
  /// exactly the screenshot-misattribution risk it exists to prevent.
  String get bannerText => switch (this) {
        RingDataSource.mock => 'DEMO — simulated ring data',
        RingDataSource.health => 'DEV — your health app data (not a HUX ring)',
        RingDataSource.aizoBle =>
          'UNOFFICIAL — connected via reverse-engineered protocol (battery + vibration only)',
      };
}
