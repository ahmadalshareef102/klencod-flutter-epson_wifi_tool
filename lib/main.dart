import 'package:flutter/material.dart';

import 'printer_service.dart';
import 'reset_service.dart';
import 'snmp.dart';

void main() => runApp(const EpsonApp());

class EpsonApp extends StatelessWidget {
  const EpsonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'أداة طابعة إبسون',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF1565C0),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ipCtrl = TextEditingController();
  final ResetService _reset = UnsupportedResetService();

  List<FoundPrinter> _found = [];
  PrinterInfo? _info;
  bool _scanning = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
      _found = [];
    });
    try {
      final prefix = await Snmp.localPrefix();
      if (prefix == null) {
        throw Exception('لم أجد شبكة واي فاي. تأكد أن الجوال متصل بنفس شبكة الطابعة.');
      }
      final res = await Snmp.scan(prefix);
      setState(() {
        _found = res;
        if (res.isEmpty) {
          _error = 'لم يتم العثور على طابعة. أدخل عنوان IP يدوياً.';
        } else if (res.length == 1) {
          _ipCtrl.text = res.first.ip;
        }
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _connect() async {
    final ip = _ipCtrl.text.trim();
    if (ip.isEmpty) {
      setState(() => _error = 'أدخل عنوان IP للطابعة.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _info = null;
    });
    try {
      final info = await fetchPrinterInfo(ip);
      setState(() => _info = info);
    } catch (_) {
      setState(() => _error =
          'تعذر الاتصال بالطابعة. تأكد من العنوان ومن أنها على نفس الشبكة وأن SNMP مفعّل.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _tryReset() async {
    final r = await _reset.resetWasteInkCounter(_ipCtrl.text.trim());
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(r.ok ? 'تم' : 'غير متاح'),
        content: Text(r.message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('حسناً'))
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أداة طابعة إبسون (واي فاي)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _ipCtrl,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(
              labelText: 'عنوان IP للطابعة',
              hintText: '192.168.1.50',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: const Icon(Icons.search),
                label: Text(_scanning ? 'جارٍ البحث...' : 'بحث تلقائي'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _loading ? null : _connect,
                icon: const Icon(Icons.print),
                label: Text(_loading ? 'جارٍ الاتصال...' : 'اتصال'),
              ),
            ),
          ]),
          if (_scanning || _loading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          for (final p in _found)
            Card(
              child: ListTile(
                leading: const Icon(Icons.print),
                title: Text(p.name.isEmpty ? p.descr : p.name),
                subtitle: Text(p.ip, textDirection: TextDirection.ltr),
                onTap: () {
                  _ipCtrl.text = p.ip;
                  _connect();
                },
              ),
            ),
          if (_info != null) ..._buildInfo(_info!),
          const SizedBox(height: 16),
          _buildResetCard(),
        ],
      ),
    );
  }

  List<Widget> _buildInfo(PrinterInfo i) {
    return [
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('الطابعة', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('الاسم: ${i.name}'),
            Text('الوصف: ${i.model}'),
            Text('الحالة: ${i.status}'),
            if (i.errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('تنبيهات: ${i.errors.join('، ')}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
      ),
      if (i.inks.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('مستوى الحبر', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final ink in i.inks)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${ink.name}: ${ink.percent == null ? 'غير معروف' : '${ink.percent}%'}'),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: ink.percent == null ? null : ink.percent! / 100,
                    ),
                  ]),
                ),
            ]),
          ),
        ),
    ];
  }

  Widget _buildResetCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('تصفير وسادة الحبر',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'هذه الميزة غير مفعّلة بعد. حالة وسادة الحبر لا تظهر عبر SNMP القياسي، '
            'والتصفير يحتاج أوامر خاصة بإبسون لم تُضَف إلى المشروع.',
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _tryReset,
            icon: const Icon(Icons.restart_alt),
            label: const Text('تصفير العدّاد'),
          ),
        ]),
      ),
    );
  }
}