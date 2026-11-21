enum AppLanguage {
  en('en', 'EN', 'English'),
  hi('hi', 'हिं', 'हिन्दी'),
  kn('kn', 'ಕನ್', 'ಕನ್ನಡ');

  const AppLanguage(this.code, this.shortLabel, this.displayName);

  final String code;
  final String shortLabel;
  final String displayName;

  static AppLanguage fromCode(String? code) {
    return AppLanguage.values.firstWhere(
      (lang) => lang.code == code,
      orElse: () => AppLanguage.hi,
    );
  }
}

class AppStrings {
  AppStrings._(this.lang);

  final AppLanguage lang;

  static AppStrings of(AppLanguage lang) => AppStrings._(lang);

  String _pick({required String en, required String hi, required String kn}) {
    switch (lang) {
      case AppLanguage.en:
        return en;
      case AppLanguage.hi:
        return hi;
      case AppLanguage.kn:
        return kn;
    }
  }

  String get appTitle => 'Asha Vaani';
  String get appSubtitle => _pick(
        en: 'Voice-first newborn home visit assistant',
        hi: 'नवजात गृह भेंट के लिए वॉइस सहायक',
        kn: 'ನವಜಾತ ಶಿಶು ಮನೆ ಭೇಟಿಗೆ ಧ್ವನಿ ಸಹಾಯಕ',
      );

  // Login & Backend Settings
  String get selectWorker => _pick(
        en: 'Select ASHA Worker',
        hi: 'आशा कार्यकर्ता चुनें',
        kn: 'ಆಶಾ ಕಾರ್ಯಕರ್ತೆಯನ್ನು ಆಯ್ಕೆಮಾಡಿ',
      );
  String get serverSettings => _pick(
        en: 'Server Settings',
        hi: 'सर्वर सेटिंग्स',
        kn: 'ಸರ್ವರ್ ಸೆಟ್ಟಿಂಗ್‌ಗಳು',
      );
  String get backendUrlLabel => _pick(
        en: 'Backend URL',
        hi: 'बैकएंड URL',
        kn: 'ಬ್ಯಾಕೆಂಡ್ URL',
      );
  String get testConnection => _pick(
        en: 'Test Connection',
        hi: 'कनेक्शन जांचें',
        kn: 'ಸಂಪರ್ಕ ಪರೀಕ್ಷಿಸಿ',
      );
  String get connectionOk => _pick(
        en: 'Connected to backend',
        hi: 'सर्वर से जुड़ा है',
        kn: 'ಸರ್ವರ್ ಸಂಪರ್ಕ ಯಶಸ್ವಿಯಾಗಿದೆ',
      );
  String get connectionFailed => _pick(
        en: 'Could not reach server',
        hi: 'सर्वर से जुड़ नहीं पाया',
        kn: 'ಸರ್ವರ್ ಸಂಪರ್ಕ ಸಾಧ್ಯವಾಗಲಿಲ್ಲ',
      );

  // Home Navigation (V2 4-tab shell)
  String get homeTab => _pick(
        en: 'Home',
        hi: 'होम',
        kn: 'ಮುಖಪುಟ',
      );
  String get beneficiariesTab => _pick(
        en: 'Beneficiaries',
        hi: 'लाभार्थी',
        kn: 'ಫಲಾನುಭವಿಗಳು',
      );
  String get insightsTab => _pick(
        en: 'Insights',
        hi: 'आंकड़े',
        kn: 'ಅಂಕಿಅಂಶ',
      );
  String get settingsTab => _pick(
        en: 'Settings',
        hi: 'सेटिंग्स',
        kn: 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು',
      );
  String get savedVisitsTab => _pick(
        en: 'Saved Visits',
        hi: 'सहेजे गए रिकॉर्ड',
        kn: 'ಉಳಿಸಿದ ಭೇಟಿಗಳು',
      );
  String get switchWorker => _pick(
        en: 'Switch Worker',
        hi: 'कार्यकर्ता बदलें',
        kn: 'ಕಾರ್ಯಕರ್ತೆ ಬದಲಿಸಿ',
      );

  // Lock / Sign-In (V2 §3.1)
  String get workerCodeLabel => _pick(
        en: 'Worker code',
        hi: 'कार्यकर्ता कोड',
        kn: 'ಕಾರ್ಯಕರ್ತೆ ಕೋಡ್',
      );
  String get workerCodeHint => _pick(
        en: 'e.g. asha_001',
        hi: 'जैसे asha_001',
        kn: 'ಉದಾ. asha_001',
      );
  String get pinLabel => _pick(
        en: '4-digit PIN',
        hi: '4 अंकों का पिन',
        kn: '4 ಅಂಕಿಯ ಪಿನ್',
      );
  String get pinHint => _pick(
        en: 'Enter PIN',
        hi: 'पिन दर्ज करें',
        kn: 'ಪಿನ್ ನಮೂದಿಸಿ',
      );
  String get signInAction => _pick(
        en: 'Sign in',
        hi: 'साइन इन करें',
        kn: 'ಸೈನ್ ಇನ್ ಮಾಡಿ',
      );
  String get unlockAction => _pick(
        en: 'Unlock',
        hi: 'अनलॉक करें',
        kn: 'ಅನ್‌ಲಾಕ್ ಮಾಡಿ',
      );
  String get pinLockChip => _pick(
        en: 'PIN lock active',
        hi: 'पिन लॉक सक्रिय',
        kn: 'ಪಿನ್ ಲಾಕ್ ಸಕ್ರಿಯ',
      );
  String get pinLockOfflineChip => _pick(
        en: 'PIN lock · Offline ready',
        hi: 'पिन लॉक · ऑफ़लाइन तैयार',
        kn: 'ಪಿನ್ ಲಾಕ್ · ಆಫ್‌ಲೈನ್ ಸಿದ್ಧ',
      );
  String get demoPinHint => _pick(
        en: 'Demo accounts: asha_001, asha_002 (PIN 1234)',
        hi: 'डेमो खाता: asha_001, asha_002 (पिन 1234)',
        kn: 'ಡೆಮೊ ಖಾತೆ: asha_001, asha_002 (ಪಿನ್ 1234)',
      );
  String get switchAccountAction => _pick(
        en: 'Use another account',
        hi: 'दूसरा खाता चुनें',
        kn: 'ಬೇರೆ ಖಾತೆ ಬಳಸಿ',
      );
  String get invalidCredentialsError => _pick(
        en: 'Incorrect worker code or PIN.',
        hi: 'कार्यकर्ता कोड या पिन गलत है।',
        kn: 'ಕಾರ್ಯಕರ್ತೆ ಕೋಡ್ ಅಥವಾ ಪಿನ್ ತಪ್ಪಾಗಿದೆ.',
      );
  String get offlineFirstLoginError => _pick(
        en: 'Connect to the backend server for first sign-in.',
        hi: 'पहली बार साइन इन के लिए सर्वर से जुड़ें।',
        kn: 'ಮೊದಲ ಬಾರಿ ಸೈನ್ ಇನ್ ಮಾಡಲು ಸರ್ವರ್‌ಗೆ ಸಂಪರ್ಕಿಸಿ.',
      );
  String get lockAppAction => _pick(
        en: 'Lock app',
        hi: 'ऐप लॉक करें',
        kn: 'ಆ್ಯಪ್ ಲಾಕ್ ಮಾಡಿ',
      );
  String get signOutAction => _pick(
        en: 'Sign out',
        hi: 'साइन आउट',
        kn: 'ಸೈನ್ ಔಟ್',
      );
  String get signOutConfirmTitle => _pick(
        en: 'Sign out of this device?',
        hi: 'इस फ़ोन से साइन आउट करें?',
        kn: 'ಈ ಫೋನ್‌ನಿಂದ ಸೈನ್ ಔಟ್ ಮಾಡುವುದೇ?',
      );
  String get signOutConfirmMessage => _pick(
        en: 'Next sign-in will require internet connection to verify your worker PIN.',
        hi: 'अगली बार साइन इन करने के लिए इंटरनेट कनेक्शन की ज़रूरत होगी।',
        kn: 'ಮುಂದಿನ ಬಾರಿ ಸೈನ್ ಇನ್ ಮಾಡಲು ಇಂಟರ್ನೆಟ್ ಸಂಪರ್ಕ ಬೇಕಾಗುತ್ತದೆ.',
      );

