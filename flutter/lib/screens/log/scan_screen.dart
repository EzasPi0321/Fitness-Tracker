import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../design/tokens.dart';
import '../../widgets/common.dart';

/// Full-screen barcode scanner (phones only). Returns the first product barcode it reads.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final v = b.rawValue;
      if (v != null && v.replaceAll(RegExp(r'\D'), '').length >= 6) {
        _done = true;
        HapticFeedback.heavyImpact();
        Navigator.pop(context, v);
        return;
      }
    }
  }

  Future<void> _type() async {
    final ctl = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Type barcode'),
        content: TextField(controller: ctl, autofocus: true, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Look up')),
        ],
      ),
    );
    if (code != null && code.trim().isNotEmpty && mounted) Navigator.pop(context, code);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan barcode', style: TextStyle(color: Colors.white)),
        actions: [
          IconButton(
            tooltip: 'Torch',
            onPressed: _controller.toggleTorch,
            icon: const FIcon(Symbols.flashlight_on, color: Colors.white),
          ),
          TextButton(
            onPressed: _type,
            child: const Text('Type it', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(S.xl),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Camera access is off. Allow it in Settings, or tap "Type it".'
                      : 'The camera isn’t available. Tap "Type it" to enter the barcode.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
          // Staging: one clear target in the middle of the frame.
          Center(
            child: Container(
              width: 280,
              height: 160,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(S.radiusCard),
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Point at the barcode',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}
