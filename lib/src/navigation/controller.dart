import 'package:flutter/animation.dart';
import 'package:flutter/foundation.dart';

import 'navigation.dart';

/// The view-side implementation operated by [MarkdownXController].
abstract interface class MarkdownXNavigationHost {
  /// The headings of the current document.
  List<MarkdownXHeading> get headings;

  /// Whether the target [id] exists.
  bool hasAnchor(String id);

  /// Scrolls to the position of [id]. Returns true if it could move there.
  /// This is the implementation of [MarkdownXController.jumpToAnchor]; the arguments mean the same.
  Future<bool> jumpToAnchor(
    String id, {
    required Duration duration,
    required Curve curve,
    required double alignment,
  });
}

/// A controller for getting a document's table of contents and navigating to any heading or footnote.
///
/// Pass it as `markdownController` of `Markdown` and `MarkdownBody`. One controller
/// can be attached to only one Widget at a time. It notifies its listeners when the
/// headings change (notification happens after build, so calling `setState` inside
/// a listener is fine).
class MarkdownXController extends ChangeNotifier {
  MarkdownXNavigationHost? _host;
  bool _disposed = false;

  /// The headings of the current document. Empty when no Widget is attached.
  List<MarkdownXHeading> get headings => _host?.headings ?? const [];

  /// Whether the controller is attached to a Widget.
  bool get isAttached => _host != null;

  /// Whether the target [id] exists (a heading ID or footnote ID, without the `#`).
  bool hasAnchor(String id) => _host?.hasAnchor(id) ?? false;

  /// Scrolls to the position of [id]. Returns true if it could move there, and false if the
  /// id does not exist, no Widget is attached, or scrolling was not possible.
  ///
  /// `Markdown` also moves to blocks that are not built yet (outside the lazily
  /// built range). A closed `details` is opened before moving. [alignment] is the
  /// position on screen (0 is the start, 1 is the end).
  Future<bool> jumpToAnchor(
    String id, {
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
    double alignment = 0,
  }) {
    final host = _host;
    if (host == null) return Future.value(false);
    return host.jumpToAnchor(
      id,
      duration: duration,
      curve: curve,
      alignment: alignment,
    );
  }

  /// Scrolls to the position of [heading]. Same as [jumpToAnchor].
  Future<bool> scrollToHeading(
    MarkdownXHeading heading, {
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
    double alignment = 0,
  }) => jumpToAnchor(
    heading.id,
    duration: duration,
    curve: curve,
    alignment: alignment,
  );

  /// Called when a Widget is attached.
  ///
  /// For internal use by the package; apps must not call it (`@internal`).
  @internal
  void attach(MarkdownXNavigationHost host) {
    assert(
      _host == null || identical(_host, host),
      'MarkdownXController cannot be attached to more than one Widget at a time',
    );
    _host = host;
  }

  /// Called when a Widget is detached.
  ///
  /// For internal use by the package; apps must not call it (`@internal`).
  @internal
  void detach(MarkdownXNavigationHost host) {
    if (identical(_host, host)) _host = null;
  }

  /// Notifies that the headings have changed.
  ///
  /// For internal use by the package; apps must not call it (`@internal`).
  @internal
  void notifyHeadingsChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
