import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../core/storage/trust_store.dart';
import '../l10n/l10n_context.dart';
import '../theme/app_theme.dart';

/// Convert a Base64url (no-padding) string to its lowercase hex equivalent.
String _b64ToHex(String b64) {
  // Restore padding that was stripped for compactness.
  final padded = b64.padRight((b64.length + 3) ~/ 4 * 4, '=');
  final bytes = base64Url.decode(padded);
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Parse the compact text form of a contact card.
///
/// Supports two wire formats:
///  • `nyx4;id;name;ik_b64;sk_b64;kpk_b64` — current (Base64url keys)
///  • `nyx3;id;name;ik_hex;sk_hex;kpk_hex` — legacy (hex keys)
Map<String, dynamic>? parseContactCard(String raw) {
  final s = raw.trim();

  if (s.startsWith('nyx4;')) {
    // Current format: keys are Base64url-encoded (no padding).
    final parts = s.split(';');
    if (parts.length != 6) return null;
    try {
      return {
        'nyx': 3,
        'id': parts[1],
        'name': parts[2],
        'ik': _b64ToHex(parts[3]),
        'sk': _b64ToHex(parts[4]),
        'kpk': _b64ToHex(parts[5]),
      };
    } catch (_) {
      return null;
    }
  }

  if (s.startsWith('nyx3;')) {
    // Legacy format: keys are hex-encoded.
    final parts = s.split(';');
    if (parts.length != 6) return null;
    return {'nyx': 3, 'id': parts[1], 'name': parts[2], 'ik': parts[3], 'sk': parts[4], 'kpk': parts[5]};
  }

  return null;
}

/// Camera scanner for contact-card QR codes. Pops with the pinned
/// [PinnedPeer] on success.
class ScanCardScreen extends StatefulWidget {
  const ScanCardScreen({super.key});
  @override
  State<ScanCardScreen> createState() => _ScanCardScreenState();
}

class _ScanCardScreenState extends State<ScanCardScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  bool _handled = false;
  String? _status;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    for (final code in capture.barcodes) {
      final raw = code.rawValue;
      if (raw == null) continue;
      final card = parseContactCard(raw);
      if (card == null) {
        setState(() => _status = context.l10n.notANyxChatContactCard);
        continue;
      }
      _handled = true;
      try {
        final peer = await context.read<TrustStore>().pinFromContactCard(card, verified: true);
        if (!mounted) return;
        Navigator.pop(context, peer);
      } catch (e) {
        _handled = false;
        if (!mounted) return;
        setState(() => _status = context.l10n.invalidCard('$e'));
      }
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.nyx.background,
      appBar: AppBar(
        backgroundColor: context.nyx.background,
        elevation: 0,
        title: Text(context.l10n.scanContactCard, style: TextStyle(color: context.nyx.textPrimary, fontSize: 17, fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: Icon(Icons.flash_on_outlined, color: context.nyx.textSecondary),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Stack(children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Center(
              child: Container(
                width: 240, height: 240,
                decoration: BoxDecoration(
                  border: Border.all(color: context.nyx.accentBlue.withValues(alpha: 0.8), width: 2),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          color: context.nyx.surface,
          child: Column(children: [
            Text(_status ?? context.l10n.pointCameraHint,
                textAlign: TextAlign.center,
                style: TextStyle(color: _status == null ? context.nyx.textSecondary : context.nyx.warning, fontSize: 13)),
            const SizedBox(height: 6),
            Text(context.l10n.scanningPinsKeys,
                textAlign: TextAlign.center, style: TextStyle(color: context.nyx.textMuted, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }
}