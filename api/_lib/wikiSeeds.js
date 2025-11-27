// api/_lib/wikiSeeds.js
const defaultTimestamp = new Date('2024-01-01T00:00:00.000Z').toISOString();

export const wikiSeedCategories = [
  {
    id: 'cat_productgroups',
    name: 'Produktgruppen – Übersicht',
    description:
      'DE: Kurzüberblick über alle MDR-TD-Produktgruppen von DFS-DIAMON. / EN: Quick overview of all MDR-TD product groups. / ES: Resumen rápido de todos los grupos MDR-TD. / FR: Aperçu rapide des groupes MDR-TD. / IT: Panoramica rapida di tutti i gruppi MDR-TD.',
    icon: 'layers',
    sortOrder: 1,
    isActive: true,
  },
  {
    id: 'cat_errors',
    name: 'Typische Fehlerursachen',
    description:
      'DE: Häufige Ursachen für Reklamationen. / EN: Common root causes for complaints. / ES: Causas frecuentes de reclamaciones. / FR: Causes fréquentes des réclamations. / IT: Cause comuni dei reclami.',
    icon: 'alert-triangle',
    sortOrder: 2,
    isActive: true,
  },
  {
    id: 'cat_prevention',
    name: 'Reklamationsvermeidung',
    description:
      'DE: Tipps zur Vermeidung von Reklamationen. / EN: Tips to prevent complaints. / ES: Consejos para evitar reclamaciones. / FR: Conseils pour éviter les réclamations. / IT: Suggerimenti per evitare reclami.',
    icon: 'shield-check',
    sortOrder: 3,
    isActive: true,
  },
  {
    id: 'cat_application',
    name: 'Anwendung & Technik',
    description:
      'DE: Praxistipps zu Drehzahl, Druck und Kühlung. / EN: Practical tips on speed, pressure and cooling. / ES: Consejos prácticos sobre velocidad, presión y refrigeración. / FR: Conseils pratiques sur vitesse, pression et refroidissement. / IT: Suggerimenti pratici su velocità, pressione e raffreddamento.',
    icon: 'settings',
    sortOrder: 4,
    isActive: true,
  },
  {
    id: 'cat_safety',
    name: 'Sicherheit & Warnhinweise',
    description:
      'DE: Klinische und technische Sicherheitsthemen. / EN: Clinical and technical safety topics. / ES: Temas de seguridad clínica y técnica. / FR: Sujets de sécurité clinique et technique. / IT: Temi di sicurezza clinica e tecnica.',
    icon: 'alert-octagon',
    sortOrder: 5,
    isActive: true,
  },
  {
    id: 'cat_faq',
    name: 'Häufige Fragen (FAQ)',
    description:
      'DE: Standardantworten auf typische Kundenfragen. / EN: Standard answers for common customer questions. / ES: Respuestas estándar a preguntas frecuentes. / FR: Réponses standard aux questions fréquentes. / IT: Risposte standard alle domande frequenti.',
    icon: 'help-circle',
    sortOrder: 6,
    isActive: true,
  },
  {
    id: 'cat_material',
    name: 'Material & Haltbarkeit',
    description:
      'DE: Werkstoffe und Lebensdauer. / EN: Materials and durability. / ES: Materiales y durabilidad. / FR: Matériaux et durabilité. / IT: Materiali e durata.',
    icon: 'package',
    sortOrder: 7,
    isActive: true,
  },
  {
    id: 'cat_reprocessing',
    name: 'Aufbereitung & Reinigung',
    description:
      'DE: Reinigung, Desinfektion und Sterilisation. / EN: Cleaning, disinfection and sterilization. / ES: Limpieza, desinfección y esterilización. / FR: Nettoyage, désinfection et stérilisation. / IT: Pulizia, disinfezione e sterilizzazione.',
    icon: 'refresh-cw',
    sortOrder: 8,
    isActive: true,
  },
];