  // Home Dashboard (V2 §3.2)
  String greeting(String name) => _pick(
        en: 'Namaste, $name',
        hi: 'नमस्ते, $name',
        kn: 'ನಮಸ್ಕಾರ, $name',
      );
  String get dueTodayLabel => _pick(
        en: 'Due today',
        hi: 'आज बकाया',
        kn: 'ಇಂದಿನ ಭೇಟಿ',
      );
  String get doneTodayLabel => _pick(
        en: 'Done today',
        hi: 'आज पूरे',
        kn: 'ಇಂದು ಪೂರ್ಣ',
      );
  String get needsAttentionLabel => _pick(
        en: 'Needs attention',
        hi: 'ध्यान आवश्यक',
        kn: 'ಗಮನ ಅಗತ್ಯ',
      );
  String get recordVisitAction => _pick(
        en: 'Record visit',
        hi: 'भेंट रिकॉर्ड करें',
        kn: 'ಭೇಟಿ ದಾಖಲಿಸಿ',
      );
  String get dueAndOverdueTitle => _pick(
        en: 'Due and overdue',
        hi: 'बाकी और बकाया भेंट',
        kn: 'ಬಾಕಿ ಇರುವ ಭೇಟಿಗಳು',
      );
  String get dueTodayStatus => _pick(
        en: 'Due today',
        hi: 'आज देय',
        kn: 'ಇಂದು ಬಾಕಿ',
      );
  String get noVisitsDueTitle => _pick(
        en: 'No visits pending right now',
        hi: 'अभी कोई भेंट बाकी नहीं है',
        kn: 'ಸದ್ಯಕ್ಕೆ ಯಾವುದೇ ಭೇಟಿ ಬಾಕಿ ಇಲ್ಲ',
      );
  String get noVisitsDueMessage => _pick(
        en: 'All assigned beneficiaries can still be opened below or from the Beneficiaries tab.',
        hi: 'आप लाभार्थी सूची खोलकर किसी भी बच्चे की भेंट रिकॉर्ड कर सकती हैं।',
        kn: 'ನೀವು ಫಲಾನುಭವಿ ಪಟ್ಟಿಯಿಂದ ಯಾವುದೇ ಮಗುವಿನ ಭೇಟಿಯನ್ನು ದಾಖಲಿಸಬಹುದು.',
      );
  String get viewBeneficiariesAction => _pick(
        en: 'Open beneficiaries',
        hi: 'लाभार्थी खोलें',
        kn: 'ಫಲಾನುಭವಿಗಳನ್ನು ತೆರೆಯಿರಿ',
      );
  String get chooseBeneficiaryTitle => _pick(
        en: 'Choose beneficiary',
        hi: 'लाभार्थी चुनें',
        kn: 'ಫಲಾನುಭವಿಯನ್ನು ಆಯ್ಕೆಮಾಡಿ',
      );
  String get syncedLabel => _pick(
        en: 'Synced',
        hi: 'सिंक है',
        kn: 'ಸಿಂಕ್ ಆಗಿದೆ',
      );
  String get offlineLabel => _pick(
        en: 'Offline',
        hi: 'ऑफ़लाइन',
        kn: 'ಆಫ್‌ಲೈನ್',
      );
  String pendingCountChip(int count) => _pick(
        en: '$count pending',
        hi: '$count बाकी',
        kn: '$count ಬಾಕಿ',
      );

  // Visit Purpose Picker (V2 §3.6, §4)
  String get selectVisitPurposeTitle => _pick(
        en: 'Select visit purpose',
        hi: 'भेंट का उद्देश्य चुनें',
        kn: 'ಭೇಟಿಯ ಉದ್ದೇಶವನ್ನು ಆಯ್ಕೆಮಾಡಿ',
      );
  String get suggestedPurposeLabel => _pick(
        en: 'Suggested visit',
        hi: 'सुझाया गया उद्देश्य',
        kn: 'ಸೂಚಿಸಲಾದ ಭೇಟಿ',
      );
  String get otherPurposesTitle => _pick(
        en: 'Other visit purposes',
        hi: 'अन्य भेंट प्रकार',
        kn: 'ಇತರ ಭೇಟಿ ಉದ್ದೇಶಗಳು',
      );
  String get continueWithPurposeAction => _pick(
        en: 'Continue',
        hi: 'आगे बढ़ें',
        kn: 'ಮುಂದುವರಿಯಿರಿ',
      );
  String get purposeVoiceHintLabel => _pick(
        en: 'Or say / type what check this is (e.g. BP check, fever)',
        hi: 'या बोलें / लिखें यह कौन सी जांच है (जैसे BP check, बुखार)',
        kn: 'ಅಥವಾ ಯಾವ ತಪಾಸಣೆ ಎಂದು ಹೇಳಿ / ಟೈಪ್ ಮಾಡಿ (ಉದಾ. BP check, ಜ್ವರ)',
      );
  String get purposeVoiceHintPlaceholder => _pick(
        en: 'e.g. BP check, ANC, fever',
        hi: 'जैसे BP check, ANC, बुखार',
        kn: 'ಉದಾ. BP check, ANC, ಜ್ವರ',
      );
  String detectedPurposeBanner(String purposeName) => _pick(
        en: 'Matched "$purposeName" from your note',
        hi: 'आपकी बात से "$purposeName" पहचाना गया',
        kn: 'ನಿಮ್ಮ ಮಾಹಿತಿಯಿಂದ "$purposeName" ಗುರುತಿಸಲಾಗಿದೆ',
      );
  String switchPurposeAction(String purposeName) => _pick(
        en: 'Use $purposeName',
        hi: '$purposeName चुनें',
        kn: '$purposeName ಬಳಸಿ',
      );
  String get offlineRegistryNotice => _pick(
        en: 'Offline mode — showing built-in visit types',
        hi: 'ऑफ़लाइन — सहेजे गए भेंट प्रकार दिख रहे हैं',
        kn: 'ಆಫ್‌ಲೈನ್ — ಉಳಿಸಿದ ಭೇಟಿ ಪ್ರಕಾರಗಳನ್ನು ತೋರಿಸಲಾಗುತ್ತಿದೆ',
      );
  String get noMatchingPurposesTitle => _pick(
        en: 'No visit purposes available',
        hi: 'कोई भेंट उद्देश्य उपलब्ध नहीं है',
        kn: 'ಯಾವುದೇ ಭೇಟಿ ಉದ್ದೇಶಗಳು ಲಭ್ಯವಿಲ್ಲ',
      );
  String get visitPurposeChipLabel => _pick(
        en: 'Purpose',
        hi: 'उद्देश्य',
        kn: 'ಉದ್ದೇಶ',
      );

