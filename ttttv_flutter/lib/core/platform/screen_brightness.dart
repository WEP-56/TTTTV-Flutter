import 'package:flutter/services.dart';

const _channel = MethodChannel('ttttv/screen_brightness');

Future<double> readScreenBrightness() async {
  try {
    final value = await _channel.invokeMethod<double>('get');
    return (value ?? 1.0).clamp(0.0, 1.0).toDouble();
  } catch (_) {
    return 1.0;
  }
}

Future<void> setScreenBrightness(double value) async {
  try {
    await _channel.invokeMethod<void>('set', value.clamp(0.0, 1.0));
  } catch (_) {
    // Unsupported platforms keep the UI preview only.
  }
}

Future<void> resetScreenBrightness() async {
  try {
    await _channel.invokeMethod<void>('reset');
  } catch (_) {
    // Unsupported platforms do not need reset handling.
  }
}
