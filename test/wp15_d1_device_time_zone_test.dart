import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrixflow_native/platform/device_time_zone.dart';
import 'package:matrixflow_native/platform/windows_time_zone_map.dart';

/// A Linux-looking filesystem for the zone sources.
LinuxDeviceTimeZoneSource linuxSource({
  Map<String, String> environment = const {},
  Map<String, String> files = const {},
  Map<String, String> links = const {},
}) => LinuxDeviceTimeZoneSource(
  environment: environment,
  readFile: (path) async => files[path],
  readLink: (path) async => links[path],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('device identity resolution', () {
    test('an Android IANA id is used as reported', () {
      final status = resolveDeviceTimeZone(
        const DeviceTimeZoneReading(
          platform: DeviceTimeZonePlatform.android,
          identity: 'Asia/Shanghai',
        ),
      );
      expect(status.ianaId, 'Asia/Shanghai');
      expect(status.problem, isNull);
    });

    test('a Windows key is translated through the pinned CLDR table', () {
      final status = resolveDeviceTimeZone(
        const DeviceTimeZoneReading(
          platform: DeviceTimeZonePlatform.windows,
          identity: 'Tokyo Standard Time',
        ),
      );
      expect(status.ianaId, 'Asia/Tokyo');
      expect(status.identity, 'Tokyo Standard Time');
    });

    test('a Windows key outside the table is reported, never guessed', () {
      final status = resolveDeviceTimeZone(
        const DeviceTimeZoneReading(
          platform: DeviceTimeZonePlatform.windows,
          identity: 'Neverland Standard Time',
        ),
      );
      expect(status.resolved, isFalse);
      expect(status.problem, DeviceTimeZoneProblem.unmapped);
      expect(status.identity, 'Neverland Standard Time');
    });

    test('an unreadable platform reports unavailability', () {
      final status = resolveDeviceTimeZone(
        const DeviceTimeZoneReading.unreadable(DeviceTimeZonePlatform.linux),
      );
      expect(status.resolved, isFalse);
      expect(status.problem, DeviceTimeZoneProblem.unavailable);
      expect(status.identity, isNull);
    });

    test('a non-IANA platform value fails validation', () {
      final status = resolveDeviceTimeZone(
        const DeviceTimeZoneReading(
          platform: DeviceTimeZonePlatform.android,
          identity: 'Mars/Phobos',
        ),
      );
      expect(status.problem, DeviceTimeZoneProblem.invalid);
      expect(status.identity, 'Mars/Phobos');
    });

    test('blank identities are treated as unavailable', () {
      for (final identity in <String?>[null, '', '   ']) {
        final status = resolveDeviceTimeZone(
          DeviceTimeZoneReading(
            platform: DeviceTimeZonePlatform.linux,
            identity: identity,
          ),
        );
        expect(status.resolved, isFalse);
        expect(status.problem, DeviceTimeZoneProblem.unavailable);
      }
    });
  });

  group('IANA validation and catalogue', () {
    test('recognizes real zones and rejects look-alikes', () {
      expect(isKnownIanaTimeZone('Asia/Shanghai'), isTrue);
      expect(isKnownIanaTimeZone('America/New_York'), isTrue);
      expect(isKnownIanaTimeZone('Not/AZone'), isFalse);
      expect(isKnownIanaTimeZone(''), isFalse);
      expect(isKnownIanaTimeZone(' Asia/Shanghai'), isFalse);
      expect(isKnownIanaTimeZone('asia/shanghai'), isFalse);
    });

    test('lists region ids and filters them for the picker', () {
      final all = scheduleZoneIds();
      expect(all.length, greaterThan(400));
      expect(all, contains('Asia/Shanghai'));
      expect(all.every((id) => id.contains('/')), isTrue);
      expect(searchScheduleZoneIds('shanghai'), contains('Asia/Shanghai'));
      expect(searchScheduleZoneIds('shanghai', limit: 1), hasLength(1));
      expect(searchScheduleZoneIds('nowhere/at/all'), isEmpty);
    });
  });

  group('Windows mapping table', () {
    test('is the CLDR territory-001 set with a pinned source', () {
      expect(windowsTimeZoneMapRelease, 'CLDR 47');
      expect(windowsTimeZoneMapSourceSha256, hasLength(64));
      expect(windowsTimeZoneToIana, hasLength(139));
      expect(windowsTimeZoneToIana['China Standard Time'], 'Asia/Shanghai');
      expect(windowsTimeZoneToIana['W. Europe Standard Time'], 'Europe/Berlin');
      expect(
        windowsTimeZoneToIana['Pacific Standard Time'],
        'America/Los_Angeles',
      );
    });

    test('every mapped zone exists in the bundled database', () {
      final missing = <String>[
        for (final entry in windowsTimeZoneToIana.entries)
          if (!isKnownIanaTimeZone(entry.value))
            '${entry.key} -> ${entry.value}',
      ];
      expect(missing, isEmpty);
    });

    test('lookup tolerates a differently cased key', () {
      expect(ianaForWindowsIdentity('tokyo standard time'), 'Asia/Tokyo');
      expect(ianaForWindowsIdentity('  Tokyo Standard Time  '), 'Asia/Tokyo');
      expect(ianaForWindowsIdentity(''), isNull);
      expect(ianaForWindowsIdentity('Unknown Standard Time'), isNull);
    });
  });

  group('Linux system configuration', () {
    test('TZ names the zone, with or without the POSIX colon', () async {
      expect(
        (await linuxSource(environment: {'TZ': 'Asia/Tokyo'}).read()).identity,
        'Asia/Tokyo',
      );
      expect(
        (await linuxSource(environment: {'TZ': ':America/New_York'}).read())
            .identity,
        'America/New_York',
      );
    });

    test('TZ may be a zoneinfo path', () async {
      final reading = await linuxSource(
        environment: {'TZ': '/usr/share/zoneinfo/Europe/Paris'},
      ).read();
      expect(reading.identity, 'Europe/Paris');
    });

    test('a POSIX TZ rule is not silently treated as a zone', () async {
      final reading = await linuxSource(environment: {'TZ': 'CST-8'}).read();
      expect(reading.identity, 'CST-8');
      expect(resolveDeviceTimeZone(reading).problem, DeviceTimeZoneProblem.invalid);
    });

    test('TZ pointing at localtime falls through to the files', () async {
      final reading = await linuxSource(
        environment: {'TZ': ':/etc/localtime'},
        files: {'/etc/timezone': 'Europe/Berlin\n'},
      ).read();
      expect(reading.identity, 'Europe/Berlin');
    });

    test('/etc/timezone is read when TZ is unset', () async {
      final reading = await linuxSource(
        files: {'/etc/timezone': '\n  Europe/Berlin  \n'},
      ).read();
      expect(reading.identity, 'Europe/Berlin');
      expect(resolveDeviceTimeZone(reading).ianaId, 'Europe/Berlin');
    });

    test('a broken /etc/timezone is reported instead of ignored', () async {
      final reading = await linuxSource(
        files: {'/etc/timezone': 'Mars/Phobos'},
        links: {'/etc/localtime': '/usr/share/zoneinfo/Asia/Tokyo'},
      ).read();
      expect(reading.identity, 'Mars/Phobos');
      expect(resolveDeviceTimeZone(reading).problem, DeviceTimeZoneProblem.invalid);
    });

    test('the /etc/localtime symlink names the zone', () async {
      final reading = await linuxSource(
        links: {'/etc/localtime': '/usr/share/zoneinfo/Australia/Sydney'},
      ).read();
      expect(reading.identity, 'Australia/Sydney');
    });

    test('a copied /etc/localtime carries no name and is not guessed', () async {
      final reading = await linuxSource().read();
      expect(reading.unreadable, isTrue);
      expect(
        resolveDeviceTimeZone(reading).problem,
        DeviceTimeZoneProblem.unavailable,
      );
    });
  });

  group('platform channel source', () {
    const channel = MethodChannel(deviceTimeZoneChannelName);

    void mock(Future<Object?>? Function(MethodCall call) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, handler);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
    }

    test('reads the reported identity', () async {
      mock((call) async {
        expect(call.method, 'systemZone');
        return {'platform': 'windows', 'identity': 'China Standard Time'};
      });
      final reading = await ChannelDeviceTimeZoneSource(
        channel: channel,
      ).read();
      expect(reading.platform, DeviceTimeZonePlatform.windows);
      expect(resolveDeviceTimeZone(reading).ianaId, 'Asia/Shanghai');
    });

    test('a reply without an identity is unreadable', () async {
      mock((call) async => {'platform': 'android', 'identity': null});
      final reading = await ChannelDeviceTimeZoneSource(
        channel: channel,
      ).read();
      expect(reading.unreadable, isTrue);
      expect(reading.platform, DeviceTimeZonePlatform.android);
    });

    test('a platform that cannot answer is unreadable, not UTC', () async {
      mock((call) async => throw MissingPluginException('no handler'));
      final reading = await ChannelDeviceTimeZoneSource(
        channel: channel,
      ).read();
      expect(reading.unreadable, isTrue);
      expect(resolveDeviceTimeZone(reading).ianaId, isNull);
    });
  });
}