  // Beneficiaries, Add Beneficiary & Profile (V2 §3.3-3.5)
  String get filterAll => _pick(en: 'All', hi: 'सभी', kn: 'ಎಲ್ಲಾ');
  String get filterPregnant =>
      _pick(en: 'Pregnant women', hi: 'गर्भवती महिला', kn: 'ಗರ್ಭಿಣಿಯರು');
  String get filterNewborns =>
      _pick(en: 'Newborns', hi: 'नवजात', kn: 'ನವಜಾತ ಶಿಶುಗಳು');
  String get filterChildren => _pick(en: 'Children', hi: 'बच्चे', kn: 'ಮಕ್ಕಳು');
  String get filterOthers => _pick(en: 'Others', hi: 'अन्य', kn: 'ಇತರರು');
  String get filterHighRisk =>
      _pick(en: 'High risk', hi: 'उच्च जोखिम', kn: 'ಹೆಚ್ಚಿನ ಅಪಾಯ');
  String get addBeneficiaryAction =>
      _pick(en: 'Add beneficiary', hi: 'नया लाभार्थी जोड़ें', kn: 'ಹೊಸ ಫಲಾನುಭವಿ ಸೇರಿಸಿ');
  String get speakToAddTitle =>
      _pick(en: 'Speak to fill (recommended)', hi: 'बोलकर भरें (सुझाव)', kn: 'ಮಾತನಾಡಿ ಭರ್ತಿ ಮಾಡಿ');
  String get speakToAddHint => _pick(
        en: 'Hold mic and say name, age, pregnant/newborn, and area.',
        hi: 'माइक दबाकर नाम, उम्र, गर्भवती/नवजात और गाँव बोलें।',
        kn: 'ಮೈಕ್ ಒತ್ತಿ ಹಿಡಿದು ಹೆಸರು, ವಯಸ್ಸು, ಗರ್ಭಿಣಿ/ನವಜಾತ ಮತ್ತು ಊರು ಹೇಳಿ.',
      );
  String get beneficiaryWhoStep =>
      _pick(en: '1. Who', hi: '1. पहचान', kn: '1. ಪರಿಚಯ');
  String get beneficiaryWhereStep =>
      _pick(en: '2. Where & details', hi: '2. स्थान व विवरण', kn: '2. ಸ್ಥಳ ಮತ್ತು ವಿವರ');
  String get beneficiaryConsentStep =>
      _pick(en: '3. Consent & check', hi: '3. सहमति और जांच', kn: '3. ಸಮ್ಮತಿ ಮತ್ತು ಪರಿಶೀಲನೆ');
  String get fullNameLabel => _pick(en: 'Full name', hi: 'पूरा नाम', kn: 'ಪೂರ್ಣ ಹೆಸರು');
  String get beneficiaryTypeLabel =>
      _pick(en: 'Category', hi: 'श्रेणी', kn: 'ವರ್ಗ');
  String get sexLabel => _pick(en: 'Sex', hi: 'लिंग', kn: 'ಲಿಂಗ');
  String get sexFemale => _pick(en: 'Female', hi: 'महिला', kn: 'ಹೆಣ್ಣು');
  String get sexMale => _pick(en: 'Male', hi: 'पुरुष', kn: 'ಗಂಡು');
  String get sexUnknown => _pick(en: 'Not specified', hi: 'स्पष्ट नहीं', kn: 'ತಿಳಿಸಿಲ್ಲ');
  String get dobLabel => _pick(en: 'Date of birth (YYYY-MM-DD)', hi: 'जन्म तिथि (YYYY-MM-DD)', kn: 'ಜನ್ಮ ದಿನಾಂಕ (YYYY-MM-DD)');
  String get ageYearsLabel => _pick(en: 'Age (years)', hi: 'उम्र (साल)', kn: 'ವಯಸ್ಸು (ವರ್ಷ)');
  String get ageEstimatedFlag =>
      _pick(en: 'Age is estimated', hi: 'अनुमानित उम्र', kn: 'ಅಂದಾಜು ವಯಸ್ಸು');
  String get areaVillageLabel =>
      _pick(en: 'Area / village', hi: 'गाँव / क्षेत्र', kn: 'ಪ್ರದೇಶ / ಗ್ರಾಮ');
  String get phoneOptionalLabel =>
      _pick(en: 'Phone (optional, masked after save)', hi: 'फ़ोन (वैकल्पिक)', kn: 'ಫೋನ್ (ಐಚ್ಛಿಕ)');
  String get monthsPregnantLabel =>
      _pick(en: 'Months pregnant (1–9)', hi: 'गर्भावस्था के महीने (1–9)', kn: 'ಗರ್ಭಾವಸ್ಥೆಯ ತಿಂಗಳು (1–9)');
  String computedEddBanner(String edd) =>
      _pick(en: 'Estimated due date (EDD): $edd', hi: 'संभावित प्रसव तिथि (EDD): $edd', kn: 'ಅಂದಾಜು ಹೆರಿಗೆ ದಿನಾಂಕ (EDD): $edd');
  String get linkMotherLabel =>
      _pick(en: 'Link mother (optional)', hi: 'माँ को जोड़ें (वैकल्पिक)', kn: 'ತಾಯಿಯನ್ನು ಜೋಡಿಸಿ (ಐಚ್ಛಿಕ)');
  String get consentRequiredCheckbox => _pick(
        en: 'Beneficiary / guardian agreed to health record collection',
        hi: 'लाभार्थी / अभिभावक ने स्वास्थ्य जानकारी दर्ज करने की सहमति दी',
        kn: 'ಫಲಾನುಭವಿ / ಪೋಷಕರು ಆರೋಗ್ಯ ಮಾಹಿತಿ ದಾಖಲಿಸಲು ಸಮ್ಮತಿಸಿದ್ದಾರೆ',
      );
  String get consentRequiredError => _pick(
        en: 'Consent must be confirmed before saving.',
        hi: 'सहेजने से पहले सहमति आवश्यक है।',
        kn: 'ಉಳಿಸುವ ಮೊದಲು ಸಮ್ಮತಿ ಅಗತ್ಯವಿದೆ.',
      );
  String get consentMethodVerbal => _pick(en: 'Verbal', hi: 'मौखिक', kn: 'ಮೌಖಿಕ');
  String get consentMethodSigned => _pick(en: 'Signed', hi: 'हस्ताक्षरित', kn: 'ಸಹಿ');
  String get possibleDuplicateTitle =>
      _pick(en: 'Possible match found', hi: 'मिलता-जुलता रिकॉर्ड मिला', kn: 'ಹೋಲುವ ದಾಖಲೆ ಕಂಡುಬಂದಿದೆ');
  String get openExistingPersonAction =>
      _pick(en: 'Open existing', hi: 'मौजूदा खोलें', kn: 'ಇರುವವರನ್ನು ತೆರೆಯಿರಿ');
  String get saveAsNewPersonAction =>
      _pick(en: 'Save as new person', hi: 'नए व्यक्ति के रूप में सहेजें', kn: 'ಹೊಸ ವ್ಯಕ್ತಿಯಾಗಿ ಉಳಿಸಿ');
  String get saveBeneficiaryAction =>
      _pick(en: 'Save beneficiary', hi: 'लाभार्थी सहेजें', kn: 'ಫಲಾನುಭವಿ ಉಳಿಸಿ');
  String get beneficiarySavedTitle =>
      _pick(en: 'Beneficiary saved', hi: 'लाभार्थी सहेजा गया', kn: 'ಫಲಾನುಭವಿ ಉಳಿಸಲಾಗಿದೆ');
  String get recordFirstVisitNowAction =>
      _pick(en: 'Record first visit now', hi: 'अभी पहली भेंट रिकॉर्ड करें', kn: 'ಈಗಲೇ ಮೊದಲ ಭೇಟಿ ದಾಖಲಿಸಿ');
  String get tapToRevealAction => _pick(en: 'Tap to reveal', hi: 'देखने के लिए दबाएं', kn: 'ತೋರಿಸಲು ಟ್ಯಾಪ್ ಮಾಡಿ');
  String get hideSensitiveAction => _pick(en: 'Hide', hi: 'छुपाएं', kn: 'ಮರೆಮಾಡಿ');
  String get recentMeasurementsTitle =>
      _pick(en: 'Health trends', hi: 'माप का रुझान', kn: 'ಆರೋಗ್ಯ ಅಳತೆಗಳು');
  String get visitTimelineTitle =>
      _pick(en: 'Visit timeline', hi: 'भेंट इतिहास', kn: 'ಭೇಟಿ ಇತಿಹಾಸ');
  String get noVisitsRecordedYet =>
      _pick(en: 'No visits recorded yet', hi: 'अभी कोई भेंट दर्ज नहीं है', kn: 'ಇನ್ನೂ ಯಾವುದೇ ಭೇಟಿ ದಾಖಲಾಗಿಲ್ಲ');
  String get phoneLabel => _pick(en: 'Phone', hi: 'फ़ोन', kn: 'ಫೋನ್');
  String beneficiaryTypeDisplay(String type) {
    switch (type) {
      case 'pregnant_woman':
        return _pick(en: 'Pregnant woman', hi: 'गर्भवती महिला', kn: 'ಗರ್ಭಿಣಿ');
      case 'newborn':
        return _pick(en: 'Newborn', hi: 'नवजात', kn: 'ನವಜಾತ ಶಿಶು');
      case 'child_u5':
        return _pick(en: 'Child', hi: 'बच्चा', kn: 'ಮಗು');
      case 'pnc_mother':
        return _pick(en: 'PNC mother', hi: 'प्रसूता माता', kn: 'ಬಾಣಂತಿ');
      case 'adult':
        return _pick(en: 'Adult', hi: 'वयस्क', kn: 'ವಯಸ್ಕ');
      default:
        return _pick(en: 'Other', hi: 'अन्य', kn: 'ಇತರೆ');
    }
  }

