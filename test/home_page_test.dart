import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bin/api/roblox_api.dart';
import 'package:bin/render/avatar_assembler.dart';
import 'package:bin/render/avatar_view.dart';
import 'package:bin/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

class _FakeApi extends RobloxApi {
  _FakeApi({this.result, this.error});

  final AvatarFetchResult? result;
  final Object? error;

  @override
  Future<AvatarFetchResult> fetchAvatar(
    String username, {
    void Function(String status)? onStatus,
    AvatarAssembler? assembler,
  }) async {
    onStatus?.call('Resolving $username...');
    onStatus?.call('Downloading model...');
    if (error != null) throw error!;
    return result!;
  }
}

Widget _page(RobloxApi api) => MaterialApp(home: HomePage(api: api));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders avatar after fetch', (tester) async {
    final api = _FakeApi(
      result: AvatarFetchResult(
          userId: 156, username: 'builderman', model: buildTestModel()),
    );
    await tester.pumpWidget(_page(api));
    await tester.runAsync(() async {
      await tester.tap(find.text('Render'));
      await Future.delayed(const Duration(seconds: 1));
      await tester.pump();
    });
    await tester.pump();
    expect(find.byType(AvatarView), findsOneWidget);
    expect(find.textContaining('builderman'), findsWidgets);
  });

  testWidgets('submitting from keyboard also fetches', (tester) async {
    final api = _FakeApi(
      result: AvatarFetchResult(
          userId: 1, username: 'roblox', model: buildTestModel()),
    );
    await tester.pumpWidget(_page(api));
    await tester.enterText(find.byType(TextField), 'roblox');
    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.go);
      await Future.delayed(const Duration(seconds: 1));
      await tester.pump();
    });
    await tester.pump();
    expect(find.byType(AvatarView), findsOneWidget);
  });

  testWidgets('empty username resets to idle', (tester) async {
    final api = _FakeApi();
    await tester.pumpWidget(_page(api));
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Render'));
    await tester.pump();
    expect(find.text('Enter a Roblox username'), findsOneWidget);
  });

  testWidgets('fetch error shows error state', (tester) async {
    final api = _FakeApi(
        error: AvatarFetchException('No Roblox user named "ghost"'));
    await tester.pumpWidget(_page(api));
    await tester.enterText(find.byType(TextField), 'ghost');
    await tester.tap(find.text('Render'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('No Roblox user'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('timeout shows connection message', (tester) async {
    final api = _FakeApi(
        error: TimeoutException('deadline', const Duration(seconds: 1)));
    await tester.pumpWidget(_page(api));
    await tester.tap(find.text('Render'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Request timed out'), findsOneWidget);
  });

  testWidgets('unexpected error shows generic message', (tester) async {
    final api = _FakeApi(error: StateError('boom'));
    await tester.pumpWidget(_page(api));
    await tester.tap(find.text('Render'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('Failed to load avatar'), findsOneWidget);
  });

  testWidgets('local glb path renders directly', (tester) async {
    final path =
        '${Directory.systemTemp.path}/bin_widget_${DateTime.now().microsecondsSinceEpoch}.glb';
    File(path).writeAsBytesSync(buildTestGlb());
    await tester.pumpWidget(_page(_FakeApi()));
    await tester.enterText(find.byType(TextField), path);
    await tester.runAsync(() async {
      await tester.tap(find.text('Render'));
      await Future.delayed(const Duration(seconds: 1));
      await tester.pump();
    });
    await tester.pump();
    expect(find.byType(AvatarView), findsOneWidget);
    expect(find.textContaining('.glb'), findsWidgets);
    File(path).deleteSync();
  });

  testWidgets('missing local glb shows error', (tester) async {
    await tester.pumpWidget(_page(_FakeApi()));
    await tester.enterText(find.byType(TextField), '/no/such/model.glb');
    await tester.runAsync(() async {
      await tester.tap(find.text('Render'));
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });
    await tester.pump();
    expect(find.textContaining('Could not read'), findsOneWidget);
  });

  testWidgets('parse failure shows generic message', (tester) async {
    final path =
        '${Directory.systemTemp.path}/bin_bad_${DateTime.now().microsecondsSinceEpoch}.glb';
    File(path).writeAsBytesSync(Uint8List(3));
    await tester.pumpWidget(_page(_FakeApi()));
    await tester.enterText(find.byType(TextField), path);
    await tester.runAsync(() async {
      await tester.tap(find.text('Render'));
      await Future.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });
    await tester.pump();
    expect(find.textContaining('Failed to load avatar'), findsOneWidget);
    File(path).deleteSync();
  });
}
