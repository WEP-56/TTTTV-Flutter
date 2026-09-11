import 'dart:io';

import 'package:flutter/services.dart';

class AndroidMedia {
  static const channel = MethodChannel('ttttv/media');

  static Future<bool> supportsPip() async {
    if (!Platform.isAndroid) return false;
    return await channel.invokeMethod<bool>('supportsPip') ?? false;
  }

  static Future<bool> enterPip() async =>
      await channel.invokeMethod<bool>('enterPip') ?? false;

  static Future<void> setPlaying(bool playing) async {
    if (Platform.isAndroid)
      await channel.invokeMethod<void>('setPlaying', playing);
  }

  static Future<void> multicast(bool acquire) async {
    if (Platform.isAndroid)
      await channel.invokeMethod<void>('multicast', acquire);
  }
}
