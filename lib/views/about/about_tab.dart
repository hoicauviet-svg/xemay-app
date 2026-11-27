import 'package:flutter/material.dart';
import '../../controllers/app_update_controller.dart';
import '../../services/external_link_opener.dart';
import '../settings/app_update_panel.dart';
import '../widgets/form_section.dart';

const _brandGreen = Color(0xFF176455);
const websiteUrl = 'https://hoicau.net/';
const collectionUrl = 'https://hoicau.net/games';
const supportUrl = 'https://hoicau.net/support';

class AboutTab extends StatelessWidget {
  const AboutTab({super.key, this.updateController, this.openLink});
  final AppUpdateController? updateController;
  final Future<void> Function(String url)? openLink;

  @override
  Widget build(BuildContext context) => AppUpdatePanel(
    controller: updateController,
    intro: _AboutIntro(onOpenLink: openLink),
    title: 'Phiên bản & cập nhật',
  );
}

class _AboutIntro extends StatelessWidget {
  const _AboutIntro({this.onOpenLink});
  final Future<void> Function(String url)? onOpenLink;

  @override
  Widget build(BuildContext context) => FormSection(
    title: 'Giới thiệu',
    children: [
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Image.asset(
            'assets/images/SplashLogo.png',
            key: const ValueKey('about-logo'),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, _, _) =>
                const Icon(Icons.storefront, size: 72, color: _brandGreen),
          ),
        ),
      ),
      const SizedBox(height: 20),
      const Divider(height: 1, color: Color(0xFFE5EAED)),
      const SizedBox(height: 12),
      _AboutLink(
        key: const ValueKey('about-website-link'),
        icon: Icons.language,
        label: 'Website',
        url: websiteUrl,
        onOpenLink: onOpenLink,
      ),
      const SizedBox(height: 8),
      _AboutLink(
        key: const ValueKey('about-collection-link'),
        icon: Icons.sports_esports_outlined,
        label: 'Bộ sưu tập',
        url: collectionUrl,
        onOpenLink: onOpenLink,
      ),
      const SizedBox(height: 8),
      _AboutLink(
        key: const ValueKey('about-support-link'),
        icon: Icons.support_agent_outlined,
        label: 'Hỗ trợ',
        url: supportUrl,
        onOpenLink: onOpenLink,
      ),
    ],
  );
}

class _AboutLink extends StatelessWidget {
  const _AboutLink({
    super.key,
    required this.icon,
    required this.label,
    required this.url,
    this.onOpenLink,
  });
  final IconData icon;
  final String label, url;
  final Future<void> Function(String url)? onOpenLink;

  Future<void> _open(BuildContext context) async {
    try {
      await (onOpenLink ?? openExternalLink)(url);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(const SnackBar(content: Text('Không mở được liên kết.')));
    }
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: _brandGreen),
      const SizedBox(width: 8),
      SizedBox(
        width: 78,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, height: 1.5),
        ),
      ),
      Expanded(
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: InkWell(
            onTap: () => _open(context),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                url,
                style: const TextStyle(
                  color: _brandGreen,
                  height: 1.5,
                  decoration: TextDecoration.underline,
                  decorationColor: _brandGreen,
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
