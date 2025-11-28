import '../l10n/app_localizations.dart';

typedef DownloadCategoryLocalizationFn = String Function(AppLocalizations t);

const List<String> kDefaultDownloadCategories = [
  'Sicherheitsdatenblätter',
  'Gebrauchsanweisungen',
  'Aufbereitungsanweisungen',
  'Kataloge',
  'Produktflyer',
  'Registrierungsdokumente',
  'sonstige Dokumente',
];

final Map<String, DownloadCategoryLocalizationFn> kDownloadCategoryLocalizations = {
  'Sicherheitsdatenblätter': (t) => t.download_category_safety_data_sheets,
  'Gebrauchsanweisungen': (t) => t.download_category_instructions,
  'Aufbereitungsanweisungen': (t) => t.download_category_processing_instructions,
  'Kataloge': (t) => t.download_category_catalogues,
  'Produktflyer': (t) => t.download_category_product_flyers,
  'Registrierungsdokumente': (t) => t.download_category_registration_documents,
  'sonstige Dokumente': (t) => t.download_category_other_documents,
};

String localizeDownloadCategory(AppLocalizations t, String category) {
  final translator = kDownloadCategoryLocalizations[category.trim()];
  return translator != null ? translator(t) : category;
}
