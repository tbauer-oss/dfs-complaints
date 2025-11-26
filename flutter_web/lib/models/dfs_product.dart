class DfsProduct {
  final String tdNumberAndName;
  final String basicUdiDi;
  final String productGroup;
  final String articleNumber;
  final String productName;
  final String isoCode;
  final String packagingUnitVe;
  final String riskClass;
  final String classificationRule;
  final String udiSingleUnit;
  final String udiVe;
  final String mdrCode;
  final String gmdn;
  final String umdnsCode;
  final String emdn;
  final String dmidsNo;
  final String certificationNo;
  final String material;
  final String surfaceInfo;
  final String firstPlacingOnMarketDate;
  final String legacyDevice;

  const DfsProduct({
    required this.tdNumberAndName,
    required this.basicUdiDi,
    required this.productGroup,
    required this.articleNumber,
    required this.productName,
    required this.isoCode,
    required this.packagingUnitVe,
    required this.riskClass,
    required this.classificationRule,
    required this.udiSingleUnit,
    required this.udiVe,
    required this.mdrCode,
    required this.gmdn,
    required this.umdnsCode,
    required this.emdn,
    required this.dmidsNo,
    required this.certificationNo,
    required this.material,
    required this.surfaceInfo,
    required this.firstPlacingOnMarketDate,
    required this.legacyDevice,
  });

  DfsProduct copyWith({
    String? tdNumberAndName,
    String? basicUdiDi,
    String? productGroup,
    String? articleNumber,
    String? productName,
    String? isoCode,
    String? packagingUnitVe,
    String? riskClass,
    String? classificationRule,
    String? udiSingleUnit,
    String? udiVe,
    String? mdrCode,
    String? gmdn,
    String? umdnsCode,
    String? emdn,
    String? dmidsNo,
    String? certificationNo,
    String? material,
    String? surfaceInfo,
    String? firstPlacingOnMarketDate,
    String? legacyDevice,
  }) {
    return DfsProduct(
      tdNumberAndName: tdNumberAndName ?? this.tdNumberAndName,
      basicUdiDi: basicUdiDi ?? this.basicUdiDi,
      productGroup: productGroup ?? this.productGroup,
      articleNumber: articleNumber ?? this.articleNumber,
      productName: productName ?? this.productName,
      isoCode: isoCode ?? this.isoCode,
      packagingUnitVe: packagingUnitVe ?? this.packagingUnitVe,
      riskClass: riskClass ?? this.riskClass,
      classificationRule: classificationRule ?? this.classificationRule,
      udiSingleUnit: udiSingleUnit ?? this.udiSingleUnit,
      udiVe: udiVe ?? this.udiVe,
      mdrCode: mdrCode ?? this.mdrCode,
      gmdn: gmdn ?? this.gmdn,
      umdnsCode: umdnsCode ?? this.umdnsCode,
      emdn: emdn ?? this.emdn,
      dmidsNo: dmidsNo ?? this.dmidsNo,
      certificationNo: certificationNo ?? this.certificationNo,
      material: material ?? this.material,
      surfaceInfo: surfaceInfo ?? this.surfaceInfo,
      firstPlacingOnMarketDate:
          firstPlacingOnMarketDate ?? this.firstPlacingOnMarketDate,
      legacyDevice: legacyDevice ?? this.legacyDevice,
    );
  }

  static const fieldOrder = [
    'td_number_and_name',
    'basic_udi_di',
    'product_group',
    'article_number',
    'product_name',
    'iso_code',
    'packaging_unit_ve',
    'risk_class',
    'classification_rule',
    'udi_single_unit',
    'udi_ve',
    'mdr_code',
    'gmdn',
    'umdns_code',
    'emdn',
    'dmids_no',
    'certification_no',
    'material',
    'surface_info',
    'first_placing_on_market_date',
    'legacy_device',
  ];

  static const fieldLabels = <String, String>{
    'td_number_and_name': 'TD-Nr. und Bezeichnung',
    'basic_udi_di': 'Basic-UDI-DI',
    'product_group': 'Produktgruppe',
    'article_number': 'Artikelnummer',
    'product_name': 'Produktname',
    'iso_code': 'ISO-Code',
    'packaging_unit_ve': 'Verpackungseinheit (VE)',
    'risk_class': 'Risikoklasse',
    'classification_rule': 'Klassifizierungsregel',
    'udi_single_unit': 'UDI (Single Unit)',
    'udi_ve': 'UDI (VE)',
    'mdr_code': 'MDR-Code',
    'gmdn': 'GMDN',
    'umdns_code': 'UMDNS-Code',
    'emdn': 'EMDN',
    'dmids_no': 'DMIDS No.',
    'certification_no': 'Certification no.',
    'material': 'Material',
    'surface_info': 'Zusätzliche Information: Oberfläche',
    'first_placing_on_market_date':
        'Datum des ersten Inverkehrbringens',
    'legacy_device': 'Legacy device? (x/leer)',
  };

  factory DfsProduct.fromHeaderMap(Map<String, String> values) {
    String pick(String key) => values[key]?.trim() ?? '';
    return DfsProduct(
      tdNumberAndName: pick('td_number_and_name'),
      basicUdiDi: pick('basic_udi_di'),
      productGroup: pick('product_group'),
      articleNumber: pick('article_number'),
      productName: pick('product_name'),
      isoCode: pick('iso_code'),
      packagingUnitVe: pick('packaging_unit_ve'),
      riskClass: pick('risk_class'),
      classificationRule: pick('classification_rule'),
      udiSingleUnit: pick('udi_single_unit'),
      udiVe: pick('udi_ve'),
      mdrCode: pick('mdr_code'),
      gmdn: pick('gmdn'),
      umdnsCode: pick('umdns_code'),
      emdn: pick('emdn'),
      dmidsNo: pick('dmids_no'),
      certificationNo: pick('certification_no'),
      material: pick('material'),
      surfaceInfo: pick('surface_info'),
      firstPlacingOnMarketDate: pick('first_placing_on_market_date'),
      legacyDevice: pick('legacy_device'),
    );
  }

  Map<String, String> toHeaderMap() => {
        'td_number_and_name': tdNumberAndName,
        'basic_udi_di': basicUdiDi,
        'product_group': productGroup,
        'article_number': articleNumber,
        'product_name': productName,
        'iso_code': isoCode,
        'packaging_unit_ve': packagingUnitVe,
        'risk_class': riskClass,
        'classification_rule': classificationRule,
        'udi_single_unit': udiSingleUnit,
        'udi_ve': udiVe,
        'mdr_code': mdrCode,
        'gmdn': gmdn,
        'umdns_code': umdnsCode,
        'emdn': emdn,
        'dmids_no': dmidsNo,
        'certification_no': certificationNo,
        'material': material,
        'surface_info': surfaceInfo,
        'first_placing_on_market_date': firstPlacingOnMarketDate,
        'legacy_device': legacyDevice,
      };

  String fieldValue(String key) => toHeaderMap()[key] ?? '';
}