  // Insights & Settings (V2 §3.9, §3.10)
  String get insightsTitle => _pick(
        en: 'Insights',
        hi: 'आंकड़े',
        kn: 'ಅಂಕಿಅಂಶ',
      );
  String get insightsSummaryNote => _pick(
        en: 'Measured from visits and queue stored on this device and server.',
        hi: 'इस फ़ोन और सर्वर पर सहेजी गई भेंट से मापा गया।',
        kn: 'ಈ ಫೋನ್ ಮತ್ತು ಸರ್ವರ್‌ನಲ್ಲಿ ಉಳಿಸಿದ ಭೇಟಿಗಳಿಂದ ಅಳೆಯಲಾಗಿದೆ.',
      );
  String get confirmedVisitsMetric => _pick(
        en: 'Confirmed visits',
        hi: 'सहेजे गए रिकॉर्ड',
        kn: 'ದೃಢೀಕರಿಸಿದ ಭೇಟಿಗಳು',
      );
  String get highRiskMetric => _pick(
        en: 'Flagged high risk',
        hi: 'उच्च जोखिम मामले',
        kn: 'ಹೆಚ್ಚಿನ ಅಪಾಯ ಪ್ರಕರಣಗಳು',
      );
  String get pendingSyncMetric => _pick(
        en: 'Waiting to sync',
        hi: 'सिंक के लिए बाकी',
        kn: 'ಸಿಂಕ್‌ಗೆ ಬಾಕಿ',
      );
  String get openSavedVisitsAction => _pick(
        en: 'Open saved visits & queue',
        hi: 'सहेजे गए रिकॉर्ड और कतार खोलें',
        kn: 'ಉಳಿಸಿದ ಭೇಟಿ ಮತ್ತು ಕ್ಯೂ ತೆರೆಯಿರಿ',
      );
  String get periodToday => _pick(en: 'Today', hi: 'आज', kn: 'ಇಂದು');
  String get period7Days => _pick(en: '7 days', hi: '7 दिन', kn: '7 ದಿನ');
  String get period30Days => _pick(en: '30 days', hi: '30 दिन', kn: '30 ದಿನ');
  String get demoDataBadge => _pick(en: 'Demo data', hi: 'डेमो डेटा', kn: 'ಡೆಮೊ ಡೇಟಾ');
  String get coverageMetric =>
      _pick(en: 'Coverage (30d)', hi: 'कवरेज (30 दिन)', kn: 'ವ್ಯಾಪ್ತಿ (30 ದಿನ)');
  String get referralsMetric =>
      _pick(en: 'Referrals suggested', hi: 'रेफरल सुझाव', kn: 'ರೆಫರಲ್ ಸಲಹೆ');
  String get dueOverdueMetric =>
      _pick(en: 'Due / Overdue', hi: 'देय / बकाया', kn: 'ಬಾಕಿ / ವಿಳಂಬ');
  String get avgRecordTimeMetric =>
      _pick(en: 'Avg record time', hi: 'औसत रिकॉर्ड समय', kn: 'ಸರಾಸರಿ ದಾಖಲೆ ಸಮಯ');
  String get voiceShareMetric =>
      _pick(en: 'Voice share', hi: 'वॉइस हिस्सेदारी', kn: 'ಧ್ವನಿ ಪಾಲು');
  String get followupRateMetric =>
      _pick(en: 'Follow-up rate', hi: 'फॉलो-अप दर', kn: 'ಅನುಸರಣಾ ದರ');
  String get estTimeSavedMetric =>
      _pick(en: 'Est. time saved', hi: 'अनुमानित समय बचत', kn: 'ಅಂದಾಜು ಉಳಿತಾಯದ ಸಮಯ');
  String get insightsTelemetryTitle =>
      _pick(en: 'Recording telemetry', hi: 'रिकॉर्डिंग विवरण', kn: 'ದಾಖಲಾತಿ ವಿವರ');
  String get visitsPerDayTitle =>
      _pick(en: 'Visits per day', hi: 'प्रतिदिन भेंट', kn: 'ದೈನಂದಿನ ಭೇಟಿಗಳು');
  String get visitsPerDayEmpty => _pick(
        en: 'No confirmed visits in this period.',
        hi: 'इस अवधि में कोई पुष्ट भेंट नहीं है।',
        kn: 'ಈ ಅವಧಿಯಲ್ಲಿ ದೃಢೀಕರಿಸಿದ ಭೇಟಿಗಳಿಲ್ಲ.',
      );
  String get visitsByPurposeTitle =>
      _pick(en: 'Visits by purpose', hi: 'उद्देश्य के अनुसार भेंट', kn: 'ಉದ್ದೇಶದ ಪ್ರಕಾರ ಭೇಟಿಗಳು');
  String get visitsByPurposeEmpty => _pick(
        en: 'Purpose breakdown appears after visits are confirmed.',
        hi: 'भेंट पुष्टि के बाद उद्देश्य विवरण यहां दिखेगा।',
        kn: 'ಭೇಟಿ ದೃಢೀಕರಿಸಿದ ನಂತರ ಉದ್ದೇಶ ವಿವರ ಕಾಣಿಸುತ್ತದೆ.',
      );
  String get riskBreakdownTitle =>
      _pick(en: 'Risk flags by type', hi: 'जोखिम संकेतों का विवरण', kn: 'ಅಪಾಯ ಸೂಚನೆಗಳ ವಿವರ');
  String get riskBreakdownEmpty => _pick(
        en: 'No risk flags recorded in this period.',
        hi: 'इस अवधि में कोई जोखिम संकेत दर्ज नहीं हुआ।',
        kn: 'ಈ ಅವಧಿಯಲ್ಲಿ ಯಾವುದೇ ಅಪಾಯ ಸೂಚನೆ ದಾಖಲಾಗಿಲ್ಲ.',
      );
  String get dueListCompactTitle =>
      _pick(en: 'Due list', hi: 'बकाया सूची', kn: 'ಬಾಕಿ ಪಟ್ಟಿ');
  String get dueListEmpty => _pick(
        en: 'No beneficiaries due or overdue today.',
        hi: 'आज कोई लाभार्थी देय या बकाया नहीं है।',
        kn: 'ಇಂದು ಬಾಕಿ ಇರುವ ಫಲಾನುಭವಿಗಳಿಲ್ಲ.',
      );
  String get loadDemoDataAction =>
      _pick(en: 'Load demo data', hi: 'डेमो डेटा लोड करें', kn: 'ಡೆಮೊ ಡೇಟಾ ಲೋಡ್ ಮಾಡಿ');
  String get clearDemoDataAction =>
      _pick(en: 'Clear demo data', hi: 'डेमो डेटा हटाएं', kn: 'ಡೆಮೊ ಡೇಟಾ ತೆರವುಗೊಳಿಸಿ');
  String get demoDataNotice => _pick(
        en: 'Includes labeled demo data stored locally on this device.',
        hi: 'इसमें इस फ़ोन पर सहेजा गया लेबल वाला डेमो डेटा शामिल है।',
        kn: 'ಈ ಸಾಧನದಲ್ಲಿ ಉಳಿಸಿದ ಗುರುತಿಸಲಾದ ಡೆಮೊ ಡೇಟಾ ಒಳಗೊಂಡಿದೆ.',
      );
  String visitsPerDaySummary(int totalVisits, int flaggedVisits, int days) => _pick(
        en: '$totalVisits confirmed ($flaggedVisits flagged) across $days d',
        hi: '$days दिन में $totalVisits पुष्ट ($flaggedVisits चिह्नित)',
        kn: '$days ದಿನಗಳಲ್ಲಿ $totalVisits ದೃಢೀಕೃತ ($flaggedVisits ಗುರುತಿಸಿದ)',
      );
  String visitsByPurposeSummary(int topCount, String topLabel) => _pick(
        en: 'Top purpose: $topLabel ($topCount)',
        hi: 'मुख्य उद्देश्य: $topLabel ($topCount)',
        kn: 'ಪ್ರಮುಖ ಉದ್ದೇಶ: $topLabel ($topCount)',
      );
  String riskBreakdownSummary(int totalFlags, String topLabel) => _pick(
        en: '$totalFlags flags logged, led by $topLabel',
        hi: '$totalFlags संकेत दर्ज, सबसे अधिक $topLabel',
        kn: '$totalFlags ಸೂಚನೆಗಳು ದಾಖಲಾಗಿವೆ, ಪ್ರಮುಖ: $topLabel',
      );
  String dueListSummary(int overdueCount, int dueTodayCount) => _pick(
        en: '$overdueCount overdue, $dueTodayCount due today',
        hi: '$overdueCount बकाया, $dueTodayCount आज देय',
        kn: '$overdueCount ವಿಳಂಬ, $dueTodayCount ಇಂದು ಬಾಕಿ',
      );
  String avgSecondsFormat(double seconds) =>
      _pick(en: '${seconds.toStringAsFixed(0)}s', hi: '${seconds.toStringAsFixed(0)} सेकंड', kn: '${seconds.toStringAsFixed(0)} ಸೆ');
  String minutesSavedValue(double perVisitMinutes, double totalMinutes) {
    final p = perVisitMinutes.toStringAsFixed(1);
    final t = totalMinutes.toStringAsFixed(0);
    return _pick(
      en: '$p min/visit ($t min total)',
      hi: '$p मिनट/भेंट (कुल $t मिनट)',
      kn: '$p ನಿಮಿಷ/ಭೇಟಿ (ಒಟ್ಟು $t ನಿಮಿಷ)',
    );
  }
  String get paperBaselineLabel => _pick(
        en: 'Paper baseline (min/visit)',
        hi: 'कागज़ी रिकॉर्ड समय (मिनट/भेंट)',
        kn: 'ಕಾಗದ ದಾಖಲೆ ಸಮಯ (ನಿಮಿಷ/ಭೇಟಿ)',
      );
  String get paperBaselineUnset =>
      _pick(en: 'Not set', hi: 'सेट नहीं है', kn: 'ಸೆಟ್ ಮಾಡಿಲ್ಲ');
  String get paperBaselineSubtitle => _pick(
        en: 'Optional minutes per paper record to estimate voice time saved',
        hi: 'वॉइस रिकॉर्डिंग से समय बचत मापने के लिए वैकल्पिक मान',
        kn: 'ಧ್ವನಿ ದಾಖಲಾತಿಯ ಸಮಯ ಉಳಿತಾಯ ಲೆಕ್ಕಾಚಾರಕ್ಕೆ ಐಚ್ಛಿಕ ಮೌಲ್ಯ',
      );
  String get paperBaselineHint => _pick(
        en: 'Minutes per paper record (e.g. 5)',
        hi: 'प्रति कागज़ी भेंट मिनट (जैसे 5)',
        kn: 'ಪ್ರತಿ ಕಾಗದ ದಾಖಲೆಗೆ ನಿಮಿಷಗಳು (ಉದಾ. 5)',
      );
  String get clearBaselineAction =>
      _pick(en: 'Clear baseline', hi: 'मान हटाएं', kn: 'ತೆರವುಗೊಳಿಸಿ');
  String get insightsComingNextTitle => _pick(
        en: 'Charts arrive in the next update',
        hi: 'चार्ट अगले चरण में जुड़ेंगे',
        kn: 'ಚಾರ್ಟ್‌ಗಳು ಮುಂದಿನ ಹಂತದಲ್ಲಿ ಬರುತ್ತವೆ',
      );
  String get insightsComingNextBody => _pick(
        en: 'Daily trends, purpose breakdowns, and period filters connect once local measurement storage is active.',
        hi: 'स्थानीय माप तालिका बनने के बाद दैनिक रुझान और फ़िल्टर यहां दिखेंगे।',
        kn: 'ಸ್ಥಳೀಯ ಅಳತೆ ಸಂಗ್ರಹ ಸಿದ್ಧವಾದ ನಂತರ ದೈನಂದಿನ ವಿವರಗಳು ಇಲ್ಲಿ ಕಾಣಿಸುತ್ತವೆ.',
      );
  String get settingsTitle => _pick(
        en: 'Settings & Privacy',
        hi: 'सेटिंग्स और गोपनीयता',
        kn: 'ಸೆಟ್ಟಿಂಗ್‌ಗಳು ಮತ್ತು ಗೌಪ್ಯತೆ',
      );
  String signedInAs(String name, String id) => _pick(
        en: 'Signed in as $name ($id)',
        hi: '$name ($id) के रूप में लॉग इन',
        kn: '$name ($id) ಆಗಿ ಸೈನ್ ಇನ್ ಆಗಿದೆ',
      );
  String get highContrastLabel => _pick(
        en: 'High contrast mode',
        hi: 'उच्च कंट्रास्ट मोड',
        kn: 'ಹೈ ಕಾಂಟ್ರಾಸ್ಟ್ ಮೋಡ್',
      );
  String get highContrastSubtitle => _pick(
        en: 'Stronger borders and dark text for bright outdoor sunlight',
        hi: 'बाहर तेज़ धूप में साफ़ पढ़ने के लिए गहरे रंग और बॉर्डर',
        kn: 'ಹೊರಗಿನ ಬಿಸಿಲಿನಲ್ಲಿ ಸ್ಪಷ್ಟವಾಗಿ ಕಾಣಲು ಗಾಢ ಬಣ್ಣ ಮತ್ತು ಬಾರ್ಡರ್',
      );
  String get languageSectionLabel => _pick(
        en: 'App & speech language',
        hi: 'ऐप और बोलने की भाषा',
        kn: 'ಆ್ಯಪ್ ಮತ್ತು ಮಾತಿನ ಭಾಷೆ',
      );
  String get syncAndQueueLabel => _pick(
        en: 'Saved visits & sync queue',
        hi: 'सहेजे गए रिकॉर्ड और सिंक कतार',
        kn: 'ಉಳಿಸಿದ ಭೇಟಿಗಳು ಮತ್ತು ಸಿಂಕ್ ಕ್ಯೂ',
      );
  String get privacyAndDataTitle => _pick(
        en: 'Privacy & data',
        hi: 'गोपनीयता और डेटा',
        kn: 'ಗೌಪ್ಯತೆ ಮತ್ತು ಡೇಟಾ',
      );
  String get privacySummaryBody => _pick(
        en: 'Audio recordings are queued locally when offline and sent over your configured server connection to extract newborn visit fields. Provider API keys remain only on the backend server. Only synthetic demo records are used in this build.',
        hi: 'ऑफ़लाइन होने पर ऑडियो फ़ोन में सुरक्षित कतार में रहता है और नेटवर्क आने पर सर्वर को भेजा जाता है। सभी API कुंजियां केवल सर्वर पर रहती हैं। इस संस्करण में केवल कृत्रिम डेमो डेटा है।',
        kn: 'ಆಫ್‌ಲೈನ್ ಇದ್ದಾಗ ಆಡಿಯೋ ಫೋನಿನಲ್ಲಿ ಸಂಗ್ರಹವಾಗಿ, ನೆಟ್‌ವರ್ಕ್ ಬಂದಾಗ ಸರ್ವರ್‌ಗೆ ಕಳುಹಿಸಲಾಗುತ್ತದೆ. API ಕೀಗಳು ಸರ್ವರ್‌ನಲ್ಲಿ ಮಾತ್ರ ಇರುತ್ತವೆ. ಈ ಆವೃತ್ತಿಯಲ್ಲಿ ಕೇವಲ ಕೃತಕ ಡೆಮೊ ಡೇಟಾ ಇದೆ.',
      );
  String get openUiGalleryLabel => _pick(
        en: 'V2 design gallery',
        hi: 'V2 डिज़ाइन गैलरी',
        kn: 'V2 ವಿನ್ಯಾಸ ಗ್ಯಾಲರಿ',
      );

