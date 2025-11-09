import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class LegalImprintPage extends StatelessWidget {
  const LegalImprintPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(t.imprint_title), // Key kommt gleich ins L10n
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: DefaultTextStyle(
          style: theme.textTheme.bodyMedium!.copyWith(height: 1.5),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Impressum',
                style: theme.textTheme.titleLarge!.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              Text('**Herausgeber**', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('DFS-Diamon GmbH\nLändenstraße 1\nD - 93339 Riedenburg\n'),
              const Text('Telefon +49 (0) 9442 91 89-0\nTelefax +49 (0) 9442 91 89-37\nE-Mail info@dfs-diamon.de\n'),
              const SizedBox(height: 12),

              Text('**Registerdaten**', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Amtsgericht Regensburg HRB 2966\nUSt-ID-Nummer DE 128580122\n'),
              const Text('Verantwortlich für die Inhalte: Herr Dr. Stefan Brand\n'
                  'Vertretungsberechtigter: Herr Dr. Stefan Brand\n'),
              const SizedBox(height: 12),

              Text('**Haftungsausschluss**', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Wir bemühen uns, auf dieser Webseite richtige und vollständige Informationen '
                'zur Verfügung zu stellen, dennoch übernehmen wir keine Haftung oder Garantie '
                'für Aktualität, Richtigkeit und Vollständigkeit der auf dieser Webseite bereitgestellten '
                'Informationen. Dies gilt auch für alle weiterführenden Verbindungen (Links), auf die diese '
                'Webseite direkt oder indirekt verweist. Wir sind also für jegliche Inhalte von Webseiten, '
                'die mittels einer solchen Verbindung erreicht werden, nicht verantwortlich. Alle Angaben zu '
                'Preisen, Produkttexten, Produktbildern sind ohne Gewähr, Irrtümer und technische Änderungen vorbehalten.',
              ),
              const SizedBox(height: 12),

              Text('**Urheberrechte**', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Alle Rechte vorbehalten. Inhalt und Struktur der DFS-Diamon Website sind urheberrechtlich geschützt. '
                'Informationen oder Daten (Text-, Bild-, Grafik-, Ton-, Video- oder Animationsdateien) unserer Website dürfen '
                'ohne vorherige schriftliche Zustimmung der DFS-Diamon GmbH weder in irgendeiner Form verwendet noch '
                'reproduziert werden, auch nicht auszugsweise.',
              ),
              const SizedBox(height: 12),

              Text('**Alternative Streitbeilegung gemäß Art. 14 Abs. 1 ODR-VO und § 36 VSBG:**',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text(
                'Die Europäische Kommission stellt eine Plattform zur Online-Streitbeilegung (OS) bereit, '
                'die Sie unter https://webgate.ec.europa.eu/odr/main/index.cfm?event=main.home.show&lng=DE finden. '
                'Wir sind bereit, an einem außergerichtlichen Schlichtungsverfahren teilzunehmen.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
