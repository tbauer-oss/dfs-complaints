// lib/models/country.dart
import 'package:flutter/widgets.dart';

class Country {
  final String code;                 // ISO 3166-1 alpha-2 (z. B. "DE")
  final Map<String, String> names;   // Lokalisierte Anzeigenamen

  const Country({required this.code, required this.names});

  String label(BuildContext context) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    return names[lang] ?? names['en'] ?? names.values.first;
  }
}

// ---- Master list (English only) ----
// Coverage: all UN members + commonly used territories (HK, MO, TW, XK, etc.)
final List<Country> kCountries = (() {
  // WICHTIG: keine doppelten Keys!
  const Map<String, String> data = {
    // EUROPE (incl. microstates & extras)
    'AL':'Albania','AD':'Andorra','AM':'Armenia','AT':'Austria','AZ':'Azerbaijan',
    'BA':'Bosnia and Herzegovina','BE':'Belgium','BG':'Bulgaria','BY':'Belarus',
    'CH':'Switzerland','CY':'Cyprus','CZ':'Czechia','DE':'Germany','DK':'Denmark',
    'EE':'Estonia','ES':'Spain','FI':'Finland','FO':'Faroe Islands','FR':'France',
    'GB':'United Kingdom','GI':'Gibraltar','GR':'Greece','HR':'Croatia','HU':'Hungary',
    'IE':'Ireland','IS':'Iceland','IT':'Italy','LI':'Liechtenstein','LT':'Lithuania',
    'LU':'Luxembourg','LV':'Latvia','MC':'Monaco','MD':'Moldova','ME':'Montenegro',
    'MK':'North Macedonia','MT':'Malta','NL':'Netherlands','NO':'Norway','PL':'Poland',
    'PT':'Portugal','RO':'Romania','RS':'Serbia','RU':'Russia','SE':'Sweden','SI':'Slovenia',
    'SK':'Slovakia','SM':'San Marino','UA':'Ukraine','VA':'Holy See','XK':'Kosovo',
    'AX':'Åland Islands','JE':'Jersey','GG':'Guernsey','IM':'Isle of Man','SJ':'Svalbard and Jan Mayen',

    // NORTH AMERICA & CARIBBEAN
    'AG':'Antigua and Barbuda','AI':'Anguilla','AW':'Aruba','BB':'Barbados','BL':'Saint Barthélemy',
    'BM':'Bermuda','BS':'Bahamas','BZ':'Belize','CA':'Canada','CR':'Costa Rica','CU':'Cuba',
    'CW':'Curaçao','DM':'Dominica','DO':'Dominican Republic','GD':'Grenada','GL':'Greenland',
    'GP':'Guadeloupe','GT':'Guatemala','HN':'Honduras','HT':'Haiti','JM':'Jamaica',
    'KN':'Saint Kitts and Nevis','KY':'Cayman Islands','LC':'Saint Lucia','MF':'Saint Martin',
    'MQ':'Martinique','MS':'Montserrat','MX':'Mexico','NI':'Nicaragua','PA':'Panama',
    'PM':'Saint Pierre and Miquelon','PR':'Puerto Rico','SV':'El Salvador','SX':'Sint Maarten',
    'TC':'Turks and Caicos Islands','TT':'Trinidad and Tobago','UM':'U.S. Outlying Islands',
    'VC':'Saint Vincent and the Grenadines','VG':'British Virgin Islands','VI':'U.S. Virgin Islands',
    'US':'United States',

    // SOUTH AMERICA
    'AR':'Argentina','BO':'Bolivia','BR':'Brazil','CL':'Chile','CO':'Colombia','EC':'Ecuador',
    'FK':'Falkland Islands','GF':'French Guiana','GY':'Guyana','PE':'Peru','PY':'Paraguay',
    'SR':'Suriname','UY':'Uruguay','VE':'Venezuela',

    // AFRICA
    'AO':'Angola','BF':'Burkina Faso','BI':'Burundi','BJ':'Benin','BW':'Botswana','CD':'Congo (DRC)',
    'CF':'Central African Republic','CG':'Congo','CI':"Côte d’Ivoire",'CM':'Cameroon','CV':'Cabo Verde',
    'DJ':'Djibouti','DZ':'Algeria','EG':'Egypt','EH':'Western Sahara','ER':'Eritrea','ET':'Ethiopia',
    'GA':'Gabon','GH':'Ghana','GM':'Gambia','GN':'Guinea','GQ':'Equatorial Guinea','GW':'Guinea-Bissau',
    'KE':'Kenya','KM':'Comoros','LR':'Liberia','LS':'Lesotho','LY':'Libya','MA':'Morocco',
    'MG':'Madagascar','ML':'Mali','MR':'Mauritania','MU':'Mauritius','MW':'Malawi','MZ':'Mozambique',
    'NA':'Namibia','NE':'Niger','NG':'Nigeria','RE':'Réunion','RW':'Rwanda','SC':'Seychelles',
    'SD':'Sudan','SH':'Saint Helena, Ascension and Tristan da Cunha','SL':'Sierra Leone','SN':'Senegal',
    'SO':'Somalia','SS':'South Sudan','ST':'São Tomé and Príncipe','SZ':'Eswatini','TD':'Chad',
    'TG':'Togo','TN':'Tunisia','TZ':'Tanzania','UG':'Uganda','YT':'Mayotte','ZA':'South Africa',
    'ZM':'Zambia','ZW':'Zimbabwe',

    // MIDDLE EAST & CENTRAL ASIA
    'AE':'United Arab Emirates','AF':'Afghanistan',
    // 'AM':'Armenia',        // <— entfernt: bereits oben gelistet
    // 'AZ':'Azerbaijan',     // <— entfernt: bereits oben gelistet
    'BH':'Bahrain','GE':'Georgia','IL':'Israel','IQ':'Iraq','IR':'Iran','JO':'Jordan',
    'KG':'Kyrgyzstan','KW':'Kuwait','KZ':'Kazakhstan','LB':'Lebanon','OM':'Oman','PK':'Pakistan',
    'PS':'Palestine, State of','QA':'Qatar','SA':'Saudi Arabia','SY':'Syria','TJ':'Tajikistan',
    'TM':'Turkmenistan','TR':'Türkiye','UZ':'Uzbekistan','YE':'Yemen',

    // SOUTH & EAST ASIA
    'BD':'Bangladesh','BN':'Brunei','BT':'Bhutan','CC':'Cocos (Keeling) Islands','CN':'China',
    'HK':'Hong Kong','ID':'Indonesia','IN':'India','JP':'Japan','KH':'Cambodia','KP':'Korea (North)',
    'KR':'Korea (South)','LA':'Lao People’s Democratic Republic','LK':'Sri Lanka','MM':'Myanmar',
    'MN':'Mongolia','MO':'Macao','MY':'Malaysia','NP':'Nepal','PH':'Philippines','SG':'Singapore',
    'TH':'Thailand','TL':'Timor-Leste','TW':'Taiwan','VN':'Viet Nam',

    // OCEANIA
    'AS':'American Samoa','AU':'Australia','CK':'Cook Islands','FJ':'Fiji','FM':'Micronesia',
    'GU':'Guam','KI':'Kiribati','MH':'Marshall Islands','MP':'Northern Mariana Islands','NC':'New Caledonia',
    'NF':'Norfolk Island','NR':'Nauru','NU':'Niue','NZ':'New Zealand','PF':'French Polynesia',
    'PG':'Papua New Guinea','PN':'Pitcairn','PW':'Palau','SB':'Solomon Islands','TK':'Tokelau',
    'TO':'Tonga','TV':'Tuvalu','VU':'Vanuatu','WF':'Wallis and Futuna','WS':'Samoa',

    // POLAR/OTHER
    'AQ':'Antarctica','BV':'Bouvet Island','CX':'Christmas Island','BQ':'Caribbean Netherlands',
  };

  final list = data.entries
      .map((e) => Country(code: e.key, names: {'en': e.value}))
      .toList();

  // sort by English label for stable UI dropdowns
  list.sort((a, b) => (a.names['en']!).compareTo(b.names['en']!));
  return list;
})();
