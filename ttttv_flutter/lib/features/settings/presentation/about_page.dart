import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/platform/platform_window.dart';

const _githubRepositoryUrl = 'https://github.com/WEP-56/TTTTV-Flutter';

class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<void> _openGitHub(BuildContext context) async {
    final uri = Uri.parse(_githubRepositoryUrl);
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法打开浏览器，请稍后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const PlatformDragToMoveArea(
          child: SizedBox(
            width: double.infinity,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('关于 TTTTV'),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Card(
            elevation: 0,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TTTTV',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '一个面向桌面端的影视、直播搜索与观看项目，当前版本聚焦 Windows 使用体验。',
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => _openGitHub(context),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: const Text('打开 GitHub 仓库'),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _githubRepositoryUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const _AboutSection(
            title: '项目说明',
            children: [
              '本项目用于聚合公开可访问的影视与直播信息，提供搜索、管理与观看能力。',
              '项目本身不内置影视内容，也不声明对第三方站点、直播平台或片源服务拥有任何权利。',
            ],
          ),
          const SizedBox(height: 16),
          const _AboutSection(
            title: '免责声明',
            children: [
              '请仅在遵守当地法律法规及相关平台服务条款的前提下使用本项目。',
              '用户应自行判断片源、直播链接与第三方服务的合法性、安全性与可用性，并自行承担使用风险。',
              '如果任何第三方内容涉及侵权、失效、下架或访问限制，本项目不提供担保，也不承担由此产生的直接或间接责任。',
            ],
          ),
          const SizedBox(height: 16),
          _AboutSection(
            title: 'License',
            children: const [
              'TTTTV-Flutter 使用仓库中声明的开源许可证发布。',
              '应用依赖的第三方 Flutter / Dart / Native 库分别遵循其各自许可证条款。',
            ],
            footer: Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'TTTTV',
                ),
                icon: const Icon(Icons.article_outlined),
                label: const Text('查看开源许可证'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection({
    required this.title,
    required this.children,
    this.footer,
  });

  final String title;
  final List<String> children;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            for (final item in children) ...[
              Text(
                item,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.65),
              ),
              const SizedBox(height: 10),
            ],
            if (footer != null) footer!,
          ],
        ),
      ),
    );
  }
}
