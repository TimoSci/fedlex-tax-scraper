
# Hardcoded list of Swiss federal tax laws to scrape, keyed by SR number.

KNOWN_LAWS = [
  # --- Direct taxes ---
  {
    name: "DBG",
    sr: "642.11",
    cc: "1991/1184_1184_1184",
    description: "Bundesgesetz über die direkte Bundessteuer"
  },
  {
    name: "DBV",
    sr: "642.118",
    cc: "1993/1341_1341_1341",
    description: "Verordnung über die direkte Bundessteuer"
  },
  {
    name: "Berufskostenverordnung",
    sr: "642.118.1",
    cc: "1993/1346_1346_1346",
    description: "Verordnung über den Abzug der Berufskosten unselbständig Erwerbstätiger"
  },
  {
    name: "EFV",
    sr: "642.116",
    cc: "2019/415",
    description: "Verordnung über den Abzug von Zinsen auf Eigenkapital (Eigenfinanzierungsverordnung)"
  },
  {
    name: "Patentboxverordnung",
    sr: "642.117.1",
    cc: "2019/413",
    description: "Verordnung über die Patentbox"
  },
  {
    name: "Zinssatzverordnung-DBG",
    sr: "642.118.2",
    cc: "2018/781",
    description: "Verordnung über die anwendbaren Zinssätze bei der direkten Bundessteuer"
  },
  {
    name: "StHG",
    sr: "642.14",
    cc: "1991/1256_1256_1256",
    description: "Bundesgesetz über die Harmonisierung der direkten Steuern der Kantone und Gemeinden"
  },
  {
    name: "StHV",
    sr: "642.141",
    cc: "1994/2417_2417_2417",
    description: "Verordnung über die Anwendung des Steuerharmonisierungsgesetzes"
  },

  # --- VAT ---
  {
    name: "MWSTG",
    sr: "641.20",
    cc: "2009/615",
    description: "Bundesgesetz über die Mehrwertsteuer"
  },
  {
    name: "MWSTV",
    sr: "641.201",
    cc: "2009/854",
    description: "Mehrwertsteuerverordnung"
  },
  {
    name: "MWSTV-EFD",
    sr: "641.201.1",
    cc: "2021/714",
    description: "Verordnung des EFD über die Mehrwertsteuer"
  },

  # --- Withholding tax ---
  {
    name: "VStG",
    sr: "642.21",
    cc: "1966/371_385_384",
    description: "Bundesgesetz über die Verrechnungssteuer"
  },
  {
    name: "VStV",
    sr: "642.211",
    cc: "1966/386_400_399",
    description: "Verrechnungssteuerverordnung"
  },

  # --- Stamp duties ---
  {
    name: "StG",
    sr: "641.10",
    cc: "1974/11_11_11",
    description: "Bundesgesetz über die Stempelabgaben"
  },
  {
    name: "StV",
    sr: "641.101",
    cc: "1974/15_15_15",
    description: "Verordnung über die Stempelabgaben"
  },

  # --- Minimum tax (OECD Pillar Two) ---
  {
    name: "EStG",
    sr: "642.23",
    cc: "2023/687",
    description: "Bundesgesetz über die Ergänzungssteuer (Mindestbesteuerungsgesetz)"
  },
  {
    name: "MindStV",
    sr: "642.234",
    cc: "2023/690",
    description: "Mindestbesteuerungsverordnung"
  },

  # --- Special consumption taxes ---
  {
    name: "BierStG",
    sr: "641.411",
    cc: "1998/502_502_502",
    description: "Bundesgesetz über die Biersteuer"
  },
  {
    name: "TbStG",
    sr: "641.31",
    cc: "1969/645_665_649",
    description: "Bundesgesetz über die Tabakbesteuerung"
  },
  {
    name: "TbStV",
    sr: "641.311",
    cc: "1970/210_214_213",
    description: "Verordnung über die Tabakbesteuerung"
  },
  {
    name: "SpiritG",
    sr: "680",
    cc: "2016/188",
    description: "Bundesgesetz über die Besteuerung von Spirituosen"
  },
  {
    name: "MinöStG",
    sr: "641.61",
    cc: "1996/3371_3371_3371",
    description: "Bundesgesetz über die Mineralölsteuer"
  },
  {
    name: "MinöStV",
    sr: "641.611",
    cc: "1997/790_790_790",
    description: "Mineralölsteuerverordnung"
  },
  {
    name: "NSAG",
    sr: "741.71",
    cc: "2012/276",
    description: "Bundesgesetz über die Nationalstrassenabgabe"
  },
  {
    name: "SVAG",
    sr: "641.81",
    cc: "2000/354",
    description: "Bundesgesetz über eine leistungsabhängige Schwerverkehrsabgabe"
  },
  {
    name: "SVAV",
    sr: "641.811",
    cc: "2000/358",
    description: "Verordnung über eine leistungsabhängige Schwerverkehrsabgabe"
  },
  {
    name: "CO2-Gesetz",
    sr: "641.71",
    cc: "2012/855",
    description: "Bundesgesetz über die Reduktion von CO2-Emissionen"
  },

  # --- International tax / administrative assistance ---
  {
    name: "StAhiG",
    sr: "651.1",
    cc: "2013/231",
    description: "Bundesgesetz über die internationale Amtshilfe in Steuersachen"
  },
  {
    name: "StAhiV",
    sr: "651.11",
    cc: "2013/232",
    description: "Verordnung über die internationale Amtshilfe in Steuersachen"
  },
  {
    name: "AIAG",
    sr: "653.1",
    cc: "2016/182",
    description: "Bundesgesetz über den automatischen Informationsaustausch in Steuersachen"
  },
  {
    name: "AIAV",
    sr: "653.11",
    cc: "2016/181",
    description: "Verordnung über den automatischen Informationsaustausch in Steuersachen"
  },
  {
    name: "StADG",
    sr: "651.4",
    cc: "2021/703",
    description: "Bundesgesetz über die Durchführung von internationalen Abkommen im Steuerbereich"
  },

  # --- Procedural / enforcement ---
  {
    name: "VStrR",
    sr: "313.0",
    cc: "1974/1857_1857_1857",
    description: "Bundesgesetz über das Verwaltungsstrafrecht"
  },
].freeze
