أداة طابعة إبسون (واي فاي) - فلاتر

الملفات:
- pubspec.yaml
- lib/main.dart            الواجهة العربية (RTL)
- lib/snmp.dart            عميل SNMP v2c مكتوب بلغة Dart (بدون حزم خارجية)
- lib/printer_service.dart قراءة الحالة والحبر
- lib/reset_service.dart   نقطة دمج التصفير (غير مفعّلة)

خطوات مهمة في Klencod:
1) إن كان المشروع يحتوي مجلد android فتأكد أن AndroidManifest.xml يحتوي:
   <uses-permission android:name="android.permission.INTERNET"/>
   (داخل <manifest> وقبل <application>)
2) الجوال والطابعة على نفس شبكة الواي فاي.
3) يجب أن يكون SNMP مفعّلاً في الطابعة (غالباً مفعّل افتراضياً، المجتمع: public).

ملاحظة: التصفير غير مفعّل لأنه لا توجد أوامر موثوقة لتنفيذه.
