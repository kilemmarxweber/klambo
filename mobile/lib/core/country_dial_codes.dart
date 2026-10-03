/// Indicatifs téléphoniques internationaux + drapeaux (emoji).
class CountryDial {
  const CountryDial({
    required this.iso2,
    required this.dialCode,
    required this.nameFr,
    required this.nameEn,
    required this.namePt,
  });

  final String iso2;
  final String dialCode;
  final String nameFr;
  final String nameEn;
  final String namePt;

  String get flag {
    final cc = iso2.toUpperCase();
    if (cc.length != 2) return "🏳️";
    return String.fromCharCodes(
      cc.codeUnits.map((c) => 0x1F1E6 - 65 + c),
    );
  }

  String nameFor(String lang) {
    switch (lang) {
      case "en":
        return nameEn;
      case "pt":
        return namePt;
      default:
        return nameFr;
    }
  }

  String get label => "$flag  +$dialCode";
}

const kDefaultCountryIso = "AO"; // Angola (+244) — écoles Klambocore

/// Liste complète (ISO) des pays / territoires avec indicatif.
const kCountryDials = <CountryDial>[
  CountryDial(iso2: "AF", dialCode: "93", nameFr: "Afghanistan", nameEn: "Afghanistan", namePt: "Afeganistão"),
  CountryDial(iso2: "ZA", dialCode: "27", nameFr: "Afrique du Sud", nameEn: "South Africa", namePt: "África do Sul"),
  CountryDial(iso2: "AL", dialCode: "355", nameFr: "Albanie", nameEn: "Albania", namePt: "Albânia"),
  CountryDial(iso2: "DZ", dialCode: "213", nameFr: "Algérie", nameEn: "Algeria", namePt: "Argélia"),
  CountryDial(iso2: "DE", dialCode: "49", nameFr: "Allemagne", nameEn: "Germany", namePt: "Alemanha"),
  CountryDial(iso2: "AD", dialCode: "376", nameFr: "Andorre", nameEn: "Andorra", namePt: "Andorra"),
  CountryDial(iso2: "AO", dialCode: "244", nameFr: "Angola", nameEn: "Angola", namePt: "Angola"),
  CountryDial(iso2: "AI", dialCode: "1264", nameFr: "Anguilla", nameEn: "Anguilla", namePt: "Anguila"),
  CountryDial(iso2: "AG", dialCode: "1268", nameFr: "Antigua-et-Barbuda", nameEn: "Antigua and Barbuda", namePt: "Antígua e Barbuda"),
  CountryDial(iso2: "SA", dialCode: "966", nameFr: "Arabie saoudite", nameEn: "Saudi Arabia", namePt: "Arábia Saudita"),
  CountryDial(iso2: "AR", dialCode: "54", nameFr: "Argentine", nameEn: "Argentina", namePt: "Argentina"),
  CountryDial(iso2: "AM", dialCode: "374", nameFr: "Arménie", nameEn: "Armenia", namePt: "Arménia"),
  CountryDial(iso2: "AW", dialCode: "297", nameFr: "Aruba", nameEn: "Aruba", namePt: "Aruba"),
  CountryDial(iso2: "AU", dialCode: "61", nameFr: "Australie", nameEn: "Australia", namePt: "Austrália"),
  CountryDial(iso2: "AT", dialCode: "43", nameFr: "Autriche", nameEn: "Austria", namePt: "Áustria"),
  CountryDial(iso2: "AZ", dialCode: "994", nameFr: "Azerbaïdjan", nameEn: "Azerbaijan", namePt: "Azerbaijão"),
  CountryDial(iso2: "BS", dialCode: "1242", nameFr: "Bahamas", nameEn: "Bahamas", namePt: "Bahamas"),
  CountryDial(iso2: "BH", dialCode: "973", nameFr: "Bahreïn", nameEn: "Bahrain", namePt: "Bahrein"),
  CountryDial(iso2: "BD", dialCode: "880", nameFr: "Bangladesh", nameEn: "Bangladesh", namePt: "Bangladesh"),
  CountryDial(iso2: "BB", dialCode: "1246", nameFr: "Barbade", nameEn: "Barbados", namePt: "Barbados"),
  CountryDial(iso2: "BE", dialCode: "32", nameFr: "Belgique", nameEn: "Belgium", namePt: "Bélgica"),
  CountryDial(iso2: "BZ", dialCode: "501", nameFr: "Belize", nameEn: "Belize", namePt: "Belize"),
  CountryDial(iso2: "BJ", dialCode: "229", nameFr: "Bénin", nameEn: "Benin", namePt: "Benim"),
  CountryDial(iso2: "BM", dialCode: "1441", nameFr: "Bermudes", nameEn: "Bermuda", namePt: "Bermudas"),
  CountryDial(iso2: "BT", dialCode: "975", nameFr: "Bhoutan", nameEn: "Bhutan", namePt: "Butão"),
  CountryDial(iso2: "BY", dialCode: "375", nameFr: "Biélorussie", nameEn: "Belarus", namePt: "Bielorrússia"),
  CountryDial(iso2: "MM", dialCode: "95", nameFr: "Birmanie", nameEn: "Myanmar", namePt: "Mianmar"),
  CountryDial(iso2: "BO", dialCode: "591", nameFr: "Bolivie", nameEn: "Bolivia", namePt: "Bolívia"),
  CountryDial(iso2: "BA", dialCode: "387", nameFr: "Bosnie-Herzégovine", nameEn: "Bosnia and Herzegovina", namePt: "Bósnia e Herzegovina"),
  CountryDial(iso2: "BW", dialCode: "267", nameFr: "Botswana", nameEn: "Botswana", namePt: "Botsuana"),
  CountryDial(iso2: "BR", dialCode: "55", nameFr: "Brésil", nameEn: "Brazil", namePt: "Brasil"),
  CountryDial(iso2: "BN", dialCode: "673", nameFr: "Brunei", nameEn: "Brunei", namePt: "Brunei"),
  CountryDial(iso2: "BG", dialCode: "359", nameFr: "Bulgarie", nameEn: "Bulgaria", namePt: "Bulgária"),
  CountryDial(iso2: "BF", dialCode: "226", nameFr: "Burkina Faso", nameEn: "Burkina Faso", namePt: "Burquina Faso"),
  CountryDial(iso2: "BI", dialCode: "257", nameFr: "Burundi", nameEn: "Burundi", namePt: "Burundi"),
  CountryDial(iso2: "KH", dialCode: "855", nameFr: "Cambodge", nameEn: "Cambodia", namePt: "Camboja"),
  CountryDial(iso2: "CM", dialCode: "237", nameFr: "Cameroun", nameEn: "Cameroon", namePt: "Camarões"),
  CountryDial(iso2: "CA", dialCode: "1", nameFr: "Canada", nameEn: "Canada", namePt: "Canadá"),
  CountryDial(iso2: "CV", dialCode: "238", nameFr: "Cap-Vert", nameEn: "Cape Verde", namePt: "Cabo Verde"),
  CountryDial(iso2: "CL", dialCode: "56", nameFr: "Chili", nameEn: "Chile", namePt: "Chile"),
  CountryDial(iso2: "CN", dialCode: "86", nameFr: "Chine", nameEn: "China", namePt: "China"),
  CountryDial(iso2: "CY", dialCode: "357", nameFr: "Chypre", nameEn: "Cyprus", namePt: "Chipre"),
  CountryDial(iso2: "CO", dialCode: "57", nameFr: "Colombie", nameEn: "Colombia", namePt: "Colômbia"),
  CountryDial(iso2: "KM", dialCode: "269", nameFr: "Comores", nameEn: "Comoros", namePt: "Comores"),
  CountryDial(iso2: "CG", dialCode: "242", nameFr: "Congo", nameEn: "Congo", namePt: "Congo"),
  CountryDial(iso2: "CD", dialCode: "243", nameFr: "Congo (RDC)", nameEn: "DR Congo", namePt: "RD Congo"),
  CountryDial(iso2: "KP", dialCode: "850", nameFr: "Corée du Nord", nameEn: "North Korea", namePt: "Coreia do Norte"),
  CountryDial(iso2: "KR", dialCode: "82", nameFr: "Corée du Sud", nameEn: "South Korea", namePt: "Coreia do Sul"),
  CountryDial(iso2: "CR", dialCode: "506", nameFr: "Costa Rica", nameEn: "Costa Rica", namePt: "Costa Rica"),
  CountryDial(iso2: "CI", dialCode: "225", nameFr: "Côte d'Ivoire", nameEn: "Ivory Coast", namePt: "Costa do Marfim"),
  CountryDial(iso2: "HR", dialCode: "385", nameFr: "Croatie", nameEn: "Croatia", namePt: "Croácia"),
  CountryDial(iso2: "CU", dialCode: "53", nameFr: "Cuba", nameEn: "Cuba", namePt: "Cuba"),
  CountryDial(iso2: "CW", dialCode: "599", nameFr: "Curaçao", nameEn: "Curaçao", namePt: "Curaçao"),
  CountryDial(iso2: "DK", dialCode: "45", nameFr: "Danemark", nameEn: "Denmark", namePt: "Dinamarca"),
  CountryDial(iso2: "DJ", dialCode: "253", nameFr: "Djibouti", nameEn: "Djibouti", namePt: "Djibuti"),
  CountryDial(iso2: "DM", dialCode: "1767", nameFr: "Dominique", nameEn: "Dominica", namePt: "Dominica"),
  CountryDial(iso2: "EG", dialCode: "20", nameFr: "Égypte", nameEn: "Egypt", namePt: "Egito"),
  CountryDial(iso2: "AE", dialCode: "971", nameFr: "Émirats arabes unis", nameEn: "United Arab Emirates", namePt: "Emirados Árabes Unidos"),
  CountryDial(iso2: "EC", dialCode: "593", nameFr: "Équateur", nameEn: "Ecuador", namePt: "Equador"),
  CountryDial(iso2: "ER", dialCode: "291", nameFr: "Érythrée", nameEn: "Eritrea", namePt: "Eritreia"),
  CountryDial(iso2: "ES", dialCode: "34", nameFr: "Espagne", nameEn: "Spain", namePt: "Espanha"),
  CountryDial(iso2: "EE", dialCode: "372", nameFr: "Estonie", nameEn: "Estonia", namePt: "Estónia"),
  CountryDial(iso2: "SZ", dialCode: "268", nameFr: "Eswatini", nameEn: "Eswatini", namePt: "Essuatíni"),
  CountryDial(iso2: "US", dialCode: "1", nameFr: "États-Unis", nameEn: "United States", namePt: "Estados Unidos"),
  CountryDial(iso2: "ET", dialCode: "251", nameFr: "Éthiopie", nameEn: "Ethiopia", namePt: "Etiópia"),
  CountryDial(iso2: "FJ", dialCode: "679", nameFr: "Fidji", nameEn: "Fiji", namePt: "Fiji"),
  CountryDial(iso2: "FI", dialCode: "358", nameFr: "Finlande", nameEn: "Finland", namePt: "Finlândia"),
  CountryDial(iso2: "FR", dialCode: "33", nameFr: "France", nameEn: "France", namePt: "França"),
  CountryDial(iso2: "GA", dialCode: "241", nameFr: "Gabon", nameEn: "Gabon", namePt: "Gabão"),
  CountryDial(iso2: "GM", dialCode: "220", nameFr: "Gambie", nameEn: "Gambia", namePt: "Gâmbia"),
  CountryDial(iso2: "GE", dialCode: "995", nameFr: "Géorgie", nameEn: "Georgia", namePt: "Geórgia"),
  CountryDial(iso2: "GH", dialCode: "233", nameFr: "Ghana", nameEn: "Ghana", namePt: "Gana"),
  CountryDial(iso2: "GI", dialCode: "350", nameFr: "Gibraltar", nameEn: "Gibraltar", namePt: "Gibraltar"),
  CountryDial(iso2: "GR", dialCode: "30", nameFr: "Grèce", nameEn: "Greece", namePt: "Grécia"),
  CountryDial(iso2: "GD", dialCode: "1473", nameFr: "Grenade", nameEn: "Grenada", namePt: "Granada"),
  CountryDial(iso2: "GL", dialCode: "299", nameFr: "Groenland", nameEn: "Greenland", namePt: "Gronelândia"),
  CountryDial(iso2: "GP", dialCode: "590", nameFr: "Guadeloupe", nameEn: "Guadeloupe", namePt: "Guadalupe"),
  CountryDial(iso2: "GU", dialCode: "1671", nameFr: "Guam", nameEn: "Guam", namePt: "Guam"),
  CountryDial(iso2: "GT", dialCode: "502", nameFr: "Guatemala", nameEn: "Guatemala", namePt: "Guatemala"),
  CountryDial(iso2: "GN", dialCode: "224", nameFr: "Guinée", nameEn: "Guinea", namePt: "Guiné"),
  CountryDial(iso2: "GQ", dialCode: "240", nameFr: "Guinée équatoriale", nameEn: "Equatorial Guinea", namePt: "Guiné Equatorial"),
  CountryDial(iso2: "GW", dialCode: "245", nameFr: "Guinée-Bissau", nameEn: "Guinea-Bissau", namePt: "Guiné-Bissau"),
  CountryDial(iso2: "GY", dialCode: "592", nameFr: "Guyana", nameEn: "Guyana", namePt: "Guiana"),
  CountryDial(iso2: "GF", dialCode: "594", nameFr: "Guyane", nameEn: "French Guiana", namePt: "Guiana Francesa"),
  CountryDial(iso2: "HT", dialCode: "509", nameFr: "Haïti", nameEn: "Haiti", namePt: "Haiti"),
  CountryDial(iso2: "HN", dialCode: "504", nameFr: "Honduras", nameEn: "Honduras", namePt: "Honduras"),
  CountryDial(iso2: "HK", dialCode: "852", nameFr: "Hong Kong", nameEn: "Hong Kong", namePt: "Hong Kong"),
  CountryDial(iso2: "HU", dialCode: "36", nameFr: "Hongrie", nameEn: "Hungary", namePt: "Hungria"),
  CountryDial(iso2: "IN", dialCode: "91", nameFr: "Inde", nameEn: "India", namePt: "Índia"),
  CountryDial(iso2: "ID", dialCode: "62", nameFr: "Indonésie", nameEn: "Indonesia", namePt: "Indonésia"),
  CountryDial(iso2: "IQ", dialCode: "964", nameFr: "Irak", nameEn: "Iraq", namePt: "Iraque"),
  CountryDial(iso2: "IR", dialCode: "98", nameFr: "Iran", nameEn: "Iran", namePt: "Irão"),
  CountryDial(iso2: "IE", dialCode: "353", nameFr: "Irlande", nameEn: "Ireland", namePt: "Irlanda"),
  CountryDial(iso2: "IS", dialCode: "354", nameFr: "Islande", nameEn: "Iceland", namePt: "Islândia"),
  CountryDial(iso2: "IL", dialCode: "972", nameFr: "Israël", nameEn: "Israel", namePt: "Israel"),
  CountryDial(iso2: "IT", dialCode: "39", nameFr: "Italie", nameEn: "Italy", namePt: "Itália"),
  CountryDial(iso2: "JM", dialCode: "1876", nameFr: "Jamaïque", nameEn: "Jamaica", namePt: "Jamaica"),
  CountryDial(iso2: "JP", dialCode: "81", nameFr: "Japon", nameEn: "Japan", namePt: "Japão"),
  CountryDial(iso2: "JO", dialCode: "962", nameFr: "Jordanie", nameEn: "Jordan", namePt: "Jordânia"),
  CountryDial(iso2: "KZ", dialCode: "7", nameFr: "Kazakhstan", nameEn: "Kazakhstan", namePt: "Cazaquistão"),
  CountryDial(iso2: "KE", dialCode: "254", nameFr: "Kenya", nameEn: "Kenya", namePt: "Quénia"),
  CountryDial(iso2: "KG", dialCode: "996", nameFr: "Kirghizistan", nameEn: "Kyrgyzstan", namePt: "Quirguistão"),
  CountryDial(iso2: "KI", dialCode: "686", nameFr: "Kiribati", nameEn: "Kiribati", namePt: "Quiribáti"),
  CountryDial(iso2: "KW", dialCode: "965", nameFr: "Koweït", nameEn: "Kuwait", namePt: "Kuwait"),
  CountryDial(iso2: "LA", dialCode: "856", nameFr: "Laos", nameEn: "Laos", namePt: "Laos"),
  CountryDial(iso2: "LS", dialCode: "266", nameFr: "Lesotho", nameEn: "Lesotho", namePt: "Lesoto"),
  CountryDial(iso2: "LV", dialCode: "371", nameFr: "Lettonie", nameEn: "Latvia", namePt: "Letónia"),
  CountryDial(iso2: "LB", dialCode: "961", nameFr: "Liban", nameEn: "Lebanon", namePt: "Líbano"),
  CountryDial(iso2: "LR", dialCode: "231", nameFr: "Liberia", nameEn: "Liberia", namePt: "Libéria"),
  CountryDial(iso2: "LY", dialCode: "218", nameFr: "Libye", nameEn: "Libya", namePt: "Líbia"),
  CountryDial(iso2: "LI", dialCode: "423", nameFr: "Liechtenstein", nameEn: "Liechtenstein", namePt: "Listenstaine"),
  CountryDial(iso2: "LT", dialCode: "370", nameFr: "Lituanie", nameEn: "Lithuania", namePt: "Lituânia"),
  CountryDial(iso2: "LU", dialCode: "352", nameFr: "Luxembourg", nameEn: "Luxembourg", namePt: "Luxemburgo"),
  CountryDial(iso2: "MO", dialCode: "853", nameFr: "Macao", nameEn: "Macau", namePt: "Macau"),
  CountryDial(iso2: "MK", dialCode: "389", nameFr: "Macédoine du Nord", nameEn: "North Macedonia", namePt: "Macedónia do Norte"),
  CountryDial(iso2: "MG", dialCode: "261", nameFr: "Madagascar", nameEn: "Madagascar", namePt: "Madagáscar"),
  CountryDial(iso2: "MY", dialCode: "60", nameFr: "Malaisie", nameEn: "Malaysia", namePt: "Malásia"),
  CountryDial(iso2: "MW", dialCode: "265", nameFr: "Malawi", nameEn: "Malawi", namePt: "Maláui"),
  CountryDial(iso2: "MV", dialCode: "960", nameFr: "Maldives", nameEn: "Maldives", namePt: "Maldivas"),
  CountryDial(iso2: "ML", dialCode: "223", nameFr: "Mali", nameEn: "Mali", namePt: "Mali"),
  CountryDial(iso2: "MT", dialCode: "356", nameFr: "Malte", nameEn: "Malta", namePt: "Malta"),
  CountryDial(iso2: "MA", dialCode: "212", nameFr: "Maroc", nameEn: "Morocco", namePt: "Marrocos"),
  CountryDial(iso2: "MQ", dialCode: "596", nameFr: "Martinique", nameEn: "Martinique", namePt: "Martinica"),
  CountryDial(iso2: "MU", dialCode: "230", nameFr: "Maurice", nameEn: "Mauritius", namePt: "Maurícia"),
  CountryDial(iso2: "MR", dialCode: "222", nameFr: "Mauritanie", nameEn: "Mauritania", namePt: "Mauritânia"),
  CountryDial(iso2: "YT", dialCode: "262", nameFr: "Mayotte", nameEn: "Mayotte", namePt: "Maiote"),
  CountryDial(iso2: "MX", dialCode: "52", nameFr: "Mexique", nameEn: "Mexico", namePt: "México"),
  CountryDial(iso2: "FM", dialCode: "691", nameFr: "Micronésie", nameEn: "Micronesia", namePt: "Micronésia"),
  CountryDial(iso2: "MD", dialCode: "373", nameFr: "Moldavie", nameEn: "Moldova", namePt: "Moldávia"),
  CountryDial(iso2: "MC", dialCode: "377", nameFr: "Monaco", nameEn: "Monaco", namePt: "Mónaco"),
  CountryDial(iso2: "MN", dialCode: "976", nameFr: "Mongolie", nameEn: "Mongolia", namePt: "Mongólia"),
  CountryDial(iso2: "ME", dialCode: "382", nameFr: "Monténégro", nameEn: "Montenegro", namePt: "Montenegro"),
  CountryDial(iso2: "MS", dialCode: "1664", nameFr: "Montserrat", nameEn: "Montserrat", namePt: "Monserrate"),
  CountryDial(iso2: "MZ", dialCode: "258", nameFr: "Mozambique", nameEn: "Mozambique", namePt: "Moçambique"),
  CountryDial(iso2: "NA", dialCode: "264", nameFr: "Namibie", nameEn: "Namibia", namePt: "Namíbia"),
  CountryDial(iso2: "NR", dialCode: "674", nameFr: "Nauru", nameEn: "Nauru", namePt: "Nauru"),
  CountryDial(iso2: "NP", dialCode: "977", nameFr: "Népal", nameEn: "Nepal", namePt: "Nepal"),
  CountryDial(iso2: "NI", dialCode: "505", nameFr: "Nicaragua", nameEn: "Nicaragua", namePt: "Nicarágua"),
  CountryDial(iso2: "NE", dialCode: "227", nameFr: "Niger", nameEn: "Niger", namePt: "Níger"),
  CountryDial(iso2: "NG", dialCode: "234", nameFr: "Nigeria", nameEn: "Nigeria", namePt: "Nigéria"),
  CountryDial(iso2: "NO", dialCode: "47", nameFr: "Norvège", nameEn: "Norway", namePt: "Noruega"),
  CountryDial(iso2: "NC", dialCode: "687", nameFr: "Nouvelle-Calédonie", nameEn: "New Caledonia", namePt: "Nova Caledónia"),
  CountryDial(iso2: "NZ", dialCode: "64", nameFr: "Nouvelle-Zélande", nameEn: "New Zealand", namePt: "Nova Zelândia"),
  CountryDial(iso2: "OM", dialCode: "968", nameFr: "Oman", nameEn: "Oman", namePt: "Omã"),
  CountryDial(iso2: "UG", dialCode: "256", nameFr: "Ouganda", nameEn: "Uganda", namePt: "Uganda"),
  CountryDial(iso2: "UZ", dialCode: "998", nameFr: "Ouzbékistan", nameEn: "Uzbekistan", namePt: "Uzbequistão"),
  CountryDial(iso2: "PK", dialCode: "92", nameFr: "Pakistan", nameEn: "Pakistan", namePt: "Paquistão"),
  CountryDial(iso2: "PW", dialCode: "680", nameFr: "Palaos", nameEn: "Palau", namePt: "Palau"),
  CountryDial(iso2: "PS", dialCode: "970", nameFr: "Palestine", nameEn: "Palestine", namePt: "Palestina"),
  CountryDial(iso2: "PA", dialCode: "507", nameFr: "Panama", nameEn: "Panama", namePt: "Panamá"),
  CountryDial(iso2: "PG", dialCode: "675", nameFr: "Papouasie-Nouvelle-Guinée", nameEn: "Papua New Guinea", namePt: "Papua-Nova Guiné"),
  CountryDial(iso2: "PY", dialCode: "595", nameFr: "Paraguay", nameEn: "Paraguay", namePt: "Paraguai"),
  CountryDial(iso2: "NL", dialCode: "31", nameFr: "Pays-Bas", nameEn: "Netherlands", namePt: "Países Baixos"),
  CountryDial(iso2: "PE", dialCode: "51", nameFr: "Pérou", nameEn: "Peru", namePt: "Peru"),
  CountryDial(iso2: "PH", dialCode: "63", nameFr: "Philippines", nameEn: "Philippines", namePt: "Filipinas"),
  CountryDial(iso2: "PL", dialCode: "48", nameFr: "Pologne", nameEn: "Poland", namePt: "Polónia"),
  CountryDial(iso2: "PF", dialCode: "689", nameFr: "Polynésie française", nameEn: "French Polynesia", namePt: "Polinésia Francesa"),
  CountryDial(iso2: "PR", dialCode: "1787", nameFr: "Porto Rico", nameEn: "Puerto Rico", namePt: "Porto Rico"),
  CountryDial(iso2: "PT", dialCode: "351", nameFr: "Portugal", nameEn: "Portugal", namePt: "Portugal"),
  CountryDial(iso2: "QA", dialCode: "974", nameFr: "Qatar", nameEn: "Qatar", namePt: "Catar"),
  CountryDial(iso2: "CF", dialCode: "236", nameFr: "République centrafricaine", nameEn: "Central African Republic", namePt: "República Centro-Africana"),
  CountryDial(iso2: "DO", dialCode: "1809", nameFr: "République dominicaine", nameEn: "Dominican Republic", namePt: "República Dominicana"),
  CountryDial(iso2: "CZ", dialCode: "420", nameFr: "République tchèque", nameEn: "Czech Republic", namePt: "Chéquia"),
  CountryDial(iso2: "RE", dialCode: "262", nameFr: "La Réunion", nameEn: "Réunion", namePt: "Reunião"),
  CountryDial(iso2: "RO", dialCode: "40", nameFr: "Roumanie", nameEn: "Romania", namePt: "Roménia"),
  CountryDial(iso2: "GB", dialCode: "44", nameFr: "Royaume-Uni", nameEn: "United Kingdom", namePt: "Reino Unido"),
  CountryDial(iso2: "RU", dialCode: "7", nameFr: "Russie", nameEn: "Russia", namePt: "Rússia"),
  CountryDial(iso2: "RW", dialCode: "250", nameFr: "Rwanda", nameEn: "Rwanda", namePt: "Ruanda"),
  CountryDial(iso2: "EH", dialCode: "212", nameFr: "Sahara occidental", nameEn: "Western Sahara", namePt: "Saara Ocidental"),
  CountryDial(iso2: "KN", dialCode: "1869", nameFr: "Saint-Kitts-et-Nevis", nameEn: "Saint Kitts and Nevis", namePt: "São Cristóvão e Neves"),
  CountryDial(iso2: "SM", dialCode: "378", nameFr: "Saint-Marin", nameEn: "San Marino", namePt: "San Marino"),
  CountryDial(iso2: "SX", dialCode: "1721", nameFr: "Saint-Martin", nameEn: "Sint Maarten", namePt: "Sint Maarten"),
  CountryDial(iso2: "PM", dialCode: "508", nameFr: "Saint-Pierre-et-Miquelon", nameEn: "Saint Pierre and Miquelon", namePt: "Saint Pierre e Miquelon"),
  CountryDial(iso2: "VC", dialCode: "1784", nameFr: "Saint-Vincent-et-les-Grenadines", nameEn: "Saint Vincent and the Grenadines", namePt: "São Vicente e Granadinas"),
  CountryDial(iso2: "LC", dialCode: "1758", nameFr: "Sainte-Lucie", nameEn: "Saint Lucia", namePt: "Santa Lúcia"),
  CountryDial(iso2: "SV", dialCode: "503", nameFr: "Salvador", nameEn: "El Salvador", namePt: "El Salvador"),
  CountryDial(iso2: "WS", dialCode: "685", nameFr: "Samoa", nameEn: "Samoa", namePt: "Samoa"),
  CountryDial(iso2: "AS", dialCode: "1684", nameFr: "Samoa américaines", nameEn: "American Samoa", namePt: "Samoa Americana"),
  CountryDial(iso2: "ST", dialCode: "239", nameFr: "Sao Tomé-et-Principe", nameEn: "Sao Tome and Principe", namePt: "São Tomé e Príncipe"),
  CountryDial(iso2: "SN", dialCode: "221", nameFr: "Sénégal", nameEn: "Senegal", namePt: "Senegal"),
  CountryDial(iso2: "RS", dialCode: "381", nameFr: "Serbie", nameEn: "Serbia", namePt: "Sérvia"),
  CountryDial(iso2: "SC", dialCode: "248", nameFr: "Seychelles", nameEn: "Seychelles", namePt: "Seicheles"),
  CountryDial(iso2: "SL", dialCode: "232", nameFr: "Sierra Leone", nameEn: "Sierra Leone", namePt: "Serra Leoa"),
  CountryDial(iso2: "SG", dialCode: "65", nameFr: "Singapour", nameEn: "Singapore", namePt: "Singapura"),
  CountryDial(iso2: "SK", dialCode: "421", nameFr: "Slovaquie", nameEn: "Slovakia", namePt: "Eslováquia"),
  CountryDial(iso2: "SI", dialCode: "386", nameFr: "Slovénie", nameEn: "Slovenia", namePt: "Eslovénia"),
  CountryDial(iso2: "SO", dialCode: "252", nameFr: "Somalie", nameEn: "Somalia", namePt: "Somália"),
  CountryDial(iso2: "SD", dialCode: "249", nameFr: "Soudan", nameEn: "Sudan", namePt: "Sudão"),
  CountryDial(iso2: "SS", dialCode: "211", nameFr: "Soudan du Sud", nameEn: "South Sudan", namePt: "Sudão do Sul"),
  CountryDial(iso2: "LK", dialCode: "94", nameFr: "Sri Lanka", nameEn: "Sri Lanka", namePt: "Sri Lanca"),
  CountryDial(iso2: "SE", dialCode: "46", nameFr: "Suède", nameEn: "Sweden", namePt: "Suécia"),
  CountryDial(iso2: "CH", dialCode: "41", nameFr: "Suisse", nameEn: "Switzerland", namePt: "Suíça"),
  CountryDial(iso2: "SR", dialCode: "597", nameFr: "Suriname", nameEn: "Suriname", namePt: "Suriname"),
  CountryDial(iso2: "SY", dialCode: "963", nameFr: "Syrie", nameEn: "Syria", namePt: "Síria"),
  CountryDial(iso2: "TJ", dialCode: "992", nameFr: "Tadjikistan", nameEn: "Tajikistan", namePt: "Tajiquistão"),
  CountryDial(iso2: "TW", dialCode: "886", nameFr: "Taïwan", nameEn: "Taiwan", namePt: "Taiwan"),
  CountryDial(iso2: "TZ", dialCode: "255", nameFr: "Tanzanie", nameEn: "Tanzania", namePt: "Tanzânia"),
  CountryDial(iso2: "TD", dialCode: "235", nameFr: "Tchad", nameEn: "Chad", namePt: "Chade"),
  CountryDial(iso2: "TF", dialCode: "262", nameFr: "Terres australes françaises", nameEn: "French Southern Territories", namePt: "Terras Austrais Francesas"),
  CountryDial(iso2: "TH", dialCode: "66", nameFr: "Thaïlande", nameEn: "Thailand", namePt: "Tailândia"),
  CountryDial(iso2: "TL", dialCode: "670", nameFr: "Timor oriental", nameEn: "Timor-Leste", namePt: "Timor-Leste"),
  CountryDial(iso2: "TG", dialCode: "228", nameFr: "Togo", nameEn: "Togo", namePt: "Togo"),
  CountryDial(iso2: "TO", dialCode: "676", nameFr: "Tonga", nameEn: "Tonga", namePt: "Tonga"),
  CountryDial(iso2: "TT", dialCode: "1868", nameFr: "Trinité-et-Tobago", nameEn: "Trinidad and Tobago", namePt: "Trindade e Tobago"),
  CountryDial(iso2: "TN", dialCode: "216", nameFr: "Tunisie", nameEn: "Tunisia", namePt: "Tunísia"),
  CountryDial(iso2: "TM", dialCode: "993", nameFr: "Turkménistan", nameEn: "Turkmenistan", namePt: "Turquemenistão"),
  CountryDial(iso2: "TR", dialCode: "90", nameFr: "Turquie", nameEn: "Turkey", namePt: "Turquia"),
  CountryDial(iso2: "TV", dialCode: "688", nameFr: "Tuvalu", nameEn: "Tuvalu", namePt: "Tuvalu"),
  CountryDial(iso2: "UA", dialCode: "380", nameFr: "Ukraine", nameEn: "Ukraine", namePt: "Ucrânia"),
  CountryDial(iso2: "UY", dialCode: "598", nameFr: "Uruguay", nameEn: "Uruguay", namePt: "Uruguai"),
  CountryDial(iso2: "VU", dialCode: "678", nameFr: "Vanuatu", nameEn: "Vanuatu", namePt: "Vanuatu"),
  CountryDial(iso2: "VA", dialCode: "379", nameFr: "Vatican", nameEn: "Vatican", namePt: "Vaticano"),
  CountryDial(iso2: "VE", dialCode: "58", nameFr: "Venezuela", nameEn: "Venezuela", namePt: "Venezuela"),
  CountryDial(iso2: "VN", dialCode: "84", nameFr: "Viêt Nam", nameEn: "Vietnam", namePt: "Vietname"),
  CountryDial(iso2: "YE", dialCode: "967", nameFr: "Yémen", nameEn: "Yemen", namePt: "Iémen"),
  CountryDial(iso2: "ZM", dialCode: "260", nameFr: "Zambie", nameEn: "Zambia", namePt: "Zâmbia"),
  CountryDial(iso2: "ZW", dialCode: "263", nameFr: "Zimbabwe", nameEn: "Zimbabwe", namePt: "Zimbábue"),
];

