import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

bool looksLikeNetworkPermissionIssue(Object? error) {
  final text = error?.toString().toLowerCase() ?? '';
  return text.contains('failed host lookup') ||
      text.contains('socketexception') ||
      text.contains('connection error') ||
      text.contains('errno = 7');
}

Future<void> openAppSystemSettings(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);

  final candidates = <Uri>[
    Uri.parse('app-settings:'),
    Uri.parse('package:com.ttttv.app'),
  ];

  for (final uri in candidates) {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }
  }

  if (context.mounted) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('无法直接打开系统设置，请手动前往应用设置检查联网限制。'),
      ),
    );
  }
}

Future<void> showNetworkPermissionGuideDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('检查联网权限'),
        content: const Text(
          '当前设备疑似拦截了应用联网。\n\n'
          '请前往系统设置，检查本应用是否被限制移动数据、WLAN、后台联网或受限网络访问。\n\n'
          '在 realme / ColorOS 上，常见入口是“应用信息 -> 流量使用情况 / 联网控制 / 电池优化”。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await openAppSystemSettings(context);
            },
            child: const Text('前往系统设置'),
          ),
        ],
      );
    },
  );
}
