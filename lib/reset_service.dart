// نقطة الدمج المستقبلية لتصفير عدّاد وسادة الحبر.
//
// لا يتضمن هذا المشروع أوامر تصفير: بروتوكول إبسون لكتابة ذاكرة
// الطابعة غير منشور ولا يُخمَّن. إن حصلت على توثيق موثوق له،
// ضع تنفيذه في صنف يرث من ResetService ثم استبدل
// UnsupportedResetService في main.dart.

class ResetResult {
  final bool ok;
  final String message;
  ResetResult(this.ok, this.message);
}

abstract class ResetService {
  Future<ResetResult> resetWasteInkCounter(String ip);
}

class UnsupportedResetService implements ResetService {
  @override
  Future<ResetResult> resetWasteInkCounter(String ip) async {
    return ResetResult(
      false,
      'التصفير غير مفعّل في هذه النسخة: لا تتوفر أوامر موثوقة لتنفيذه عبر الشبكة.',
    );
  }
}