  // Beneficiary List
  String get searchBeneficiariesHint => _pick(
        en: 'Search by ID or name',
        hi: 'नंबर या नाम से खोजें',
        kn: 'ಸಂಖ್ಯೆ ಅಥವಾ ಹೆಸರಿನಿಂದ ಹುಡುಕಿ',
      );
  String get noBeneficiaries => _pick(
        en: 'No assigned beneficiaries',
        hi: 'कोई लाभार्थी नहीं मिला',
        kn: 'ಯಾವುದೇ ಫಲಾನುಭವಿಗಳಿಲ್ಲ',
      );
  String get startVisit => _pick(
        en: 'Start visit',
        hi: 'भेंट शुरू करें',
        kn: 'ಭೇಟಿ ಪ್ರಾರಂಭಿಸಿ',
      );

  // Saved Visits
  String get noSavedVisits => _pick(
        en: 'No saved visits yet',
        hi: 'अभी तक कोई रिकॉर्ड सहेजा नहीं गया',
        kn: 'ಇನ್ನೂ ಯಾವುದೇ ಭೇಟಿಗಳನ್ನು ಉಳಿಸಲಾಗಿಲ್ಲ',
      );
  String get syncedBadge => _pick(
        en: 'Synced',
        hi: 'सिंक हुआ',
        kn: 'ಸಿಂಕ್ ಆಗಿದೆ',
      );
  String get consultChip => _pick(
        en: 'Consult ANM / doctor',
        hi: 'ANM / डॉक्टर से सलाह',
        kn: 'ANM / ವೈದ್ಯರ ಸಲಹೆ',
      );