CountryDial countryByIso(String iso2) {
  final upper = iso2.toUpperCase();
  return kCountryDials.firstWhere(
    (c) => c.iso2 == upper,
    orElse: () => kCountryDials.firstWhere((c) => c.iso2 == kDefaultCountryIso),
  );
}

/// Priorise AO / CD / CG en tête de liste pour les écoles Klambo.
List<CountryDial> prioritizedCountries() {
  const priority = ["AO", "CD", "CG", "FR", "PT", "BE", "BR"];
  final rest = kCountryDials.where((c) => !priority.contains(c.iso2)).toList()
    ..sort((a, b) => a.nameFr.compareTo(b.nameFr));
  return [
    for (final iso in priority) countryByIso(iso),
    ...rest,
  ];
}

/// Compose E.164 : indicatif + national (retire 0 local de tête).
String composeE164({
  required String dialCode,
  required String nationalInput,
}) {
  var national = nationalInput.replaceAll(RegExp(r"\D"), "");
  if (national.startsWith("00")) {
    return "+${national.substring(2)}";
  }
  // Si l'utilisateur colle déjà un numéro international
  if (national.startsWith(dialCode) && national.length > dialCode.length + 5) {
    return "+$national";
  }
  while (national.startsWith("0")) {
    national = national.substring(1);
  }
  return "+$dialCode$national";
}