export const wikiSeedArticles = [
  {
    id: 'art_mdr_td1_overview',
    categoryId: 'cat_productgroups',
    productGroups: [
      'MDR-TD1 - rot. Dentalinstrumente (Diamantinstrumente & Hartmetallinstrumente)',
    ],
    type: 'faq',
    title: 'Was gehört zur Produktgruppe MDR-TD1 – rotierende Diamant- und Hartmetallinstrumente?',
    teaser:
      'DE/EN/ES/FR/IT: Kurzüberblick über Indikationen, Eigenschaften und Anwendungen der DFS-Diamant- und Hartmetallinstrumente.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\nMDR-TD1 umfasst klassische rotierende Schleif- und Präparationsinstrumente (Diamant & Hartmetall) für Präparation, Füllungsentfernung, Kronen-/Brückenbearbeitung und Korrekturen. Vorteile: hohe Schneidleistung, gute Oberflächen, große Formvielfalt. Anwendung: richtige Drehzahl, korrekte Spannlänge, ausreichende Wasserkühlung, bei Verschleiß austauschen.\n\n## English\nMDR-TD1 covers rotary diamond and carbide instruments for preparation, removal of fillings, crown/bridge work, and adjustments. Benefits: strong cutting performance, clean surfaces, wide range of shapes. Use with correct speed, proper chuck length, adequate water cooling, and replace when worn.\n\n## Español\nMDR-TD1 incluye instrumentos rotatorios de diamante y carburo para preparación, eliminación de obturaciones, trabajos de coronas/puentes y ajustes. Ventajas: alto poder de corte, superficies limpias, gran variedad de formas. Usar con la velocidad correcta, longitud de sujeción adecuada, refrigeración con agua y sustituir si hay desgaste.\n\n## Français\nMDR-TD1 regroupe les instruments rotatifs diamantés et carbure pour la préparation, le retrait de restaurations, le travail sur couronnes/ponts et les retouches. Atouts : performance de coupe élevée, surface propre, large choix de formes. Utiliser à la bonne vitesse, longueur de serrage correcte, avec refroidissement par eau et remplacer en cas d’usure.\n\n## Italiano\nMDR-TD1 comprende strumenti rotanti diamantati e in carburo per preparazione, rimozione di otturazioni, lavorazione di corone/ponte e rifiniture. Vantaggi: elevata capacità di taglio, superfici pulite, ampia gamma di forme. Usare alla velocità corretta, con lunghezza di serraggio adeguata, raffreddamento ad acqua e sostituire quando usurati.\n\n**Vertreter-Tipp / Rep tip**: Drei Kernpunkte betonen / highlight three essentials: Drehzahl-Speed, Spannlänge-Chuck length, Kühlung-Cooling.`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
  {
    id: 'art_mdr_td2_overview',
    categoryId: 'cat_productgroups',
    productGroups: ['MDR-TD2 - Knochenfräser (Stahl- und Hartmetallknochenfräser)'],
    type: 'faq',
    title: 'MDR-TD2 – Knochenfräser: Einsatzbereiche und Besonderheiten',
    teaser:
      'DE/EN/ES/FR/IT: Kompakte Erklärung zu Indikationen, Varianten (Stahl/Hartmetall) und Anwendungshinweisen bei Knochenfräsern.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\nIndikationen: Osteotomie, Freilegung retinierter Zähne, Sinuslift, Knochenkonturierung. Varianten: Stahl (zäher, verzeihender), Hartmetall (max. Schneidleistung, sensibler gegen Biegung). Anwendung: chirurgisch invasiv – validierte Aufbereitung und Dokumentation, sichere Kühlung, intakte Instrumente verwenden.\n\n## English\nIndications: osteotomy, exposure of impacted teeth, sinus lift, bone contouring. Variants: steel (tough, forgiving), carbide (high cutting power, more sensitive to bending). Use: surgical application – validated reprocessing and documentation, reliable cooling, only intact instruments.\n\n## Español\nIndicaciones: osteotomía, exposición de dientes retenidos, elevación de seno, contorneado óseo. Variantes: acero (más tenaz), carburo (máxima capacidad de corte, más sensible a flexión). Uso: aplicación quirúrgica – reprocesado validado y documentación, buena refrigeración, solo instrumentos íntegros.\n\n## Français\nIndications : ostéotomie, exposition de dents incluses, sinus lift, modelage osseux. Variantes : acier (plus ductile), carbure (très puissant, plus sensible à la flexion). Utilisation : acte chirurgical – retraitement validé et documentation, refroidissement efficace, utiliser uniquement des instruments intacts.\n\n## Italiano\nIndicazioni: osteotomia, esposizione di denti ritenuti, sinus lift, modellazione ossea. Varianti: acciaio (più tenace), carburo (massima capacità di taglio, più sensibile alla flessione). Uso: procedura chirurgica – ricondizionamento validato e documentazione, raffreddamento sicuro, usare solo strumenti integri.\n\n**Vertreter-Hinweis / Rep note**: Stahl = toleranter, Hartmetall = Leistung; immer auf sichere Aufbereitung hinweisen.`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
  {
    id: 'art_material_hartmetall_vs_stahl',
    categoryId: 'cat_material',
    productGroups: [
      'MDR-TD1 - rot. Dentalinstrumente (Diamantinstrumente & Hartmetallinstrumente)',
      'MDR-TD2 - Knochenfräser (Stahl- und Hartmetallknochenfräser)',
    ],
    type: 'faq',
    title: 'Unterschied Hartmetall vs. Stahl – Biege- und Bruchverhalten',
    teaser:
      'DE/EN/ES/FR/IT: Hartmetall sehr hart, aber spröder; Stahl zäher und biegebelastbarer – so erklärt man Reklamationen.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\nHartmetall: extrem hart, verschleißfest, kaum plastisch verformbar. Sturz → Mikrorisse → später spröder Bruch. Stahl: höhere Zähigkeit und Biegefestigkeit, verzeiht leichte Verformung, etwas geringere Schneidleistung. Vertreter-Tipp: Nach Sturz oder sichtbarem Schaden Hartmetall sicherheitshalber ersetzen.\n\n## English\nCarbide: extremely hard and wear resistant, almost no plastic deformation. Drop → microcracks → brittle fracture later. Steel: tougher and more flexible, tolerates slight bending, somewhat lower cutting power. Rep tip: replace carbide tools after drops or visible damage.\n\n## Español\nCarburo: muy duro y resistente al desgaste, casi sin deformación plástica. Caídas → microfisuras → rotura frágil posterior. Acero: mayor tenacidad y flexión, tolera ligera deformación, menor poder de corte. Consejo: sustituir instrumentos de carburo tras caídas o daños visibles.\n\n## Français\nCarbure : très dur et résistant à l’usure, quasi aucune déformation plastique. Chute → microfissures → rupture fragile. Acier : plus tenace et flexible, tolère une légère flexion, puissance de coupe un peu moindre. Conseil : remplacer les instruments en carbure après une chute ou tout dommage visible.\n\n## Italiano\nCarburo: estremamente duro e resistente all’usura, quasi nessuna deformazione plastica. Caduta → microfratture → rottura fragile. Acciaio: più tenace e flessibile, tollera lieve piega, potere di taglio leggermente inferiore. Suggerimento: sostituire gli strumenti in carburo dopo cadute o danni visibili.`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
  {
    id: 'art_errors_hartmetall_bruch',
    categoryId: 'cat_errors',
    productGroups: [
      'MDR-TD1 - rot. Dentalinstrumente (Diamantinstrumente & Hartmetallinstrumente)',
      'MDR-TD2 - Knochenfräser (Stahl- und Hartmetallknochenfräser)',
    ],
    type: 'error',
    title: 'Typische Fehlerursachen für Brüche bei Hartmetallinstrumenten',
    teaser: 'DE/EN/ES/FR/IT: Häufige Ursachen und Checkliste für Rückfragen beim Kunden.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\nUrsachen: Sturz/Mikrorisse, falsche Spannlänge, Verkanten/Biegebelastung, zu hohe Drehzahl, verschlissene Instrumente, aggressive Aufbereitung. Check: Sturz? Spannlänge? Drehzahl/Druck? Aufbereitungshistorie? Sichtbarer Verschleiß/Korrosion? Hinweis: Einzelbruch ≠ Serienfehler.\n\n## English\nCauses: drops/microcracks, wrong chuck length, jamming/bending load, overspeed, worn tools, aggressive reprocessing. Check: dropped? correct chuck length? speed/pressure used? reprocessing history? visible wear/corrosion? Note: one break is not automatically a batch defect.\n\n## Español\nCausas: caídas/microfisuras, longitud de sujeción incorrecta, atascos/flexión, exceso de velocidad, desgaste, reprocesado agresivo. Comprobar: se cayó? longitud correcta? velocidad/presión? historial de reprocesado? desgaste/corrosión visible? Nota: una rotura aislada no implica defecto de serie.\n\n## Français\nCauses : chutes/microfissures, mauvaise longueur de serrage, coincement/flexion, vitesse excessive, usure, retraitement agressif. À vérifier : chute ? bonne longueur ? vitesse/pression ? historique de retraitement ? usure/corrosion visible ? Remarque : une casse isolée n’est pas forcément un défaut de lot.\n\n## Italiano\nCause: cadute/microfratture, lunghezza di serraggio errata, impuntamento/flessione, velocità eccessiva, usura, ricondizionamento aggressivo. Verifiche: caduto? lunghezza corretta? velocità/pressione? storia di ricondizionamento? usura/corrosione visibile? Nota: una rottura isolata non è automaticamente un difetto di lotto.`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
  {
    id: 'art_prevention_td1',
    categoryId: 'cat_prevention',
    productGroups: [
      'MDR-TD1 - rot. Dentalinstrumente (Diamantinstrumente & Hartmetallinstrumente)',
    ],
    type: 'prevention',
    title: 'Reklamationsvermeidung bei MDR-TD1 – richtige Anwendung von Diamant- und Hartmetallinstrumenten',
    teaser:
      'DE/EN/ES/FR/IT: Kurzleitfaden zu Kühlung, Drehzahl, Druck und Austauschintervallen für MDR-TD1.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\n- Immer ausreichende Wasserkühlung nutzen\n- Leichten Anpressdruck, Instrument schneiden lassen\n- Drehzahl gemäß Herstellerangabe konstant halten\n- Verschlissene oder beschädigte Instrumente frühzeitig austauschen\n\n## English\n- Always use sufficient water cooling\n- Apply light pressure; let the tool cut\n- Keep speed per manufacturer specification\n- Replace worn or damaged tools early\n\n## Español\n- Usar siempre refrigeración con agua suficiente\n- Presión ligera, dejar que la fresa corte\n- Mantener la velocidad indicada por el fabricante\n- Sustituir a tiempo instrumentos desgastados o dañados\n\n## Français\n- Toujours utiliser un refroidissement à l’eau suffisant\n- Pression légère, laisser l’instrument travailler\n- Vitesse conforme aux indications fabricant\n- Remplacer tôt les instruments usés ou endommagés\n\n## Italiano\n- Usare sempre adeguato raffreddamento ad acqua\n- Pressione leggera, lasciare che lo strumento tagli\n- Mantenere la velocità indicata dal produttore\n- Sostituire precocemente strumenti usurati o danneggiati\n\n**Erklärhilfe / How to explain**: "Kühlung, wenig Druck, richtige Drehzahl – dann halten die Instrumente länger und liefern bessere Oberflächen."`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
  {
    id: 'art_mdr_td3_polishers',
    categoryId: 'cat_productgroups',
    productGroups: [
      'MDR-TD3 - Dentalpolierer (Festkörperpolierer (Gummi), Uporal (Bürstenpolierer), Diafix-Oral (Filzpolierer))',
    ],
    type: 'faq',
    title: 'MDR-TD3 – Dentalpolierer: Festkörperpolierer, Uporal und Diafix-Oral',
    teaser:
      'DE/EN/ES/FR/IT: Überblick über Polierer-Typen, typische Einsatzbereiche und Anwendungshinweise.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\n- Festkörperpolierer (Gummi): Vor- und Hochglanzpolitur an Komposit/Keramik\n- Uporal (Bürstenpolierer): sanfte Anpassung und Politur, auch an sensiblen Flächen\n- Diafix-Oral (Filzpolierer): Hochglanzfinish für Metall/Keramik\nHinweise: empfohlene Drehzahl einhalten, moderater Druck, falls vorgesehen nicht trocken fahren; Einmal-/Mehrfachgebrauch je Produkt beachten.\n\n## English\n- Solid rubber polishers: pre- and high-gloss polish on composite/ceramic\n- Uporal brush polishers: gentle adjustment and polishing, including delicate areas\n- Diafix-Oral felt polishers: high-gloss finish for metal/ceramic\nNotes: use recommended speed, moderate pressure, avoid dry use if cooling required; check single- vs. multi-use.\n\n## Español\n- Pulidores de goma: pre y alto brillo en composite/cerámica\n- Pulidores de cepillo Uporal: ajuste y pulido suaves, incluso en zonas delicadas\n- Pulidores de fieltro Diafix-Oral: acabado de alto brillo para metal/cerámica\nNotas: respetar velocidad recomendada, presión moderada, evitar uso en seco si se requiere refrigeración; comprobar si son de un solo uso o reutilizables.\n\n## Français\n- Polissoirs en caoutchouc: pré- et haute brillance sur composite/céramique\n- Polissoirs brosse Uporal: ajustement doux, même sur zones sensibles\n- Polissoirs feutre Diafix-Oral: finition haute brillance métal/céramique\nNotes : respecter la vitesse recommandée, pression modérée, pas d’utilisation à sec si refroidissement requis ; vérifier usage unique/réutilisable.\n\n## Italiano\n- Lucidatori in gomma: pre e alta lucentezza su composito/ceramica\n- Lucidatori a spazzola Uporal: regolazione e lucidatura delicata, anche su superfici sensibili\n- Lucidatori in feltro Diafix-Oral: finitura a specchio per metallo/ceramica\nNote: rispettare la velocità consigliata, pressione moderata, evitare uso a secco se serve raffreddamento; controllare monouso o riutilizzo.`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
  {
    id: 'art_mdr_td4_precicut',
    categoryId: 'cat_productgroups',
    productGroups: ['MDR-TD4 - PreciCut'],
    type: 'faq',
    title: 'MDR-TD4 – PreciCut: Weichgewebeschneider und besondere Eigenschaften',
    teaser: 'DE/EN/ES/FR/IT: Indikation, Handhabung und Sicherheitshinweise für PreciCut.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\nEinsatz: präzise Schnitte im Weichgewebe (z. B. Gingiva). Handhabung: Drehzahl nach Hersteller, schonende Schnittführung, sicherer Sitz im Handstück. Sicherheit: atraumatisch arbeiten, beschädigte Instrumente sofort aussondern.\n\n## English\nUse: precise soft-tissue cutting (e.g., gingiva). Handling: use manufacturer speed, gentle cutting motion, ensure secure chucking. Safety: work atraumatically, discard damaged instruments immediately.\n\n## Español\nUso: cortes precisos en tejido blando (p. ej., encía). Manejo: velocidad según fabricante, corte suave, fijación segura en la pieza de mano. Seguridad: trabajar de forma atraumática, descartar instrumentos dañados.\n\n## Français\nUsage : coupes précises des tissus mous (p. ex. gencive). Manipulation : vitesse selon fabricant, geste doux, serrage sûr dans la pièce à main. Sécurité : travail atraumatique, écarter immédiatement tout instrument endommagé.\n\n## Italiano\nUso: tagli precisi nel tessuto molle (es. gengiva). Gestione: velocità secondo il produttore, movimento di taglio delicato, serraggio sicuro nel manipolo. Sicurezza: lavorare in modo atraumatico, scartare subito gli strumenti danneggiati.`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
  {
    id: 'art_mdr_td5_alloy',
    categoryId: 'cat_material',
    productGroups: ['MDR-TD5 - Dentallegierungen (Diadur CoCr-Legierung)'],
    type: 'faq',
    title: 'MDR-TD5 – Dentallegierungen: Diadur CoCr-Legierung im Überblick',
    teaser:
      'DE/EN/ES/FR/IT: Werkstoff-Steckbrief zur Diadur CoCr-Legierung, Einsatzgebiete und Nutzen für Kunden.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\nWerkstoff: Diadur CoCr-Legierung für Kronen, Brücken und Gerüste. Eigenschaften: hohe Festigkeit, Biokompatibilität, Korrosionsbeständigkeit. Nutzen: schlanke, stabile Konstruktionen.\n\n## English\nMaterial: Diadur CoCr alloy for crowns, bridges, frameworks. Properties: high strength, biocompatibility, corrosion resistance. Benefit: slim yet stable constructions.\n\n## Español\nMaterial: aleación Diadur CoCr para coronas, puentes y estructuras. Propiedades: alta resistencia, biocompatibilidad, resistencia a la corrosión. Beneficio: estructuras finas y estables.\n\n## Français\nMatériau : alliage Diadur CoCr pour couronnes, ponts et armatures. Propriétés : haute résistance, biocompatibilité, résistance à la corrosion. Avantage : constructions fines et stables.\n\n## Italiano\nMateriale: lega Diadur CoCr per corone, ponti e strutture. Proprietà: elevata resistenza, biocompatibilità, resistenza alla corrosione. Vantaggio: strutture sottili ma stabili.\n\n**Kurzfassung für Vertreter / Rep short pitch**: "CoCr liefert Stabilität und Biokompatibilität für langlebige Restaurationen."`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
  {
    id: 'art_faq_lifespan',
    categoryId: 'cat_faq',
    productGroups: [
      'MDR-TD1 - rot. Dentalinstrumente (Diamantinstrumente & Hartmetallinstrumente)',
      'MDR-TD2 - Knochenfräser (Stahl- und Hartmetallknochenfräser)',
      'MDR-TD3 - Dentalpolierer (Festkörperpolierer (Gummi), Uporal (Bürstenpolierer), Diafix-Oral (Filzpolierer))',
    ],
    type: 'faq',
    title: 'FAQ – Wie lange dürfen DFS-Instrumente verwendet werden?',
    teaser:
      'DE/EN/ES/FR/IT: Standardantwort zur Einsatzdauer – abhängig von Belastung, Aufbereitung und Material.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\nLebensdauer hängt von Belastung, Aufbereitung, Material und Indikation ab. Vor jedem Einsatz Sichtkontrolle; bei Rissen, Verformung oder Leistungsverlust sofort ersetzen. Gebrauchsanweisung enthält zulässige Zyklen. Dokumentation der Aufbereitungen hilft.\n\n## English\nLifetime depends on load, reprocessing, material and indication. Visual check before use; replace immediately if cracks, deformation or performance loss. Instructions for use list allowed cycles. Document reprocessing.\n\n## Español\nLa vida útil depende de carga, reprocesado, material e indicación. Revisar antes de usar; sustituir si hay grietas, deformación o pérdida de rendimiento. El IFU indica ciclos permitidos. Documentar los reprocesados.\n\n## Français\nLa durée de vie dépend de la charge, du retraitement, du matériau et de l’indication. Vérifier avant usage ; remplacer en cas de fissure, déformation ou perte d’efficacité. La notice indique les cycles autorisés. Documenter les retraitements.\n\n## Italiano\nLa durata dipende da carico, ricondizionamento, materiale e indicazione. Controllo visivo prima dell’uso; sostituire in caso di crepe, deformazioni o perdita di prestazioni. Le istruzioni indicano i cicli ammessi. Documentare i ricondizionamenti.\n\n**Vertreter-Hinweis / Rep note**: Immer auf die jeweilige Gebrauchsanweisung verweisen, falls konkrete Zykluszahlen gefragt sind.`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
  {
    id: 'art_reprocessing',
    categoryId: 'cat_reprocessing',
    productGroups: [
      'MDR-TD1 - rot. Dentalinstrumente (Diamantinstrumente & Hartmetallinstrumente)',
      'MDR-TD2 - Knochenfräser (Stahl- und Hartmetallknochenfräser)',
      'MDR-TD3 - Dentalpolierer (Festkörperpolierer (Gummi), Uporal (Bürstenpolierer), Diafix-Oral (Filzpolierer))',
      'MDR-TD4 - PreciCut',
    ],
    type: 'prevention',
    title: 'Aufbereitung von DFS-Instrumenten – was Vertreter sagen sollten',
    teaser:
      'DE/EN/ES/FR/IT: Kurzleitfaden zur Kommunikation von Reinigung, Desinfektion und Sterilisation.',
    importance: 'normal',
    contentMarkdown: `## Deutsch\nKernbotschaft: sofortige Vorreinigung, validierte maschinelle Reinigung/Desinfektion, Sterilisation nach Herstellerangaben (Zyklus, Verpackung, Beladung). Kommunikation: "Gebrauchsanweisung ist maßgeblich"; bei komplexen Fragen QM/Regulatory einbinden; nach jedem Zyklus auf Beschädigungen prüfen.\n\n## English\nKey message: immediate pre-cleaning, validated machine cleaning/disinfection, sterilization per manufacturer specs (cycle, packaging, load). Communication: "IFU is binding"; involve QA/RA for complex questions; check for damage after each cycle.\n\n## Español\nMensaje clave: prelavado inmediato, limpieza/desinfección mecánica validada, esterilización según especificaciones del fabricante (ciclo, embalaje, carga). Comunicación: "Las IFU son vinculantes"; implicar QA/RA para dudas complejas; revisar daños tras cada ciclo.\n\n## Français\nMessage clé : pré-nettoyage immédiat, nettoyage/désinfection machine validés, stérilisation selon les indications fabricant (cycle, emballage, charge). Communication : « La notice fait foi » ; impliquer AQ/RA pour questions complexes ; contrôler les dommages après chaque cycle.\n\n## Italiano\nMessaggio chiave: prelavaggio immediato, pulizia/disinfezione meccanica validata, sterilizzazione secondo le specifiche del produttore (ciclo, confezione, carico). Comunicazione: "Le IFU sono vincolanti"; coinvolgere QA/RA per domande complesse; controllare danni dopo ogni ciclo.\n\n**Vertreter-Kurztext / Rep short script**: "Direkt vorreinigen, validiert aufbereiten, steril nach Hersteller – Details stehen in der Gebrauchsanweisung."`,
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
];
