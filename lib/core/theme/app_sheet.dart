import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  useRootNavigator: true,
  useSafeArea: true,
  isScrollControlled: true,
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: 0.3),
  constraints: const BoxConstraints(maxWidth: 680),
  builder: builder,
);

/// Shared presentation for sheets with a scrollable list or form.
/// The body must attach [bodyBuilder]'s controller to its main scroll view.
class AppSheetScaffold extends StatefulWidget {
  const AppSheetScaffold({
    required this.title,
    required this.bodyBuilder,
    this.canDismiss = true,
    this.asSheet = true,
    this.headerAction,
    super.key,
  });

  final String title;
  final Widget Function(BuildContext, ScrollController?) bodyBuilder;
  final bool canDismiss;
  final bool asSheet;
  final Widget? headerAction;

  @override
  State<AppSheetScaffold> createState() => _AppSheetScaffoldState();
}

class _AppSheetScaffoldState extends State<AppSheetScaffold> {
  static const _dismissExtent = 0.3;
  static const _collapsedExtent = 0.6;
  final _sheet = DraggableScrollableController();

  double get _minimumExtent =>
      widget.canDismiss ? _dismissExtent : _collapsedExtent;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  void _resizeTo(double extent) {
    if (!_sheet.isAttached) return;
    _sheet.animateTo(
      extent,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _dragHeader(DragUpdateDetails details) {
    if (!_sheet.isAttached) return;
    _sheet.jumpTo(
      (_sheet.size - details.delta.dy / _sheet.sizeToPixels(1)).clamp(
        _minimumExtent,
        1.0,
      ),
    );
  }

  void _settleHeader(DragEndDetails details) {
    if (!_sheet.isAttached) return;
    final velocity = details.primaryVelocity ?? 0;
    final size = _sheet.size;
    final double target;
    if (velocity > 500) {
      target = size > _collapsedExtent ? _collapsedExtent : _minimumExtent;
    } else if (velocity < -500) {
      target = size < _collapsedExtent ? _collapsedExtent : 1;
    } else {
      target = size < (_minimumExtent + _collapsedExtent) / 2
          ? _minimumExtent
          : size < (_collapsedExtent + 1) / 2
          ? _collapsedExtent
          : 1;
    }
    _resizeTo(target);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.asSheet) {
      return PopScope(
        canPop: widget.canDismiss,
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            actions: [?widget.headerAction],
            leading: IconButton(
              tooltip: 'Close',
              onPressed: widget.canDismiss
                  ? () => Navigator.of(context).maybePop()
                  : null,
              icon: const Icon(CupertinoIcons.xmark),
            ),
          ),
          body: widget.bodyBuilder(context, null),
        ),
      );
    }
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      canPop: widget.canDismiss,
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification.extent == notification.minExtent &&
              notification.shouldCloseOnMinExtent) {
            Navigator.of(context).maybePop();
            return true;
          }
          return false;
        },
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: DraggableScrollableSheet(
            controller: _sheet,
            initialChildSize: _collapsedExtent,
            minChildSize: _minimumExtent,
            maxChildSize: 1,
            expand: false,
            snap: true,
            snapSizes: const [_collapsedExtent],
            shouldCloseOnMinExtent: widget.canDismiss,
            builder: (context, scrollController) => Material(
              key: const Key('app-sheet'),
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: Scaffold(
                backgroundColor: colors.surface,
                resizeToAvoidBottomInset: false,
                body: Column(
                  children: [
                    _buildHeader(context),
                    const Divider(height: 1),
                    Expanded(
                      child: Focus(
                        canRequestFocus: false,
                        onFocusChange: (focused) {
                          if (focused) _resizeTo(1);
                        },
                        child: widget.bodyBuilder(context, scrollController),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      key: const Key('app-sheet-header'),
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: (_) => FocusScope.of(context).unfocus(),
      onVerticalDragUpdate: _dragHeader,
      onVerticalDragEnd: _settleHeader,
      child: Column(
        children: [
          ListenableBuilder(
            listenable: _sheet,
            builder: (context, _) {
              final expanded = _sheet.isAttached && _sheet.size > 0.8;
              return Semantics(
                button: true,
                label: expanded ? 'Collapse sheet' : 'Expand sheet',
                onDismiss: widget.canDismiss
                    ? () => Navigator.of(context).maybePop()
                    : null,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    _resizeTo(expanded ? _collapsedExtent : 1);
                  },
                  child: SizedBox(
                    key: const Key('app-sheet-drag-handle'),
                    width: 72,
                    height: 24,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.4,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          SizedBox(
            height: 52,
            child: NavigationToolbar(
              middle: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: widget.headerAction == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: widget.headerAction,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
