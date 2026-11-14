// عميل SNMP v2c مبسّط (GET فقط) بدون أي حزم خارجية.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

class SnmpVar {
  final int tag;
  final Uint8List raw;
  SnmpVar(this.tag, this.raw);

  /// noSuchObject / noSuchInstance / endOfMibView
  bool get missing => tag == 0x80 || tag == 0x81 || tag == 0x82;

  String get asString => utf8.decode(raw, allowMalformed: true);

  int get asInt {
    if (raw.isEmpty) return 0;
    int v = (tag == 0x02 && (raw[0] & 0x80) != 0) ? -1 : 0;
    for (final b in raw) {
      v = (v << 8) | b;
    }
    return v;
  }
}

class SnmpResponse {
  final int requestId;
  final int errorStatus;
  final List<SnmpVar> vars;
  SnmpResponse(this.requestId, this.errorStatus, this.vars);
}

class FoundPrinter {
  final String ip;
  final String name;
  final String descr;
  FoundPrinter(this.ip, this.name, this.descr);
}

// ---------- ترميز BER ----------
List<int> _len(int n) {
  if (n < 128) return [n];
  if (n < 256) return [0x81, n];
  return [0x82, n >> 8, n & 0xff];
}

List<int> _tlv(int tag, List<int> c) => [tag, ..._len(c.length), ...c];

List<int> _int(int v) {
  final b = <int>[];
  var x = v;
  do {
    b.insert(0, x & 0xff);
    x >>= 8;
  } while (x > 0);
  if ((b[0] & 0x80) != 0) b.insert(0, 0);
  return _tlv(0x02, b);
}

List<int> _oid(String s) {
  final p = s.split('.').map(int.parse).toList();
  final out = <int>[40 * p[0] + p[1]];
  for (final n in p.skip(2)) {
    final tmp = <int>[n & 0x7f];
    var x = n >> 7;
    while (x > 0) {
      tmp.insert(0, (x & 0x7f) | 0x80);
      x >>= 7;
    }
    out.addAll(tmp);
  }
  return _tlv(0x06, out);
}

Uint8List buildGet(int reqId, List<String> oids, String community) {
  final vbs = <int>[];
  for (final o in oids) {
    vbs.addAll(_tlv(0x30, [..._oid(o), 0x05, 0x00]));
  }
  final pdu = _tlv(0xA0, [
    ..._int(reqId),
    ..._int(0),
    ..._int(0),
    ..._tlv(0x30, vbs),
  ]);
  return Uint8List.fromList(_tlv(0x30, [
    ..._int(1), // v2c
    ..._tlv(0x04, utf8.encode(community)),
    ...pdu,
  ]));
}

// ---------- فك الترميز ----------
class _Tlv {
  final int tag;
  final Uint8List value;
  final int next;
  _Tlv(this.tag, this.value, this.next);
}

_Tlv? _read(Uint8List d, int o) {
  if (o + 2 > d.length) return null;
  final tag = d[o];
  var l = d[o + 1];
  var p = o + 2;
  if ((l & 0x80) != 0) {
    final n = l & 0x7f;
    if (n == 0 || n > 2 || p + n > d.length) return null;
    l = 0;
    for (var i = 0; i < n; i++) {
      l = (l << 8) | d[p++];
    }
  }
  if (p + l > d.length) return null;
  return _Tlv(tag, Uint8List.sublistView(d, p, p + l), p + l);
}

List<_Tlv> _children(Uint8List d) {
  final out = <_Tlv>[];
  var o = 0;
  while (o < d.length) {
    final t = _read(d, o);
    if (t == null) break;
    out.add(t);
    o = t.next;
  }
  return out;
}

SnmpResponse? parseResponse(Uint8List d) {
  try {
    final top = _read(d, 0);
    if (top == null || top.tag != 0x30) return null;
    final parts = _children(top.value);
    if (parts.length < 3 || parts[2].tag != 0xA2) return null;
    final pdu = _children(parts[2].value);
    if (pdu.length < 4) return null;
    final vars = <SnmpVar>[];
    for (final vb in _children(pdu[3].value)) {
      final kv = _children(vb.value);
      if (kv.length < 2) return null;
      vars.add(SnmpVar(kv[1].tag, kv[1].value));
    }
    return SnmpResponse(
      SnmpVar(0x42, pdu[0].value).asInt,
      SnmpVar(0x42, pdu[1].value).asInt,
      vars,
    );
  } catch (_) {
    return null;
  }
}

// ---------- العميل ----------
class Snmp {
  static const sysDescr = '1.3.6.1.2.1.1.1.0';
  static const sysName = '1.3.6.1.2.1.1.5.0';

  static Future<List<SnmpVar>> get(
    String ip,
    List<String> oids, {
    String community = 'public',
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final reqId = Random().nextInt(0x7ffffff0) + 1;
    final c = Completer<List<SnmpVar>>();
    final sub = sock.listen((e) {
      if (e == RawSocketEvent.read) {
        final dg = sock.receive();
        if (dg == null) return;
        final r = parseResponse(dg.data);
        if (r != null && r.requestId == reqId && !c.isCompleted) {
          c.complete(r.vars);
        }
      }
    });
    try {
      sock.send(buildGet(reqId, oids, community), InternetAddress(ip), 161);
      return await c.future.timeout(timeout);
    } finally {
      await sub.cancel();
      sock.close();
    }
  }

  /// يبحث في الشبكة المحلية (x.x.x.1 - x.x.x.254) عن طابعات Epson.
  static Future<List<FoundPrinter>> scan(
    String prefix, {
    String community = 'public',
    Duration wait = const Duration(seconds: 4),
  }) async {
    final sock = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    final found = <String, FoundPrinter>{};
    final sub = sock.listen((e) {
      if (e != RawSocketEvent.read) return;
      final dg = sock.receive();
      if (dg == null) return;
      final r = parseResponse(dg.data);
      if (r == null || r.vars.length < 2) return;
      if (r.vars[0].missing || r.vars[1].missing) return;
      final descr = r.vars[0].asString;
      final name = r.vars[1].asString;
      if ('$descr $name'.toLowerCase().contains('epson')) {
        found[dg.address.address] = FoundPrinter(dg.address.address, name, descr);
      }
    });
    for (var i = 1; i <= 254; i++) {
      try {
        sock.send(buildGet(i, [sysDescr, sysName], community),
            InternetAddress('$prefix.$i'), 161);
      } catch (_) {}
      if (i % 32 == 0) await Future.delayed(const Duration(milliseconds: 20));
    }
    await Future.delayed(wait);
    await sub.cancel();
    sock.close();
    return found.values.toList();
  }

  /// بادئة الشبكة المحلية للجوال (مثل 192.168.1).
  static Future<String?> localPrefix() async {
    final ifs = await NetworkInterface.list(
        type: InternetAddressType.IPv4, includeLoopback: false);
    for (final i in ifs) {
      for (final a in i.addresses) {
        final ip = a.address;
        final p = ip.split('.');
        final ok = ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            (p[0] == '172' && int.parse(p[1]) >= 16 && int.parse(p[1]) <= 31);
        if (ok) return '${p[0]}.${p[1]}.${p[2]}';
      }
    }
    return null;
  }
}