  // Supervisor / ANM Flagged Cases View & Privacy Notice
  String get supervisorTitle => _pick(
        en: 'Flagged Cases (ANM)',
        hi: 'फ्लैग किए गए मामले (ANM)',
        kn: 'ಗುರುತಿಸಿದ ಪ್ರಕರಣಗಳು (ANM)',
      );
  String get supervisorSubtitle => _pick(
        en: 'High-risk newborn visits awaiting review',
        hi: 'समीक्षा के लिए उच्च जोखिम वाले नवजात रिकॉर्ड',
        kn: 'ಪರಿಶೀಲನೆಗೆ ಕಾಯುತ್ತಿರುವ ಹೆಚ್ಚಿನ ಅಪಾಯದ ನವಜಾತ ಭೇಟಿಗಳು',
      );
  String get supervisorEmpty => _pick(
        en: 'No flagged visits right now',
        hi: 'अभी कोई फ्लैग किया गया रिकॉर्ड नहीं है',
        kn: 'ಸದ್ಯಕ್ಕೆ ಯಾವುದೇ ಗುರುತಿಸಿದ ಭೇಟಿಗಳಿಲ್ಲ',
      );
  String get openSupervisorView => _pick(
        en: 'ANM / Supervisor View',
        hi: 'ANM / पर्यवेक्षक दृश्य',
        kn: 'ANM / ಮೇಲ್ವಿಚಾರಕರ ನೋಟ',
      );
  String flaggedCountLabel(int count) => _pick(
        en: '$count flagged visit(s)',
        hi: '$count फ्लैग किए गए रिकॉर्ड',
        kn: '$count ಗುರುತಿಸಿದ ಭೇಟಿಗಳು',
      );
  String get workerIdLabel => _pick(
        en: 'ASHA',
        hi: 'आशा',
        kn: 'ಆಶಾ',
      );
  String get visitDetailsTitle => _pick(
        en: 'Visit Details',
        hi: 'भेंट का विवरण',
        kn: 'ಭೇಟಿ ವಿವರಗಳು',
      );
  String get demoConsentNotice => _pick(
        en: 'Voice consent required · Synthetic demo data only',
        hi: 'आवाज़ रिकॉर्ड करने से पहले सहमति आवश्यक · केवल कृत्रिम डेमो डेटा',
        kn: 'ಧ್ವನಿ ದಾಖಲಿಸಲು ಸಮ್ಮತಿ ಅಗತ್ಯ · ಕೇವಲ ಕೃತಕ ಡೆಮೊ ಡೇಟಾ',
      );

  // Offline & Sync
  String get savedOfflineTitle => _pick(
        en: 'Saved offline',
        hi: 'ऑफ़लाइन सहेजा गया',
        kn: 'ಆಫ್‌ಲೈನ್‌ನಲ್ಲಿ ಉಳಿಸಲಾಗಿದೆ',
      );
  String get savedOfflineSubtitle => _pick(
        en: 'Will sync automatically when internet returns.',
        hi: 'इंटरनेट आने पर अपने आप सिंक हो जाएगा।',
        kn: 'ಇಂಟರ್ನೆಟ್ ಬಂದಾಗ ತಾನಾಗಿಯೇ ಸಿಂಕ್ ಆಗುತ್ತದೆ.',
      );
  String get offlineShowingCached => _pick(
        en: 'Offline — showing saved list',
        hi: 'ऑफ़लाइन — सहेजी गई सूची',
        kn: 'ಆಫ್‌ಲೈನ್ — ಉಳಿಸಿದ ಪಟ್ಟಿ',
      );
  String get pendingBadge => _pick(
        en: 'Pending',
        hi: 'बाकी',
        kn: 'ಬಾಕಿ ಇದೆ',
      );
  String get readyToReviewBadge => _pick(
        en: 'Ready to review',
        hi: 'जांच के लिए तैयार',
        kn: 'ಪರಿಶೀಲನೆಗೆ ಸಿದ್ಧ',
      );
  String get syncNow => _pick(
        en: 'Sync now',
        hi: 'अभी सिंक करें',
        kn: 'ಈಗ ಸಿಂಕ್ ಮಾಡಿ',
      );
  String get syncing => _pick(
        en: 'Syncing...',
        hi: 'सिंक हो रहा है...',
        kn: 'ಸಿಂಕ್ ಆಗುತ್ತಿದೆ...',
      );
  String pendingSyncBanner(int count) => _pick(
        en: '$count recording(s) waiting to sync',
        hi: '$count रिकॉर्डिंग सिंक के लिए बाकी हैं',
        kn: '$count ರೆಕಾರ್ಡಿಂಗ್ ಸಿಂಕ್ ಆಗಲು ಬಾಕಿ ಇವೆ',
      );
  String get done => _pick(en: 'Done', hi: 'ठीक है', kn: 'ಮುಗಿಯಿತು');

  // Record Screen
  String get recordVisitTitle => _pick(
        en: 'Record Visit',
        hi: 'भेंट रिकॉर्ड करें',
        kn: 'ಭೇಟಿ ದಾಖಲಿಸಿ',
      );
  String get holdToSpeak => _pick(
        en: 'Hold to Speak',
        hi: 'बोलने के लिए दबाए रखें',
        kn: 'ಮಾತನಾಡಲು ಒತ್ತಿ ಹಿಡಿಯಿರಿ',
      );
  String get releaseToSend => _pick(
        en: 'Release when done',
        hi: 'पूरा होने पर छोड़ें',
        kn: 'ಮುಗಿದ ನಂತರ ಬಿಡಿ',
      );
  String get statusReady => _pick(
        en: 'Ready',
        hi: 'तैयार',
        kn: 'ಸಿದ್ಧ',
      );
  String get statusListening => _pick(
        en: 'Listening...',
        hi: 'सुन रहे हैं...',
        kn: 'ಕೇಳಿಸಿಕೊಳ್ಳುತ್ತಿದೆ...',
      );
  String get statusProcessing => _pick(
        en: 'Processing...',
        hi: 'प्रोसेस हो रहा है...',
        kn: 'ಪ್ರಕ್ರಿಯೆಯಲ್ಲಿದೆ...',
      );
  String get statusPlayingQuestion => _pick(
        en: 'Asking follow-up...',
        hi: 'सवाल पूछा जा रहा है...',
        kn: 'ಪ್ರಶ್ನೆ ಕೇಳಲಾಗುತ್ತಿದೆ...',
      );
  String get tapWhenDone => _pick(
        en: 'Tap when done',
        hi: 'बोलने के बाद दबाएं',
        kn: 'ಮುಗಿದ ನಂತರ ಒತ್ತಿ',
      );
  String get replayQuestion => _pick(
        en: 'Replay',
        hi: 'दोबारा सुनें',
        kn: 'ಮತ್ತೆ ಕೇಳಿ',
      );
  String get skipToReview => _pick(
        en: 'Review now',
        hi: 'अभी जांचें',
        kn: 'ಈಗಲೇ ಪರಿಶೀಲಿಸಿ',
      );
  String followupStep(int count) => _pick(
        en: 'Follow-up $count of 2',
        hi: 'सवाल $count / 2',
        kn: 'ಪ್ರಶ್ನೆ $count / 2',
      );
  String get playingReadback => _pick(
        en: 'Reading aloud...',
        hi: 'पढ़कर सुनाया जा रहा है...',
        kn: 'ಓದಿ ಕೇಳಿಸಲಾಗುತ್ತಿದೆ...',
      );
  String get holdLongerHint => _pick(
        en: 'Hold the mic button while speaking',
        hi: 'बोलते समय बटन दबाए रखें',
        kn: 'ಮಾತನಾಡುವಾಗ ಬಟನ್ ಒತ್ತಿ ಹಿಡಿಯಿರಿ',
      );
  String get micPermissionNeeded => _pick(
        en: 'Microphone permission is needed to record visit audio.',
        hi: 'आवाज़ रिकॉर्ड करने के लिए माइक्रोफोन की अनुमति ज़रूरी है।',
        kn: 'ಧ್ವನಿ ದಾಖಲಿಸಲು ಮೈಕ್ರೋಫೋನ್ ಅನುಮತಿ ಅಗತ್ಯವಿದೆ.',
      );
  String get openSettings => _pick(
        en: 'Open Settings',
        hi: 'सेटिंग्स खोलें',
        kn: 'ಸೆಟ್ಟಿಂಗ್‌ಗಳನ್ನು ತೆರೆಯಿರಿ',
      );
  String get grantPermission => _pick(
        en: 'Allow Microphone',
        hi: 'अनुमति दें',
        kn: 'ಅನುಮತಿ ನೀಡಿ',
      );

