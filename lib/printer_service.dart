import 'snmp.dart';

class InkLevel {
  final String name;
  final int? percent; // null = غير معروف
  InkLevel(this.name, this.percent);
}

class PrinterInfo {
  final String model;
  final String name;
  final String status;
  final List<String> errors;
  final List<InkLevel> inks;
  PrinterInfo(this.model, this.name, this.status, this.errors, this.inks);
}

const _hrPrinterStatus = '1.3.6.1.2.1.25.3.5.1.1.1';
const _hrPrinterErrors = '1.3.6.1.2.1.25.3.5.1.2.1';
const _supDesc = '1.3.6.1.2.1.43.11.1.1.6.1.';
const _supMax = '1.3.6.1.2.1.43.11.1.1.8.1.';
const _supLevel = '1.3.6.1.2.1.43.11.1.1.9.1.';
const _maxSupplies = 6;

const _statusNames = {
  1: 'أخرى',
  2: 'غير معروفة',
  3: 'جاهزة',
  4: 'تطبع',
  5: 'تسخين',
};

// RFC 1514: البتّ الأول هو الأعلى قيمة في البايت الأول.
const _errorBits = <int, String>{
  0x80: 'الورق قليل',
  0x40: 'لا يوجد ورق',
  0x20: 'الحبر قليل',
  0x10: 'الحبر نفد',
  0x08: 'الغطاء مفتوح',
  0x04: 'انحشار ورق',
  0x02: 'الطابعة غير متصلة',
  0x01: 'تحتاج صيانة',
};

Future<PrinterInfo> fetchPrinterInfo(String ip) async {
  final oids = <String>[
    Snmp.sysDescr,
    Snmp.sysName,
    _hrPrinterStatus,
    _hrPrinterErrors,
    for (var i = 1; i <= _maxSupplies; i++) ...[
      '$_supDesc$i',
      '$_supLevel$i',
      '$_supMax$i',
    ],
  ];
  final v = await Snmp.get(ip, oids);
  if (v.length < oids.length) {
    throw Exception('رد غير مكتمل من الطابعة');
  }

  final model = v[0].missing ? '-' : v[0].asString;
  final name = v[1].missing ? '-' : v[1].asString;
  final status =
      v[2].missing ? 'غير معروفة' : (_statusNames[v[2].asInt] ?? 'غير معروفة');

  final errors = <String>[];
  if (!v[3].missing && v[3].raw.isNotEmpty) {
    final b = v[3].raw[0];
    _errorBits.forEach((mask, text) {
      if ((b & mask) != 0) errors.add(text);
    });
  }

  final inks = <InkLevel>[];
  for (var i = 0; i < _maxSupplies; i++) {
    final d = v[4 + i * 3];
    final l = v[5 + i * 3];
    final m = v[6 + i * 3];
    if (d.missing) continue;
    int? pct;
    if (!l.missing && !m.missing && l.asInt >= 0 && m.asInt > 0) {
      pct = (l.asInt * 100 / m.asInt).round().clamp(0, 100);
    }
    inks.add(InkLevel(d.asString, pct));
  }
  return PrinterInfo(model, name, status, errors, inks);
}
