import 'package:flutter/material.dart';

import '../../application/dlna_controller.dart';

class CastDeviceDialog extends StatefulWidget {
  const CastDeviceDialog({required this.controller, super.key});
  final DlnaController controller;

  @override
  State<CastDeviceDialog> createState() => _CastDeviceDialogState();
}

class _CastDeviceDialogState extends State<CastDeviceDialog> {
  late Future<List<DlnaDevice>> _devices = widget.controller.discover();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('投屏到电视'),
        content: SizedBox(
            width: 420,
            child: FutureBuilder<List<DlnaDevice>>(
                future: _devices,
                builder: (context, snapshot) {
                  final loading =
                      snapshot.connectionState != ConnectionState.done;
                  return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('请将电视和本机连接同一局域网，并在电视上开启 DLNA 投屏。'),
                        const SizedBox(height: 16),
                        if (loading) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                          const Text('正在搜索设备…'),
                        ] else if (snapshot.hasError)
                          Text('搜索失败：${snapshot.error}')
                        else if (snapshot.data?.isEmpty != false)
                          const Text('未发现设备，可检查网络后重新搜索。')
                        else
                          Flexible(
                              child: ListView(shrinkWrap: true, children: [
                            for (final device in snapshot.data!)
                              ListTile(
                                leading: const Icon(Icons.tv_rounded),
                                title: Text(
                                    device.name.isEmpty ? '电视' : device.name),
                                subtitle: Text(device.controlUrl.host),
                                onTap: () => Navigator.of(context).pop(device),
                              ),
                          ])),
                        if (!loading)
                          TextButton.icon(
                              onPressed: () => setState(() {
                                    _devices = widget.controller.discover();
                                  }),
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('重新搜索')),
                      ]);
                })),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'))
        ],
      );
}