  // Compact icon cues on Record screen
  String get cueWeight => _pick(en: 'Weight', hi: 'वजन', kn: 'ತೂಕ');
  String get cueTemp => _pick(en: 'Temp', hi: 'तापमान', kn: 'ತಾಪ');
  String get cueFeeding => _pick(en: 'Feeding', hi: 'स्तनपान', kn: 'ಹಾಲು');
  String get cueCord => _pick(en: 'Cord', hi: 'नाल', kn: 'ಹೊಕ್ಕಳು');
  String get cueJaundice => _pick(en: 'Jaundice', hi: 'पीलिया', kn: 'ಕಾಮಾಲೆ');
  String get cueLimbs => _pick(en: 'Limbs', hi: 'हाथ-पैर', kn: 'ಅಂಗಗಳು');

  // Review & Confirm
  String get reviewTitle => _pick(
        en: 'Review & Confirm',
        hi: 'जांचें और सहेजें',
        kn: 'ಪರಿಶೀಲಿಸಿ ಮತ್ತು ದೃಢೀಕರಿಸಿ',
      );
  String get referralBannerTitle => _pick(
        en: 'Suggest consulting ANM/doctor',
        hi: 'एएनएम या डॉक्टर से सलाह लेने का सुझाव है',
        kn: 'ಎಎನ್‌ಎಂ ಅಥವಾ ವೈದ್ಯರ ಸಲಹೆ ಪಡೆಯಲು ಸೂಚಿಸಲಾಗಿದೆ',
      );
  String get transcriptLabel => _pick(
        en: 'Heard',
        hi: 'सुना गया',
        kn: 'ಕೇಳಿಸಿದ್ದು',
      );
  String get followupNoteTitle => _pick(
        en: 'Follow-up question',
        hi: 'अतिरिक्त जानकारी आवश्यक',
        kn: 'ಹೆಚ್ಚುವರಿ ಮಾಹಿತಿ ಅಗತ್ಯವಿದೆ',
      );
  String get readBack => _pick(
        en: 'Read Back',
        hi: 'पढ़कर सुनाएं',
        kn: 'ಓದಿ ಕೇಳಿಸಿ',
      );
  String get confirmAndSave => _pick(
        en: 'Confirm & Save',
        hi: 'पुष्टि करें और सहेजें',
        kn: 'ದೃಢೀಕರಿಸಿ ಮತ್ತು ಉಳಿಸಿ',
      );
  String get visitSaved => _pick(
        en: 'Visit saved',
        hi: 'रिकॉर्ड सहेजा गया',
        kn: 'ಭೇಟಿ ದಾಖಲಿಸಲಾಗಿದೆ',
      );

  // Field statuses
  String get verifyTag => _pick(en: 'Verify', hi: 'जांचें', kn: 'ಪರಿಶೀಲಿಸಿ');
  String get missingTag => _pick(en: 'Missing', hi: 'बाकी', kn: 'ಬಾಕಿ');
  String get outOfRangeTag => _pick(
        en: 'Check range',
        hi: 'सीमा जांचें',
        kn: 'ಮಿತಿ ಪರಿಶೀಲಿಸಿ',
      );
  String get unknownIdTag => _pick(
        en: 'Unknown ID',
        hi: 'अज्ञात नंबर',
        kn: 'ತಿಳಿಯದ ಸಂಖ್ಯೆ',
      );
  String get notRecorded => _pick(
        en: 'Not recorded',
        hi: 'दर्ज नहीं',
        kn: 'ದಾಖಲಾಗಿಲ್ಲ',
      );

  // Common actions
  String get save => _pick(en: 'Save', hi: 'सहेजें', kn: 'ಉಳಿಸಿ');
  String get cancel => _pick(en: 'Cancel', hi: 'रद्द करें', kn: 'ರದ್ದುಮಾಡಿ');
  String get retry => _pick(en: 'Retry', hi: 'पुनः प्रयास करें', kn: 'ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ');
  String get clear => _pick(en: 'Clear', hi: 'हटाएं', kn: 'ತೆರವುಗೊಳಿಸಿ');
  String get ok => _pick(en: 'OK', hi: 'ठीक है', kn: 'ಸರಿ');
  String get yes => _pick(en: 'Yes', hi: 'हाँ', kn: 'ಹೌದು');
  String get no => _pick(en: 'No', hi: 'नहीं', kn: 'ಇಲ್ಲ');

  // Field names
  String fieldLabel(String field) {
    switch (field) {
      case 'beneficiary_id':
        return _pick(en: 'Beneficiary ID', hi: 'लाभार्थी नंबर', kn: 'ಫಲಾನುಭವಿ ಸಂಖ್ಯೆ');
      case 'baby_weight_kg':
        return _pick(en: 'Baby Weight (kg)', hi: 'बच्चे का वजन (kg)', kn: 'ಮಗುವಿನ ತೂಕ (kg)');
      case 'temperature_c':
        return _pick(en: 'Temperature (°C)', hi: 'तापमान (°C)', kn: 'ತಾಪಮಾನ (°C)');
      case 'breastfeeding':
        return _pick(en: 'Breastfeeding', hi: 'स्तनपान', kn: 'ಸ್ತನ್ಯಪಾನ');
      case 'cord_status':
        return _pick(en: 'Umbilical Cord', hi: 'नाल की स्थिति', kn: 'ಹೊಕ್ಕಳುಬಳ್ಳಿ ಸ್ಥಿತಿ');
      case 'jaundice':
        return _pick(en: 'Jaundice', hi: 'पीलिया', kn: 'ಕಾಮಾಲೆ');
      case 'breathing_rate_per_min':
        return _pick(
          en: 'Breathing Rate (/min)',
          hi: 'सांस की गति (/मिनट)',
          kn: 'ಉಸಿರಾಟದ ದರ (/ನಿಮಿಷ)',
        );
      case 'limb_abnormality':
        return _pick(en: 'Limb Check', hi: 'हाथ-पैर की जांच', kn: 'ಕೈ-ಕಾಲು ತಪಾಸಣೆ');
      case 'danger_signs':
        return _pick(en: 'Danger Signs', hi: 'खतरे के लक्षण', kn: 'ಅಪಾಯದ ಚಿಹ್ನೆಗಳು');
      case 'mother_notes':
        return _pick(en: 'Mother Notes', hi: 'माँ से संबंधित नोट्स', kn: 'ತಾಯಿಯ ಟಿಪ್ಪಣಿ');
      case 'notes':
        return _pick(en: 'Other Notes', hi: 'अन्य नोट्स', kn: 'ಇತರ ಟಿಪ್ಪಣಿಗಳು');
      default:
        return field;
    }
  }

  String breastfeedingLabel(String val) {
    switch (val) {
      case 'exclusive':
        return _pick(en: 'Exclusive', hi: 'केवल स्तनपान', kn: 'ಕೇವಲ ಎದೆಹಾಲು');
      case 'partial':
        return _pick(en: 'Partial', hi: 'आंशिक', kn: 'ಭಾಗಶಃ');
      case 'not_feeding':
        return _pick(en: 'Not feeding', hi: 'दूध नहीं पी रहा', kn: 'ಹಾಲು ಕುಡಿಯುತ್ತಿಲ್ಲ');
      case 'unknown':
        return _pick(en: 'Unknown', hi: 'पता नहीं', kn: 'ತಿಳಿದಿಲ್ಲ');
      default:
        return val;
    }
  }

  String cordStatusLabel(String val) {
    switch (val) {
      case 'clean_dry':
        return _pick(en: 'Clean & dry', hi: 'साफ और सूखा', kn: 'ಸ್ವಚ್ಛ ಮತ್ತು ಒಣಗಿದೆ');
      case 'red_swollen':
        return _pick(en: 'Red / swollen', hi: 'लाल या सूजन', kn: 'ಕೆಂಪು / ಊತ');
      case 'pus_discharge':
        return _pick(en: 'Pus discharge', hi: 'मवाद निकल रहा है', kn: 'ಕೀವು ಬರುತ್ತಿದೆ');
      case 'unknown':
        return _pick(en: 'Unknown', hi: 'पता नहीं', kn: 'ತಿಳಿದಿಲ್ಲ');
      default:
        return val;
    }
  }

  String limbLocationLabel(String val) {
    switch (val) {
      case 'left_arm':
        return _pick(en: 'Left arm', hi: 'बायाँ हाथ', kn: 'ಎಡ ತೋಳು');
      case 'right_arm':
        return _pick(en: 'Right arm', hi: 'दायाँ हाथ', kn: 'ಬಲ ತೋಳು');
      case 'left_leg':
        return _pick(en: 'Left leg', hi: 'बायाँ पैर', kn: 'ಎಡ ಕಾಲು');
      case 'right_leg':
        return _pick(en: 'Right leg', hi: 'दायाँ पैर', kn: 'ಬಲ ಕಾಲು');
      case 'both_arms':
        return _pick(en: 'Both arms', hi: 'दोनों हाथ', kn: 'ಎರಡೂ ತೋಳುಗಳು');
      case 'both_legs':
        return _pick(en: 'Both legs', hi: 'दोनों पैर', kn: 'ಎರಡೂ ಕಾಲುಗಳು');
      case 'unspecified':
        return _pick(en: 'Unspecified', hi: 'अस्पष्ट', kn: 'ನಿರ್ದಿಷ್ಟಪಡಿಸಿಲ್ಲ');
      default:
        return val;
    }
  }

