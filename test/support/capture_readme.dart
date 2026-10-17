// Renders README media from the real app widgets and synthetic data.
// See docs/media/README.md for the regeneration command.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:compoise/models.dart';
import 'package:compoise/schedule_item.dart';
import 'package:compoise/schedule_time.dart';
import 'package:compoise/screens/matrix_screen.dart';
import 'package:compoise/screens/planner_screen.dart';
import 'package:compoise/storage.dart';
import 'package:compoise/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _boundaryKey = ValueKey('readme-capture');
const _size = Size(390, 844);

class _NoCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> delete() async {}
}

void main() {
  testWidgets('render README previews', (tester) async {
    final font = Platform.environment['COMPOISE_README_FONT'];
    final icons = Platform.environment['COMPOISE_README_ICONS'];
    if (font == null || icons == null) {
      throw StateError('Set COMPOISE_README_FONT and COMPOISE_README_ICONS.');
    }
    await tester.runAsync(() async {
      for (final entry in {
        'ReadmeSans': font,
        'MaterialIcons': icons,
      }.entries) {
        await (FontLoader(entry.key)..addFont(
              Future.value(
                ByteData.sublistView(await File(entry.value).readAsBytes()),
              ),
            ))
            .load();
      }
      await Directory('docs/media').create(recursive: true);
      await Directory('build/readme-frames').create(recursive: true);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = _size;
    addTearDown(tester.view.reset);

    for (final language in [Language.zh, Language.en]) {
      final zh = language == Language.zh;
      final suffix = language.name;
      String text(String chinese, String english) => zh ? chinese : english;
      final board = Board(
        id: 'demo',
        name: text('我的一天', 'My day'),
        createdAt: 1,
      );
      Task task(
        String id,
        String title,
        int quadrant, {
        List<SubTask>? steps,
      }) => Task(
        id: id,
        boardId: board.id,
        title: title,
        quadrant: quadrant,
        createdAt: 1,
        urgencyMode: UrgencyMode.manual,
        subtasks: steps,
      );
      final tasks = [
        task(
          'report',
          text('完成项目提案', 'Finish the project proposal'),
          1,
          steps: [
            SubTask(
              id: 'outline',
              title: text('梳理提案大纲', 'Outline the proposal'),
              completed: true,
            ),
            SubTask(
              id: 'draft',
              title: text('补充方案与预算', 'Add the plan and budget'),
            ),
            SubTask(id: 'review', title: text('检查并发送提案', 'Review and send')),
          ],
        ),
        task('meeting', text('准备下午的分享', 'Prepare for the team talk'), 1),
        task('read', text('阅读 30 分钟', 'Read for 30 minutes'), 2),
        task('walk', text('傍晚散步', 'Take an evening walk'), 2),
        task('trip', text('规划周末短途旅行', 'Plan a weekend trip'), 2),
        task('parcel', text('取快递', 'Pick up a parcel'), 3),
        task('reply', text('回复活动邀约', 'Reply to an invitation'), 3),
        task('photos', text('整理相册', 'Organize photos'), 4),
      ];
      int at(int hour, [int minute = 0]) =>
          DateTime.utc(2026, 10, 17, hour - 8, minute).millisecondsSinceEpoch;
      final schedule = [
        ScheduleItem.timeBlock(
          id: 'deep-work',
          taskId: 'report',
          startAt: at(9),
          endAt: at(10, 30),
          timeZoneId: 'Asia/Shanghai',
        ),
        ScheduleItem.event(
          id: 'sync',
          title: text('团队讨论', 'Team catch-up'),
          boardId: 'demo',
          startAt: at(11),
          endAt: at(12),
          timeZoneId: 'Asia/Shanghai',
        ),
        ScheduleItem.timeBlock(
          id: 'reading',
          taskId: 'read',
          startAt: at(13),
          endAt: at(13, 30),
          timeZoneId: 'Asia/Shanghai',
        ),
        ScheduleItem.timeBlock(
          id: 'talk',
          taskId: 'meeting',
          startAt: at(14),
          endAt: at(15),
          timeZoneId: 'Asia/Shanghai',
        ),
      ];
      SharedPreferences.setMockInitialValues({
        'compoise-boards': jsonEncode([board.toJson()]),
        'compoise-tasks': jsonEncode(tasks.map((t) => t.toJson()).toList()),
        'compoise-schedule': jsonEncode(
          schedule.map((s) => s.toJson()).toList(),
        ),
        'compoise-settings': jsonEncode(
          AppSettings(
            language: language,
            themeColor: ThemeColor.green,
          ).toJson(),
        ),
        'compoise-has-seen-onboarding': true,
      });
      final store = Store(credentialStore: _NoCredentials());
      await store.init();
      await store.flush(waitForReminders: false);
      final theme = buildTheme(
        Brightness.light,
        ThemeColor.green,
        platform: TargetPlatform.android,
      );
      Widget app(Widget home) => ChangeNotifierProvider.value(
        value: store,
        child: RepaintBoundary(
          key: _boundaryKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(suffix),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh'), Locale('en'), Locale('ja')],
            theme: theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'ReadmeSans'),
            ),
            home: home,
          ),
        ),
      );
      Future<void> capture(String path) async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_boundaryKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1.5);
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(path).writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        });
      }

      await tester.pumpWidget(app(const MatrixHome()));
      await tester.pumpAndSettle();
      await capture('docs/media/matrix-$suffix.png');
      var frame = 0;
      Future<void> frames(int count) async {
        for (var i = 0; i < count; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          await capture(
            'build/readme-frames/$suffix-${(frame++).toString().padLeft(3, '0')}.png',
          );
        }
      }

      await frames(14);
      await tester.tap(find.byKey(const ValueKey('quadrant-header-1')));
      await frames(8);
      await tester.pumpAndSettle();
      await frames(18);
      await tester.tap(find.byKey(const ValueKey('focus-back-btn')));
      await frames(8);
      await tester.pumpAndSettle();
      await frames(14);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(
          PlannerScreen(
            store: store,
            displayTimeZoneId: 'Asia/Shanghai',
            initialDate: ScheduleCivilDate(2026, 10, 17),
            now: () => DateTime.utc(2026, 10, 17, 1),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await capture('docs/media/schedule-$suffix.png');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    }
  });
}
