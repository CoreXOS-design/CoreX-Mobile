import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Full-screen finger signature. Pops with a `data:image/png;base64,...`
/// string (what the inspection signature route takes, ≤ 1 MB), or null.
class SignaturePadScreen extends StatefulWidget {
  final String title;
  const SignaturePadScreen({super.key, required this.title});

  static Future<String?> capture(BuildContext context, String title) =>
      Navigator.of(context).push<String>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SignaturePadScreen(title: title),
      ));

  @override
  State<SignaturePadScreen> createState() => _SignaturePadScreenState();
}

class _SignaturePadScreenState extends State<SignaturePadScreen> {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;
  bool _saving = false;

  bool get _empty => _strokes.every((s) => s.length < 2);

  Future<void> _save() async {
    setState(() => _saving = true);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(Offset.zero & _size, Paint()..color = Colors.white);
    _SignaturePainter(_strokes, Colors.black).paint(canvas, _size);
    final image = await recorder
        .endRecording()
        .toImage(_size.width.ceil(), _size.height.ceil());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted) return;
    if (bytes == null) {
      setState(() => _saving = false);
      return;
    }
    Navigator.of(context).pop(
        'data:image/png;base64,${base64Encode(bytes.buffer.asUint8List())}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _empty ? null : () => setState(_strokes.clear),
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: _empty || _saving ? null : _save,
            child: const Text('Done'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text('Sign in the box with your finger.'),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(builder: (context, c) {
                _size = Size(c.maxWidth, c.maxHeight);
                return Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black26),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: GestureDetector(
                    onPanStart: (d) =>
                        setState(() => _strokes.add([d.localPosition])),
                    onPanUpdate: (d) =>
                        setState(() => _strokes.last.add(d.localPosition)),
                    child: CustomPaint(
                      painter: _SignaturePainter(_strokes, Colors.black),
                      size: Size.infinite,
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;
  final Color color;
  _SignaturePainter(this.strokes, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final s in strokes) {
      if (s.length < 2) continue;
      final path = Path()..moveTo(s.first.dx, s.first.dy);
      for (final o in s.skip(1)) {
        path.lineTo(o.dx, o.dy);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter old) => true;
}