  String dangerSignLabel(String val) {
    switch (val) {
      case 'not_feeding':
        return _pick(en: 'Not feeding', hi: 'दूध न पीना', kn: 'ಹಾಲು ಕುಡಿಯದಿರುವುದು');
      case 'convulsions':
        return _pick(en: 'Convulsions', hi: 'दौरे पड़ना', kn: 'ಸೆಳೆತ');
      case 'lethargy':
        return _pick(en: 'Lethargy', hi: 'सुस्ती', kn: 'ಆಲಸ್ಯ');
      case 'fast_breathing':
        return _pick(en: 'Fast breathing', hi: 'तेज़ सांस', kn: 'ವೇಗದ ಉಸಿರಾಟ');
      case 'fever':
        return _pick(en: 'Fever', hi: 'बुखार', kn: 'ಜ್ವರ');
      case 'hypothermia':
        return _pick(en: 'Low temp', hi: 'कम तापमान', kn: 'ಕಡಿಮೆ ತಾಪಮಾನ');
      case 'pus_umbilicus':
        return _pick(en: 'Pus in cord', hi: 'नाल में मवाद', kn: 'ಹೊಕ್ಕಳುಬಳ್ಳಿಯಲ್ಲಿ ಕೀವು');
      default:
        return val;
    }
  }

  String riskFlagLabel(String flag) {
    if (flag.startsWith('danger_sign:')) {
      final sign = flag.substring('danger_sign:'.length);
      return dangerSignLabel(sign);
    }
    switch (flag) {
      case 'low_birth_weight':
        return _pick(en: 'Low weight (<2.5 kg)', hi: 'कम वजन (<2.5 kg)', kn: 'ಕಡಿಮೆ ತೂಕ (<2.5 kg)');
      case 'fever':
        return _pick(en: 'High temp', hi: 'तेज़ तापमान', kn: 'ಹೆಚ್ಚು ತಾಪಮಾನ');
      case 'hypothermia':
        return _pick(en: 'Low temp', hi: 'कम तापमान', kn: 'ಕಡಿಮೆ ತಾಪಮಾನ');
      case 'fast_breathing':
        return _pick(en: 'Fast breathing', hi: 'तेज़ सांस', kn: 'ವೇಗದ ಉಸಿರಾಟ');
      case 'cord_infection':
        return _pick(en: 'Cord sign', hi: 'नाल में संक्रमण लक्षण', kn: 'ಹೊಕ್ಕಳುಬಳ್ಳಿ ಲಕ್ಷಣ');
      case 'not_feeding':
        return _pick(en: 'Not feeding', hi: 'दूध नहीं पी रहा', kn: 'ಹಾಲು ಕುಡಿಯುತ್ತಿಲ್ಲ');
      case 'jaundice':
        return _pick(en: 'Jaundice', hi: 'पीलिया', kn: 'ಕಾಮಾಲೆ');
      case 'limb_abnormality':
        return _pick(en: 'Limb issue', hi: 'हाथ-पैर समस्या', kn: 'ಅಂಗ ಸಮಸ್ಯೆ');
      case 'high_blood_pressure':
        return _pick(en: 'High BP', hi: 'उच्च रक्तचाप', kn: 'ಅಧಿಕ ರಕ್ತದೊತ್ತಡ');
      case 'swelling':
        return _pick(en: 'Swelling', hi: 'सूजन', kn: 'ಊತ');
      case 'cough':
        return _pick(en: 'Cough', hi: 'खांसी', kn: 'ಕೆಮ್ಮು');
      case 'elevated_temperature':
        return _pick(en: 'Warm temp', hi: 'हल्का बुखार', kn: 'ಹೆಚ್ಚಿದ ತಾಪಮಾನ');
      case 'jaundice_present':
        return _pick(en: 'Jaundice', hi: 'पीलिया', kn: 'ಕಾಮಾಲೆ');
      case 'danger_signs_present':
        return _pick(en: 'Danger sign', hi: 'खतरे का संकेत', kn: 'ಅಪಾಯದ ಚಿಹ್ನೆ');
      case 'limb_abnormality_reported':
        return _pick(en: 'Limb issue', hi: 'हाथ-पैर समस्या', kn: 'ಅಂಗ ಸಮಸ್ಯೆ');
      case 'severe_anemia':
        return _pick(en: 'Severe anemia', hi: 'गंभीर एनीमिया', kn: 'ತೀವ್ರ ರಕ್ತಹೀನತೆ');
      case 'heavy_bleeding':
        return _pick(en: 'Heavy bleeding', hi: 'अधिक रक्तस्राव', kn: 'ಅಧಿಕ ರಕ್ತಸ್ರಾವ');
      case 'severe_acute_malnutrition':
        return _pick(en: 'Low MUAC / SAM', hi: 'गंभीर कुपोषण', kn: 'ತೀವ್ರ ಅಪೌಷ್ಟಿಕತೆ');
      case 'persistent_fever':
        return _pick(en: 'Persistent fever', hi: 'लगातार बुखार', kn: 'ನಿರಂತರ ಜ್ವರ');
      case 'critical_hyperglycemia':
        return _pick(en: 'High blood sugar', hi: 'अधिक शुगर', kn: 'ಅಧಿಕ ರಕ್ತದ ಸಕ್ಕರೆ');
      default:
        return flag;
    }
  }

  String friendlyError(String code, [String? serverMessage]) {
    switch (code) {
      case 'INVALID_CREDENTIALS':
        return invalidCredentialsError;
      case 'OFFLINE_FIRST_LOGIN':
        return offlineFirstLoginError;
      case 'NETWORK_ERROR':
        return _pick(
          en: 'Could not connect to server. Check Wi-Fi or server URL.',
          hi: 'सर्वर से संपर्क नहीं हो पाया। इंटरनेट या सर्वर URL जांचें।',
          kn: 'ಸರ್ವರ್ ಸಂಪರ್ಕಿಸಲು ಸಾಧ್ಯವಾಗಲಿಲ್ಲ. ನೆಟ್‌ವರ್ಕ್ ಅಥವಾ URL ಪರಿಶೀಲಿಸಿ.',
        );
      case 'TIMEOUT':
        return _pick(
          en: 'Server took too long to respond. Please retry.',
          hi: 'सर्वर से जवाब आने में देरी हुई। कृपया फिर कोशिश करें।',
          kn: 'ಸರ್ವರ್ ಪ್ರತಿಕ್ರಿಯೆ ತಡವಾಯಿತು. ದಯವಿಟ್ಟು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.',
        );
      case 'EMPTY_AUDIO':
      case 'INVALID_AUDIO':
        return _pick(
          en: 'Recording could not be heard clearly. Please speak again.',
          hi: 'आवाज़ साफ़ रिकॉर्ड नहीं हुई। कृपया दोबारा बोलें।',
          kn: 'ಧ್ವನಿ ಸ್ಪಷ್ಟವಾಗಿ ದಾಖಲಾಗಲಿಲ್ಲ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಮಾತನಾಡಿ.',
        );
      case 'ERROR_RETRY':
        return _pick(
          en: 'No speech detected. Hold the button and speak clearly.',
          hi: 'कोई आवाज़ सुनाई नहीं दी। बटन दबाकर साफ़ बोलें।',
          kn: 'ಧ್ವನಿ ಕೇಳಿಸಲಿಲ್ಲ. ಬಟನ್ ಒತ್ತಿ ಸ್ಪಷ್ಟವಾಗಿ ಮಾತನಾಡಿ.',
        );
      default:
        if (serverMessage != null && serverMessage.trim().isNotEmpty) {
          return serverMessage;
        }
        return _pick(
          en: 'Something went wrong. Please try again.',
          hi: 'कुछ गलत हो गया। कृपया फिर से कोशिश करें।',
          kn: 'ಏನೋ ತಪ್ಪಾಗಿದೆ. ದಯವಿಟ್ಟು ಮತ್ತೆ ಪ್ರಯತ್ನಿಸಿ.',
        );
    }
  }
}
