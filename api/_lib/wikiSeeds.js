// api/_lib/wikiSeeds.js
const defaultTimestamp = new Date('2024-01-01T00:00:00.000Z').toISOString();

export const wikiSeedCategories = [
  {
    id: 'cat_productgroups',
    name: 'Produktgruppen – Übersicht',
    nameIntl: {
      en: 'Product groups – overview',
      es: 'Grupos de productos – resumen',
      fr: 'Groupes de produits – aperçu',
      it: 'Gruppi di prodotti – panoramica',
    },
    description: 'Kurzüberblick über alle MDR-TD-Produktgruppen von DFS-DIAMON.',
    descriptionIntl: {
      en: 'Quick overview of all MDR-TD product groups.',
      es: 'Resumen rápido de todos los grupos MDR-TD.',
      fr: 'Aperçu rapide des groupes MDR-TD.',
      it: 'Panoramica rapida di tutti i gruppi MDR-TD.',
    },
    icon: 'layers',
    sortOrder: 1,
    isActive: true,
  },
  {
    id: 'cat_errors',
    name: 'Typische Fehlerursachen',
    nameIntl: {
      en: 'Common root causes',
      es: 'Causas típicas de errores',
      fr: 'Causes d’erreurs typiques',
      it: 'Cause tipiche di errore',
    },
    description: 'Häufige Ursachen für Reklamationen.',
    descriptionIntl: {
      en: 'Common root causes for complaints.',
      es: 'Causas frecuentes de reclamaciones.',
      fr: 'Causes fréquentes des réclamations.',
      it: 'Cause comuni dei reclami.',
    },
    icon: 'alert-triangle',
    sortOrder: 2,
    isActive: true,
  },
  {
    id: 'cat_prevention',
    name: 'Reklamationsvermeidung',
    nameIntl: {
      en: 'Complaint prevention',
      es: 'Prevención de reclamaciones',
      fr: 'Prévention des réclamations',
      it: 'Prevenzione dei reclami',
    },
    description: 'Tipps zur Vermeidung von Reklamationen.',
    descriptionIntl: {
      en: 'Tips to prevent complaints.',
      es: 'Consejos para evitar reclamaciones.',
      fr: 'Conseils pour éviter les réclamations.',
      it: 'Suggerimenti per evitare reclami.',
    },
    icon: 'shield-check',
    sortOrder: 3,
    isActive: true,
  },
  {
    id: 'cat_application',
    name: 'Anwendung & Technik',
    nameIntl: {
      en: 'Application & technique',
      es: 'Aplicación y técnica',
      fr: 'Application & technique',
      it: 'Applicazione e tecnica',
    },
    description: 'Praxistipps zu Drehzahl, Druck und Kühlung.',
    descriptionIntl: {
      en: 'Practical tips on speed, pressure and cooling.',
      es: 'Consejos prácticos sobre velocidad, presión y refrigeración.',
      fr: 'Conseils pratiques sur vitesse, pression et refroidissement.',
      it: 'Suggerimenti pratici su velocità, pressione e raffreddamento.',
    },
    icon: 'settings',
    sortOrder: 4,
    isActive: true,
  },
  {
    id: 'cat_safety',
    name: 'Sicherheit & Warnhinweise',
    nameIntl: {
      en: 'Safety & warnings',
      es: 'Seguridad y advertencias',
      fr: 'Sécurité & avertissements',
      it: 'Sicurezza e avvertenze',
    },
    description: 'Klinische und technische Sicherheitsthemen.',
    descriptionIntl: {
      en: 'Clinical and technical safety topics.',
      es: 'Temas de seguridad clínica y técnica.',
      fr: 'Sujets de sécurité clinique et technique.',
      it: 'Temi di sicurezza clinica e tecnica.',
    },
    icon: 'alert-octagon',
    sortOrder: 5,
    isActive: true,
  },
  {
    id: 'cat_faq',
    name: 'Häufige Fragen (FAQ)',
    nameIntl: {
      en: 'Frequently asked questions (FAQ)',
      es: 'Preguntas frecuentes (FAQ)',
      fr: 'Questions fréquentes (FAQ)',
      it: 'Domande frequenti (FAQ)',
    },
    description: 'Standardantworten auf typische Kundenfragen.',
    descriptionIntl: {
      en: 'Standard answers for common customer questions.',
      es: 'Respuestas estándar a preguntas frecuentes.',
      fr: 'Réponses standard aux questions fréquentes.',
      it: 'Risposte standard alle domande frequenti.',
    },
    icon: 'help-circle',
    sortOrder: 6,
    isActive: true,
  },
  {
    id: 'cat_material',
    name: 'Material & Haltbarkeit',
    nameIntl: {
      en: 'Material & durability',
      es: 'Material y durabilidad',
      fr: 'Matériaux & durabilité',
      it: 'Materiali e durata',
    },
    description: 'Werkstoffe und Lebensdauer.',
    descriptionIntl: {
      en: 'Materials and durability.',
      es: 'Materiales y durabilidad.',
      fr: 'Matériaux et durabilité.',
      it: 'Materiali e durata.',
    },
    icon: 'package',
    sortOrder: 7,
    isActive: true,
  },
  {
    id: 'cat_reprocessing',
    name: 'Aufbereitung & Reinigung',
    nameIntl: {
      en: 'Reprocessing & cleaning',
      es: 'Reproceso y limpieza',
      fr: 'Retraitement & nettoyage',
      it: 'Ricondizionamento e pulizia',
    },
    description: 'Reinigung, Desinfektion und Sterilisation.',
    descriptionIntl: {
      en: 'Cleaning, disinfection and sterilization.',
      es: 'Limpieza, desinfección y esterilización.',
      fr: 'Nettoyage, désinfection et stérilisation.',
      it: 'Pulizia, disinfezione e sterilizzazione.',
    },
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
    titleIntl: {
      en: 'What belongs to MDR-TD1 – rotary diamond and carbide instruments?',
      es: '¿Qué incluye MDR-TD1 – instrumentos rotatorios de diamante y carburo?',
      fr: 'Que comprend le groupe MDR-TD1 – instruments rotatifs diamantés et carbure ?',
      it: 'Cosa comprende MDR-TD1 – strumenti rotanti diamantati e in carburo?',
    },
    teaser:
      'Kurzüberblick über Indikationen, Eigenschaften und Anwendungen der DFS-Diamant- und Hartmetallinstrumente.',
    teaserIntl: {
      en: 'Quick overview of indications, properties and uses of DFS diamond and carbide instruments.',
      es: 'Resumen breve de indicaciones, propiedades y usos de los instrumentos DFS de diamante y carburo.',
      fr: 'Aperçu des indications, propriétés et usages des instruments DFS diamantés et carbure.',
      it: 'Breve panoramica di indicazioni, proprietà e impieghi degli strumenti DFS in diamante e carburo.',
    },
    importance: 'normal',
    contentMarkdown:
      'MDR-TD1 umfasst rotierende Schleif- und Präparationsinstrumente (Diamant & Hartmetall) für Präparation, Füllungsentfernung, Kronen-/Brückenbearbeitung und Korrekturen. Vorteile: hohe Schneidleistung, gute Oberflächen, große Formvielfalt. Anwendung: richtige Drehzahl, korrekte Spannlänge, ausreichende Wasserkühlung, bei Verschleiß austauschen. **Vertreter-Tipp:** Drei Kernpunkte betonen: Drehzahl, Spannlänge, Kühlung.',
    contentIntl: {
      en: 'MDR-TD1 covers rotary diamond and carbide instruments for preparation, removal of fillings, crown/bridge work, and adjustments. Benefits: strong cutting performance, clean surfaces, wide range of shapes. Use with correct speed, proper chuck length, adequate water cooling, and replace when worn. **Rep tip:** Highlight speed, chuck length, and cooling.',
      es: 'MDR-TD1 incluye instrumentos rotatorios de diamante y carburo para preparación, eliminación de obturaciones, trabajos de coronas/puentes y ajustes. Ventajas: alto poder de corte, superficies limpias, gran variedad de formas. Usar con velocidad correcta, longitud de sujeción adecuada, refrigeración con agua y sustituir si hay desgaste. **Consejo del representante:** Enfatizar velocidad, longitud de sujeción y refrigeración.',
      fr: 'MDR-TD1 regroupe les instruments rotatifs diamantés et carbure pour la préparation, le retrait de restaurations, le travail sur couronnes/ponts et les retouches. Atouts : performance de coupe élevée, surfaces propres, large choix de formes. Utiliser à la bonne vitesse, longueur de serrage correcte, avec refroidissement par eau et remplacer en cas d’usure. **Conseil représentant :** mettre en avant vitesse, longueur de serrage et refroidissement.',
      it: 'MDR-TD1 comprende strumenti rotanti diamantati e in carburo per preparazione, rimozione di otturazioni, lavorazione di corone/ponte e rifiniture. Vantaggi: elevata capacità di taglio, superfici pulite, ampia gamma di forme. Usare alla velocità corretta, con lunghezza di serraggio adeguata, raffreddamento ad acqua e sostituire quando usurati. **Suggerimento per i rappresentanti:** sottolineare velocità, lunghezza di serraggio e raffreddamento.',
    },
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
    titleIntl: {
      en: 'MDR-TD2 – Bone cutters: use cases and specifics',
      es: 'MDR-TD2 – Fresadores óseos: usos y particularidades',
      fr: 'MDR-TD2 – Fraises osseuses : usages et spécificités',
      it: 'MDR-TD2 – Frese ossee: impieghi e particolarità',
    },
    teaser:
      'Kompakte Erklärung zu Indikationen, Varianten (Stahl/Hartmetall) und Anwendungshinweisen bei Knochenfräsern.',
    teaserIntl: {
      en: 'Compact guide to indications, variants (steel/carbide) and handling tips for bone cutters.',
      es: 'Guía compacta sobre indicaciones, variantes (acero/carburo) y consejos de uso de las fresas óseas.',
      fr: 'Guide concis des indications, variantes (acier/carbure) et conseils d’usage des fraises osseuses.',
      it: 'Guida compatta su indicazioni, varianti (acciaio/carburo) e consigli d’uso per le frese ossee.',
    },
    importance: 'normal',
    contentMarkdown:
      'Indikationen: Osteotomie, Freilegung retinierter Zähne, Sinuslift, Knochenkonturierung. Varianten: Stahl (zäher, verzeihender), Hartmetall (max. Schneidleistung, sensibler gegen Biegung). Anwendung: chirurgisch invasiv – validierte Aufbereitung und Dokumentation, sichere Kühlung, nur intakte Instrumente verwenden. **Vertreter-Hinweis:** Stahl = toleranter, Hartmetall = Leistung; immer auf sichere Aufbereitung hinweisen.',
    contentIntl: {
      en: 'Indications: osteotomy, exposure of impacted teeth, sinus lift, bone contouring. Variants: steel (tough, forgiving), carbide (high cutting power, more sensitive to bending). Use: surgical application – validated reprocessing and documentation, reliable cooling, only intact instruments. **Rep note:** steel = more forgiving, carbide = performance; always stress validated reprocessing.',
      es: 'Indicaciones: osteotomía, exposición de dientes retenidos, elevación de seno, contorneado óseo. Variantes: acero (más tenaz), carburo (máxima capacidad de corte, más sensible a flexión). Uso: aplicación quirúrgica – reprocesado validado y documentación, buena refrigeración, solo instrumentos íntegros. **Nota del representante:** acero = más tolerante, carburo = rendimiento; siempre remarcar el reprocesado validado.',
      fr: 'Indications : ostéotomie, exposition de dents incluses, sinus lift, modelage osseux. Variantes : acier (plus ductile), carbure (très puissant, plus sensible à la flexion). Utilisation : acte chirurgical – retraitement validé et documentation, refroidissement efficace, utiliser uniquement des instruments intacts. **Note représentant :** acier = plus tolérant, carbure = performance ; insister sur le retraitement validé.',
      it: 'Indicazioni: osteotomia, esposizione di denti ritenuti, sinus lift, modellazione ossea. Varianti: acciaio (più tenace), carburo (massima capacità di taglio, più sensibile alla flessione). Uso: procedura chirurgica – ricondizionamento validato e documentazione, raffreddamento sicuro, usare solo strumenti integri. **Nota per i rappresentanti:** acciaio = più tollerante, carburo = prestazioni; sottolineare sempre il ricondizionamento validato.',
    },
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
    titleIntl: {
      en: 'Carbide vs. steel – bending and fracture behavior',
      es: 'Carburo vs. acero – comportamiento a flexión y rotura',
      fr: 'Carbure vs. acier – comportement en flexion et rupture',
      it: 'Carburo vs. acciaio – comportamento a flessione e rottura',
    },
    teaser:
      'Warum Hartmetall sehr hart, aber spröder ist, und Stahl zäher und biegebelastbarer bleibt.',
    teaserIntl: {
      en: 'Why carbide is extremely hard yet brittle, while steel is tougher and more bend-resistant.',
      es: 'Por qué el carburo es muy duro pero más frágil y el acero es más tenaz y flexible.',
      fr: 'Pourquoi le carbure est très dur mais plus cassant et l’acier plus tenace et flexible.',
      it: 'Perché il carburo è durissimo ma più fragile, mentre l’acciaio è più tenace e flessibile.',
    },
    importance: 'normal',
    contentMarkdown:
      'Hartmetall: extrem hart, verschleißfest, kaum plastisch verformbar. Sturz → Mikrorisse → später spröder Bruch. Stahl: höhere Zähigkeit und Biegefestigkeit, verzeiht leichte Verformung, etwas geringere Schneidleistung. Vertreter-Tipp: Nach Sturz oder sichtbarem Schaden Hartmetall sicherheitshalber ersetzen.',
    contentIntl: {
      en: 'Carbide: extremely hard and wear resistant, almost no plastic deformation. Drop → microcracks → brittle fracture later. Steel: tougher and more flexible, tolerates slight bending, slightly lower cutting power. Rep tip: replace carbide tools after drops or visible damage.',
      es: 'Carburo: muy duro y resistente al desgaste, casi sin deformación plástica. Caída → microfisuras → rotura frágil posterior. Acero: mayor tenacidad y flexión, tolera ligera deformación, algo menor poder de corte. Consejo: sustituir instrumentos de carburo tras caídas o daños visibles.',
      fr: 'Carbure : très dur et résistant à l’usure, quasi aucune déformation plastique. Chute → microfissures → rupture fragile. Acier : plus tenace et flexible, tolère une légère flexion, puissance de coupe un peu moindre. Conseil : remplacer les instruments en carbure après une chute ou tout dommage visible.',
      it: 'Carburo: estremamente duro e resistente all’usura, quasi nessuna deformazione plastica. Caduta → microfratture → rottura fragile. Acciaio: più tenace e flessibile, tollera una lieve piega, potere di taglio leggermente inferiore. Suggerimento: sostituire gli strumenti in carburo dopo cadute o danni visibili.',
    },
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
    titleIntl: {
      en: 'Typical root causes for breaks in carbide instruments',
      es: 'Causas típicas de rotura en instrumentos de carburo',
      fr: 'Causes typiques de rupture des instruments en carbure',
      it: 'Cause tipiche di rottura degli strumenti in carburo',
    },
    teaser: 'Häufige Ursachen und Checkliste für Rückfragen beim Kunden.',
    teaserIntl: {
      en: 'Common causes and a checklist for customer follow-up.',
      es: 'Causas frecuentes y lista de comprobación para hablar con el cliente.',
      fr: 'Causes fréquentes et liste de vérification pour les questions clients.',
      it: 'Cause frequenti e checklist per il follow-up con il cliente.',
    },
    importance: 'normal',
    contentMarkdown:
      'Ursachen: Sturz/Mikrorisse, falsche Spannlänge, Verkanten/Biegebelastung, zu hohe Drehzahl, verschlissene Instrumente, aggressive Aufbereitung. Check: Sturz? Spannlänge? Drehzahl/Druck? Aufbereitungshistorie? Sichtbarer Verschleiß/Korrosion? Hinweis: Einzelbruch ≠ Serienfehler.',
    contentIntl: {
      en: 'Causes: drops/microcracks, wrong chuck length, jamming/bending load, overspeed, worn tools, aggressive reprocessing. Check: dropped? correct chuck length? speed/pressure used? reprocessing history? visible wear/corrosion? Note: one break is not automatically a batch defect.',
      es: 'Causas: caídas/microfisuras, longitud de sujeción incorrecta, atascos/flexión, exceso de velocidad, desgaste, reprocesado agresivo. Comprobar: ¿se cayó? ¿longitud correcta? ¿velocidad/presión? ¿historial de reprocesado? ¿desgaste/corrosión visible? Nota: una rotura aislada no implica defecto de serie.',
      fr: 'Causes : chutes/microfissures, mauvaise longueur de serrage, coincement/flexion, vitesse excessive, usure, retraitement agressif. À vérifier : chute ? bonne longueur ? vitesse/pression ? historique de retraitement ? usure/corrosion visible ? Remarque : une casse isolée n’est pas forcément un défaut de lot.',
      it: 'Cause: cadute/microfratture, lunghezza di serraggio errata, impuntamento/flessione, velocità eccessiva, usura, ricondizionamento aggressivo. Verifiche: caduto? lunghezza corretta? velocità/pressione? storia di ricondizionamento? usura/corrosione visibile? Nota: una rottura isolata non è automaticamente un difetto di lotto.',
    },
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
    titleIntl: {
      en: 'Complaint prevention for MDR-TD1 – correct use of diamond and carbide tools',
      es: 'Prevención de reclamaciones en MDR-TD1 – uso correcto de instrumentos de diamante y carburo',
      fr: 'Prévention des réclamations MDR-TD1 – bon usage des instruments diamantés et carbure',
      it: 'Prevenzione reclami MDR-TD1 – uso corretto di strumenti diamantati e in carburo',
    },
    teaser: 'Kurzleitfaden zu Kühlung, Drehzahl, Druck und Austauschintervallen für MDR-TD1.',
    teaserIntl: {
      en: 'Short guide on cooling, speed, pressure and replacement intervals for MDR-TD1.',
      es: 'Guía breve sobre refrigeración, velocidad, presión y sustitución en MDR-TD1.',
      fr: 'Guide court sur le refroidissement, la vitesse, la pression et le remplacement pour MDR-TD1.',
      it: 'Guida rapida su raffreddamento, velocità, pressione e sostituzione per MDR-TD1.',
    },
    importance: 'normal',
    contentMarkdown: `- Immer ausreichende Wasserkühlung nutzen
- Leichten Anpressdruck, Instrument schneiden lassen
- Drehzahl gemäß Herstellerangabe konstant halten
- Verschlissene oder beschädigte Instrumente frühzeitig austauschen

**Erklärhilfe:** „Kühlung, wenig Druck, richtige Drehzahl – dann halten die Instrumente länger und liefern bessere Oberflächen.“`,
    contentIntl: {
      en: `- Always use sufficient water cooling
- Apply light pressure; let the tool cut
- Keep speed per manufacturer specification
- Replace worn or damaged tools early

**How to explain:** “Cooling, low pressure, correct speed – instruments last longer and give better surfaces.”`,
      es: `- Usar siempre refrigeración con agua suficiente
- Presión ligera, dejar que la fresa corte
- Mantener la velocidad indicada por el fabricante
- Sustituir a tiempo instrumentos desgastados o dañados

**Cómo explicarlo:** “Refrigeración, poca presión, velocidad correcta: más durabilidad y mejores superficies.”`,
      fr: `- Toujours utiliser un refroidissement à l’eau suffisant
- Pression légère, laisser l’instrument travailler
- Vitesse conforme aux indications fabricant
- Remplacer tôt les instruments usés ou endommagés

**Comment l’expliquer :** « Refroidissement, faible pression, bonne vitesse : durée de vie prolongée et meilleures surfaces. »`,
      it: `- Usare sempre adeguato raffreddamento ad acqua
- Pressione leggera, lasciare che lo strumento tagli
- Mantenere la velocità indicata dal produttore
- Sostituire precocemente strumenti usurati o danneggiati

**Come spiegarlo:** “Raffreddamento, poca pressione, velocità corretta: più durata e migliori superfici.”`,
    },
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
    titleIntl: {
      en: 'MDR-TD3 – Dental polishers: solid, Uporal brush, and Diafix-Oral felt',
      es: 'MDR-TD3 – Pulidores dentales: goma, cepillo Uporal y fieltro Diafix-Oral',
      fr: 'MDR-TD3 – Polissoirs dentaires : gomme, brosse Uporal et feutre Diafix-Oral',
      it: 'MDR-TD3 – Lucidatori dentali: gomma, spazzola Uporal e feltro Diafix-Oral',
    },
    teaser: 'Überblick über Polierer-Typen, typische Einsatzbereiche und Anwendungshinweise.',
    teaserIntl: {
      en: 'Overview of polisher types, common use cases, and handling notes.',
      es: 'Resumen de tipos de pulidores, usos habituales y consejos de aplicación.',
      fr: 'Aperçu des types de polissoirs, usages typiques et conseils d’application.',
      it: 'Panoramica sui tipi di lucidatori, impieghi tipici e indicazioni d’uso.',
    },
    importance: 'normal',
    contentMarkdown: `- Festkörperpolierer (Gummi): Vor- und Hochglanzpolitur an Komposit/Keramik
- Uporal (Bürstenpolierer): sanfte Anpassung und Politur, auch an sensiblen Flächen
- Diafix-Oral (Filzpolierer): Hochglanzfinish für Metall/Keramik
Hinweise: empfohlene Drehzahl einhalten, moderater Druck, falls vorgesehen nicht trocken fahren; Einmal-/Mehrfachgebrauch je Produkt beachten.`,
    contentIntl: {
      en: `- Solid rubber polishers: pre- and high-gloss polish on composite/ceramic
- Uporal brush polishers: gentle adjustment and polishing, including delicate areas
- Diafix-Oral felt polishers: high-gloss finish for metal/ceramic
Notes: use recommended speed, moderate pressure, avoid dry use if cooling required; check single- vs. multi-use.`,
      es: `- Pulidores de goma: pre y alto brillo en composite/cerámica
- Pulidores de cepillo Uporal: ajuste y pulido suaves, incluso en zonas delicadas
- Pulidores de fieltro Diafix-Oral: acabado de alto brillo para metal/cerámica
Notas: respetar velocidad recomendada, presión moderada, evitar uso en seco si se requiere refrigeración; comprobar si son de un solo uso o reutilizables.`,
      fr: `- Polissoirs en caoutchouc : pré- et haute brillance sur composite/céramique
- Polissoirs brosse Uporal : ajustement doux, même sur zones sensibles
- Polissoirs feutre Diafix-Oral : finition haute brillance métal/céramique
Notes : respecter la vitesse recommandée, pression modérée, pas d’utilisation à sec si refroidissement requis ; vérifier usage unique/réutilisable.`,
      it: `- Lucidatori in gomma: pre e alta lucentezza su composito/ceramica
- Lucidatori a spazzola Uporal: regolazione e lucidatura delicata, anche su superfici sensibili
- Lucidatori in feltro Diafix-Oral: finitura a specchio per metallo/ceramica
Note: rispettare la velocità consigliata, pressione moderata, evitare uso a secco se serve raffreddamento; controllare monouso o riutilizzo.`,
    },
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
    titleIntl: {
      en: 'MDR-TD4 – PreciCut: soft tissue cutters and key properties',
      es: 'MDR-TD4 – PreciCut: cortadores de tejido blando y propiedades clave',
      fr: 'MDR-TD4 – PreciCut : coupe-tissus mous et propriétés clés',
      it: 'MDR-TD4 – PreciCut: cutter per tessuti molli e caratteristiche chiave',
    },
    teaser: 'Indikation, Handhabung und Sicherheitshinweise für PreciCut.',
    teaserIntl: {
      en: 'Indication, handling, and safety notes for PreciCut.',
      es: 'Indicaciones, manejo y notas de seguridad para PreciCut.',
      fr: 'Indications, manipulation et conseils de sécurité pour PreciCut.',
      it: 'Indicazioni, gestione e note di sicurezza per PreciCut.',
    },
    importance: 'normal',
    contentMarkdown:
      'Einsatz: präzise Schnitte im Weichgewebe (z. B. Gingiva). Handhabung: Drehzahl nach Hersteller, schonende Schnittführung, sicherer Sitz im Handstück. Sicherheit: atraumatisch arbeiten, beschädigte Instrumente sofort aussondern.',
    contentIntl: {
      en: 'Use: precise soft-tissue cutting (e.g., gingiva). Handling: use manufacturer speed, gentle cutting motion, ensure secure chucking. Safety: work atraumatically, discard damaged instruments immediately.',
      es: 'Uso: cortes precisos en tejido blando (p. ej., encía). Manejo: velocidad según fabricante, corte suave, fijación segura en la pieza de mano. Seguridad: trabajar de forma atraumática, descartar instrumentos dañados.',
      fr: 'Usage : coupes précises des tissus mous (p. ex. gencive). Manipulation : vitesse selon fabricant, geste doux, serrage sûr dans la pièce à main. Sécurité : travail atraumatique, écarter immédiatement tout instrument endommagé.',
      it: 'Uso: tagli precisi nel tessuto molle (es. gengiva). Gestione: velocità secondo il produttore, movimento di taglio delicato, serraggio sicuro nel manipolo. Sicurezza: lavorare in modo atraumatico, scartare subito gli strumenti danneggiati.',
    },
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
    titleIntl: {
      en: 'MDR-TD5 – Dental alloys: Diadur CoCr overview',
      es: 'MDR-TD5 – Aleaciones dentales: resumen de Diadur CoCr',
      fr: 'MDR-TD5 – Alliages dentaires : aperçu Diadur CoCr',
      it: 'MDR-TD5 – Leghe dentali: panoramica Diadur CoCr',
    },
    teaser: 'Werkstoff-Steckbrief zur Diadur CoCr-Legierung, Einsatzgebiete und Nutzen für Kunden.',
    teaserIntl: {
      en: 'Material facts for the Diadur CoCr alloy, its uses and benefits.',
      es: 'Ficha del material de la aleación Diadur CoCr, usos y beneficios.',
      fr: 'Fiche matériau de l’alliage Diadur CoCr, usages et bénéfices.',
      it: 'Scheda materiale della lega Diadur CoCr, usi e vantaggi.',
    },
    importance: 'normal',
    contentMarkdown:
      'Werkstoff: Diadur CoCr-Legierung für Kronen, Brücken und Gerüste. Eigenschaften: hohe Festigkeit, Biokompatibilität, Korrosionsbeständigkeit. Nutzen: schlanke, stabile Konstruktionen. **Kurzfassung für Vertreter:** „CoCr liefert Stabilität und Biokompatibilität für langlebige Restaurationen.“',
    contentIntl: {
      en: 'Material: Diadur CoCr alloy for crowns, bridges, and frameworks. Properties: high strength, biocompatibility, corrosion resistance. Benefit: slim yet stable constructions. **Rep short pitch:** “CoCr delivers stability and biocompatibility for long-lasting restorations.”',
      es: 'Material: aleación Diadur CoCr para coronas, puentes y estructuras. Propiedades: alta resistencia, biocompatibilidad, resistencia a la corrosión. Beneficio: estructuras finas y estables. **Resumen para representantes:** “CoCr ofrece estabilidad y biocompatibilidad para restauraciones duraderas.”',
      fr: 'Matériau : alliage Diadur CoCr pour couronnes, ponts et armatures. Propriétés : haute résistance, biocompatibilité, résistance à la corrosion. Avantage : constructions fines et stables. **Pitch représentant :** « Le CoCr apporte stabilité et biocompatibilité pour des restaurations durables. »',
      it: 'Materiale: lega Diadur CoCr per corone, ponti e strutture. Proprietà: elevata resistenza, biocompatibilità, resistenza alla corrosione. Vantaggio: strutture sottili ma stabili. **Sintesi per i rappresentanti:** “Il CoCr offre stabilità e biocompatibilità per restauri duraturi.”',
    },
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
    titleIntl: {
      en: 'FAQ – How long can DFS instruments be used?',
      es: 'FAQ – ¿Cuánto tiempo pueden usarse los instrumentos DFS?',
      fr: 'FAQ – Combien de temps utiliser les instruments DFS ?',
      it: 'FAQ – Per quanto tempo si possono usare gli strumenti DFS?',
    },
    teaser: 'Standardantwort zur Einsatzdauer – abhängig von Belastung, Aufbereitung und Material.',
    teaserIntl: {
      en: 'Standard answer on lifetime – depends on load, reprocessing, and material.',
      es: 'Respuesta estándar sobre la vida útil: depende de carga, reprocesado y material.',
      fr: 'Réponse standard sur la durée de vie – dépend de la charge, du retraitement et du matériau.',
      it: 'Risposta standard sulla durata – dipende da carico, ricondizionamento e materiale.',
    },
    importance: 'normal',
    contentMarkdown:
      'Lebensdauer hängt von Belastung, Aufbereitung, Material und Indikation ab. Vor jedem Einsatz Sichtkontrolle; bei Rissen, Verformung oder Leistungsverlust sofort ersetzen. Gebrauchsanweisung enthält zulässige Zyklen. Dokumentation der Aufbereitungen hilft. **Vertreter-Hinweis:** Immer auf die jeweilige Gebrauchsanweisung verweisen, falls konkrete Zykluszahlen gefragt sind.',
    contentIntl: {
      en: 'Lifetime depends on load, reprocessing, material and indication. Visual check before use; replace immediately if cracks, deformation or performance loss. Instructions for use list allowed cycles. Document reprocessing. **Rep note:** Always refer to the IFU when exact cycle numbers are requested.',
      es: 'La vida útil depende de carga, reprocesado, material e indicación. Revisar antes de usar; sustituir si hay grietas, deformación o pérdida de rendimiento. Las IFU indican los ciclos permitidos. Documentar los reprocesados. **Nota del representante:** Remitir siempre a las IFU si se piden cifras de ciclos.',
      fr: 'La durée de vie dépend de la charge, du retraitement, du matériau et de l’indication. Vérifier avant usage ; remplacer en cas de fissure, déformation ou perte d’efficacité. La notice indique les cycles autorisés. Documenter les retraitements. **Note représentant :** se référer à la notice si des chiffres précis sont demandés.',
      it: 'La durata dipende da carico, ricondizionamento, materiale e indicazione. Controllo visivo prima dell’uso; sostituire in caso di crepe, deformazioni o perdita di prestazioni. Le istruzioni indicano i cicli ammessi. Documentare i ricondizionamenti. **Nota per i rappresentanti:** rimandare sempre alle IFU se vengono chiesti numeri di cicli.',
    },
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
    titleIntl: {
      en: 'Reprocessing DFS instruments – what reps should say',
      es: 'Reprocesado de instrumentos DFS – qué deben decir los representantes',
      fr: 'Retraitement des instruments DFS – que doivent dire les représentants',
      it: 'Ricondizionamento degli strumenti DFS – cosa devono dire i rappresentanti',
    },
    teaser: 'Kurzleitfaden zur Kommunikation von Reinigung, Desinfektion und Sterilisation.',
    teaserIntl: {
      en: 'Short guide on communicating cleaning, disinfection, and sterilization.',
      es: 'Guía breve para explicar limpieza, desinfección y esterilización.',
      fr: 'Guide court pour expliquer nettoyage, désinfection et stérilisation.',
      it: 'Guida rapida per spiegare pulizia, disinfezione e sterilizzazione.',
    },
    importance: 'normal',
    contentMarkdown:
      'Kernbotschaft: sofortige Vorreinigung, validierte maschinelle Reinigung/Desinfektion, Sterilisation nach Herstellerangaben (Zyklus, Verpackung, Beladung). Kommunikation: „Gebrauchsanweisung ist maßgeblich“; bei komplexen Fragen QM/Regulatory einbinden; nach jedem Zyklus auf Beschädigungen prüfen. **Vertreter-Kurztext:** „Direkt vorreinigen, validiert aufbereiten, steril nach Hersteller – Details stehen in der Gebrauchsanweisung.“',
    contentIntl: {
      en: 'Key message: immediate pre-cleaning, validated machine cleaning/disinfection, sterilization per manufacturer specs (cycle, packaging, load). Communication: “IFU is binding”; involve QA/RA for complex questions; check for damage after each cycle. **Rep short script:** “Pre-clean right away, reprocess with validation, sterilize per manufacturer – details are in the IFU.”',
      es: 'Mensaje clave: prelavado inmediato, limpieza/desinfección mecánica validada, esterilización según especificaciones del fabricante (ciclo, embalaje, carga). Comunicación: “Las IFU son vinculantes”; implicar QA/RA para dudas complejas; revisar daños tras cada ciclo. **Texto breve para representantes:** “Prelavar, reprocesar validado, esterilizar según el fabricante: los detalles están en las IFU.”',
      fr: 'Message clé : pré-nettoyage immédiat, nettoyage/désinfection machine validés, stérilisation selon les indications fabricant (cycle, emballage, charge). Communication : « La notice fait foi » ; impliquer AQ/RA pour questions complexes ; contrôler les dommages après chaque cycle. **Script court :** « Vorrreinigen, retraiter validé, stériliser selon le fabricant – les détails sont dans la notice. »',
      it: 'Messaggio chiave: prelavaggio immediato, pulizia/disinfezione meccanica validata, sterilizzazione secondo le specifiche del produttore (ciclo, confezione, carico). Comunicazione: “Le IFU sono vincolanti”; coinvolgere QA/RA per domande complesse; controllare danni dopo ogni ciclo. **Script breve:** “Prelavare subito, ricondizionare in modo validato, sterilizzare secondo il produttore – i dettagli sono nelle IFU.”',
    },
    isActive: true,
    createdAt: defaultTimestamp,
    updatedAt: defaultTimestamp,
  },
];
