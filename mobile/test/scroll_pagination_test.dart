import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timedrop_mobile/ui/utils/scroll_pagination.dart';

/// A minimal host for the mixin: a long list that only builds what the
/// pagination window allows, wired the way the real screens wire it.
class _PagedList extends StatefulWidget {
  const _PagedList({required this.total});

  final int total;

  @override
  State<_PagedList> createState() => _PagedListState();
}

class _PagedListState extends State<_PagedList> with ScrollPaginationMixin {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: (n) => handleScrollForPagination(n, widget.total),
          child: ListView(
            children: [
              for (var i = 0; i < visibleOf(widget.total); i++)
                SizedBox(height: 200, child: Text('item $i')),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _scrollToBottom(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, -4000));
  await tester.pumpAndSettle();
}

void main() {
  group('ScrollPaginationMixin', () {
    testWidgets('starts at one page, whatever the list length', (tester) async {
      await tester.pumpWidget(const _PagedList(total: 40));

      expect(find.text('item 0'), findsOneWidget);
      expect(
        find.text('item ${ScrollPaginationMixin.pageSize}'),
        findsNothing,
        reason: 'the second page must not be built before it is asked for',
      );
    });

    testWidgets('a short list is fully built and never pages', (tester) async {
      await tester.pumpWidget(const _PagedList(total: 3));

      expect(find.text('item 2'), findsOneWidget);

      // Nothing to grow into — dragging must not throw or over-count.
      await _scrollToBottom(tester);
      expect(find.text('item 2'), findsOneWidget);
    });

    testWidgets('scrolling to the end reveals the next page', (tester) async {
      await tester.pumpWidget(const _PagedList(total: 40));
      final state = tester.state<_PagedListState>(find.byType(_PagedList));
      final before = state.visibleCount;

      await _scrollToBottom(tester);

      expect(state.visibleCount, greaterThan(before));
    });

    testWidgets('growth stops exactly at the total', (tester) async {
      const total = 12;
      await tester.pumpWidget(const _PagedList(total: total));
      final state = tester.state<_PagedListState>(find.byType(_PagedList));

      // More drags than pages, so it would overshoot if unclamped.
      for (var i = 0; i < 6; i++) {
        await _scrollToBottom(tester);
      }

      expect(state.visibleCount, total);
    });

    testWidgets('ensureVisibleIndex opens the window far enough', (tester) async {
      await tester.pumpWidget(const _PagedList(total: 40));
      final state = tester.state<_PagedListState>(find.byType(_PagedList));

      // The Vault does this so it can scroll to a just-opened memory that
      // would otherwise not have been built at all.
      state.ensureVisibleIndex(23);
      await tester.pump();

      expect(state.visibleCount, greaterThan(23));
    });

    testWidgets('ensureVisibleIndex never shrinks the window', (tester) async {
      await tester.pumpWidget(const _PagedList(total: 40));
      final state = tester.state<_PagedListState>(find.byType(_PagedList));

      state.ensureVisibleIndex(30);
      await tester.pump();
      final wide = state.visibleCount;

      state.ensureVisibleIndex(1);
      await tester.pump();

      expect(state.visibleCount, wide);
    });

    testWidgets('resetPagination returns to the first page', (tester) async {
      await tester.pumpWidget(const _PagedList(total: 40));
      final state = tester.state<_PagedListState>(find.byType(_PagedList));

      state.ensureVisibleIndex(20);
      await tester.pump();
      state.resetPagination();
      await tester.pump();

      expect(state.visibleCount, ScrollPaginationMixin.pageSize);
    });
  });
}
