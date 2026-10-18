"""Synthetic freedesktop notification server and KDE tray watcher for WSL/Xvfb.

Run with /usr/bin/python3 inside dbus-run-session; this is an opt-in platform
harness, not a unittest or a replacement for GNOME/KDE visual verification.
"""
import json
import os
import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
output = os.environ['COMPOISE_BUS_RESULT']


def record(kind, **facts):
    with open(output, 'a', encoding='utf-8') as stream:
        stream.write(json.dumps({'kind': kind, **facts}) + '\n')


class Notifications(dbus.service.Object):
    def __init__(self):
        self.name = dbus.service.BusName('org.freedesktop.Notifications', bus)
        super().__init__(bus, '/org/freedesktop/Notifications')
        self.next_id = 0

    @dbus.service.method('org.freedesktop.Notifications', out_signature='as')
    def GetCapabilities(self):
        return ['body', 'actions']

    @dbus.service.method('org.freedesktop.Notifications', out_signature='ssss')
    def GetServerInformation(self):
        return ('Compoise test', 'Compoise', '1', '1.2')

    @dbus.service.method('org.freedesktop.Notifications', in_signature='susssasa{sv}i', out_signature='u')
    def Notify(self, app, replaces, icon, title, body, actions, hints, timeout):
        self.next_id += 1
        record('notification', title=str(title), body=str(body))
        return self.next_id

    @dbus.service.method('org.freedesktop.Notifications', in_signature='u')
    def CloseNotification(self, identity):
        record('close', identity=int(identity))


class Tray(dbus.service.Object):
    def __init__(self):
        self.name = dbus.service.BusName('org.kde.StatusNotifierWatcher', bus)
        super().__init__(bus, '/StatusNotifierWatcher')

    @dbus.service.method('org.kde.StatusNotifierWatcher', in_signature='s')
    def RegisterStatusNotifierItem(self, item):
        record('tray', item=str(item))

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='ss', out_signature='v')
    def Get(self, interface, name):
        return self.GetAll(interface)[name]

    @dbus.service.method('org.freedesktop.DBus.Properties', in_signature='s', out_signature='a{sv}')
    def GetAll(self, interface):
        return {'IsStatusNotifierHostRegistered': dbus.Boolean(True), 'ProtocolVersion': dbus.Int32(0),
                'RegisteredStatusNotifierItems': dbus.Array([], signature='s')}


notifications = Notifications()
tray = Tray()
record('ready')
GLib.MainLoop().run()
