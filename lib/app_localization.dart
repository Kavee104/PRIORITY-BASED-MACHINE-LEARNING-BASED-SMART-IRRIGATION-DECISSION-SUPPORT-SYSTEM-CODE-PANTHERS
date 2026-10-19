import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores and exposes the language selected by the user.
class AppLocaleController {
  AppLocaleController._();

  static final AppLocaleController instance = AppLocaleController._();
  static const _preferenceKey = 'app_language';

  final ValueNotifier<Locale> locale = ValueNotifier<Locale>(
    const Locale('en'),
  );

  Future<void> initialize() async {
    final preferences = await SharedPreferences.getInstance();
    final savedLanguage = preferences.getString(_preferenceKey);
    if (savedLanguage == 'si' || savedLanguage == 'en') {
      locale.value = Locale(savedLanguage!);
    }
  }

  Future<void> setLanguage(String languageCode) async {
    if (locale.value.languageCode == languageCode) return;
    locale.value = Locale(languageCode);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, languageCode);
  }
}

class AppTranslations {
  AppTranslations._();

  static const Map<String, String> _sinhala = {
    'Smart Irrigation': 'ස්මාර්ට් වාරිමාර්ග',
    'English': 'English',
    'Sinhala': 'සිංහල',
    'Language': 'භාෂාව',
    'Welcome': 'සාදරයෙන් පිළිගනිමු',
    'Sign in to continue managing your irrigation system.':
        'ඔබේ වාරිමාර්ග පද්ධතිය කළමනාකරණය කිරීමට පිවිසෙන්න.',
    'Email or Username': 'විද්‍යුත් තැපෑල හෝ පරිශීලක නාමය',
    'Enter your email or username':
        'විද්‍යුත් තැපෑල හෝ පරිශීලක නාමය ඇතුළත් කරන්න',
    'Password': 'මුරපදය',
    'Enter your password': 'මුරපදය ඇතුළත් කරන්න',
    'Forgot Password?': 'මුරපදය අමතකද?',
    'Sign In': 'පිවිසෙන්න',
    'Smart Water Management': 'ස්මාර්ට් ජල කළමනාකරණය',
    "Don't have an account?": 'ගිණුමක් නැද්ද?',
    'Create an account': 'ගිණුමක් සාදන්න',
    'Farmer Registration': 'ගොවි ලියාපදිංචිය',
    'Sign up for AI-powered smart irrigation access':
        'AI ස්මාර්ට් වාරිමාර්ග පහසුකම් සඳහා ලියාපදිංචි වන්න',
    'First Name': 'මුල් නම',
    'Last Name': 'වාසගම',
    'Confirm Password': 'මුරපදය තහවුරු කරන්න',
    'CREATE FARMER ACCOUNT': 'ගොවි ගිණුම සාදන්න',
    'Please fill all required fields': 'අවශ්‍ය සියලුම කොටස් පුරවන්න',
    'Passwords do not match': 'මුරපද දෙක නොගැළපේ',
    'Signup successful! You can now login.':
        'ලියාපදිංචිය සාර්ථකයි! දැන් පිවිසිය හැක.',
    'Reset Password': 'මුරපදය යළි සකසන්න',
    "Enter your registered email address. We'll send a verification code.":
        'ලියාපදිංචි විද්‍යුත් තැපෑල ඇතුළත් කරන්න. අපි තහවුරු කිරීමේ කේතයක් එවන්නෙමු.',
    'Please enter your email address': 'විද්‍යුත් තැපැල් ලිපිනය ඇතුළත් කරන්න',
    'SEND VERIFICATION CODE': 'තහවුරු කිරීමේ කේතය යවන්න',
    'Verification Code (OTP)': 'තහවුරු කිරීමේ කේතය (OTP)',
    'VERIFY CODE': 'කේතය තහවුරු කරන්න',
    'Resend Code': 'කේතය නැවත යවන්න',
    'Enter your new secure password.': 'නව ආරක්ෂිත මුරපදය ඇතුළත් කරන්න.',
    'Confirm New Password': 'නව මුරපදය තහවුරු කරන්න',
    'Show password': 'මුරපදය පෙන්වන්න',
    'Hide password': 'මුරපදය සඟවන්න',
    'RESET PASSWORD': 'මුරපදය යළි සකසන්න',
    'Please enter the OTP code': 'OTP කේතය ඇතුළත් කරන්න',
    'Please fill both password fields': 'මුරපද කොටස් දෙකම පුරවන්න',
    'Please enter email and password':
        'කරුණාකර විද්‍යුත් තැපෑල හා මුරපදය ඇතුළත් කරන්න',
    'Grow Smarter.': 'වඩා බුද්ධිමත්ව වගා කරන්න.',
    'Save Every Drop.': 'සෑම ජල බිංදුවක්ම සුරකින්න.',
    'AI-Powered Decisions': 'AI මඟින් බලගැන්වූ තීරණ',
    'Smart Water Optimization': 'ස්මාර්ට් ජල ප්‍රශස්තකරණය',
    'Real-Time Monitoring': 'තත්කාලීන නිරීක්ෂණය',
    'AI-powered irrigation that helps you optimize water usage, improve crop health, and make smarter farming decisions.':
        'ජල භාවිතය ප්‍රශස්ත කර, වගාවේ සෞඛ්‍යය වැඩිදියුණු කර, වඩා හොඳ තීරණ ගැනීමට AI වාරිමාර්ග සහාය වේ.',
    'Predictive irrigation schedules based on soil & weather':
        'පස සහ කාලගුණය අනුව පුරෝකථන වාරි කාලසටහන්',
    'Save up to 40% reservoir water with precise allocation':
        'නිවැරදි බෙදාහැරීමෙන් ජලාශ ජලය 40% දක්වා ඉතිරි කරන්න',
    'Live moisture sensors & reservoir telemetry':
        'සජීවී තෙතමන සංවේදක සහ ජලාශ දත්ත',
    'IoT Telemetry Active': 'IoT දත්ත සබඳතාව සක්‍රියයි',
    'CONNECTED': 'සම්බන්ධයි',
    'Dashboard': 'පාලන පුවරුව',
    'Settings': 'සැකසුම්',
    'Profile & Account Settings': 'පැතිකඩ හා ගිණුම් සැකසුම්',
    'Smart Irrigation Dashboard': 'ස්මාර්ට් වාරිමාර්ග පාලන පුවරුව',
    'Manage farmer details & preferences': 'ගොවි තොරතුරු හා රුචිකත්ව කළමනාකරණය',
    'AI-Powered Water Allocation & Telemetry':
        'AI ජල බෙදාහැරීම හා දත්ත නිරීක්ෂණය',
    'Logout': 'පිටවන්න',
    'FARMER ROLE': 'ගොවි ගිණුම',
    'Farmer Profile & Account Settings': 'ගොවි පැතිකඩ හා ගිණුම් සැකසුම්',
    'Manage your personal info, farm preferences, and security settings':
        'පුද්ගලික තොරතුරු, ගොවිපළ රුචිකත්ව සහ ආරක්ෂක සැකසුම් කළමනාකරණය කරන්න',
    'Personal Profile Details': 'පුද්ගලික පැතිකඩ තොරතුරු',
    'Full Name': 'සම්පූර්ණ නම',
    'Email Address': 'විද්‍යුත් තැපැල් ලිපිනය',
    'Account Security & Password': 'ගිණුම් ආරක්ෂාව හා මුරපදය',
    'Current Password': 'වත්මන් මුරපදය',
    'New Password': 'නව මුරපදය',
    'SAVE PROFILE CHANGES': 'පැතිකඩ වෙනස්කම් සුරකින්න',
    'Welcome, {name}': 'සාදරයෙන් පිළිගනිමු, {name}',
    'System Metrics & Telemetry': 'පද්ධති දර්ශක හා දත්ත',
    'AI-powered irrigation optimization helps you save water, improve crop yield, and automate zone scheduling.':
        'AI වාරිමාර්ග ප්‍රශස්තකරණය ජලය ඉතිරි කිරීමට, අස්වැන්න වැඩි කිරීමට සහ කලාප කාලසටහන් ස්වයංක්‍රීය කිරීමට උපකාරී වේ.',
    'Soil Moisture': 'පසේ තෙතමනය',
    'Temperature': 'උෂ්ණත්වය',
    'Moisture Index': 'තෙතමන දර්ශකය',
    'Ambient Temp': 'පරිසර උෂ්ණත්වය',
    'No data': 'දත්ත නැත',
    'Needs Water': 'ජලය අවශ්‍යයි',
    'Optimal': 'ප්‍රශස්තයි',
    'High': 'ඉහළයි',
    'Normal': 'සාමාන්‍යයි',
    'ONLINE': 'මාර්ගගතයි',
    'OFFLINE': 'මාර්ගගත නොවේ',
    'Add New Field': 'නව කුඹුරක් එක් කරන්න',
    'Register New Field': 'නව කුඹුරක් ලියාපදිංචි කරන්න',
    'Field Profile Details': 'කුඹුරු පැතිකඩ තොරතුරු',
    'Add zone parameters for automated water scheduling':
        'ස්වයංක්‍රීය ජල කාලසටහන සඳහා කලාප තොරතුරු එක් කරන්න',
    'Zone Number': 'කලාප අංකය',
    'Enter Zone No (e.g. 1 - 28)': 'කලාප අංකය ඇතුළත් කරන්න (උදා: 1 - 28)',
    'Field Size (Acres)': 'කුඹුරේ ප්‍රමාණය (අක්කර)',
    'Acres': 'අක්කර',
    'SAVING...': 'සුරකිමින්...',
    'REGISTER FIELD': 'කුඹුර ලියාපදිංචි කරන්න',
    'Please enter zone number and field size':
        'කලාප අංකය සහ කුඹුරේ ප්‍රමාණය ඇතුළත් කරන්න',
    'Field profile created successfully!': 'කුඹුරු පැතිකඩ සාර්ථකව සාදන ලදී!',
    'Field profile created!': 'කුඹුරු පැතිකඩ සාදන ලදී!',
    'Field registered locally!': 'කුඹුර උපාංගයේ ලියාපදිංචි කරන ලදී!',
    'Request Water': 'ජලය ඉල්ලා සිටින්න',
    'Registered Fields & Soil Condition': 'ලියාපදිංචි කුඹුරු හා පසෙහි තත්ත්වය',
    'Field ID': 'කුඹුරු අංකය',
    'Zone No': 'කලාප අංකය',
    'Size': 'ප්‍රමාණය',
    'Moisture': 'තෙතමනය',
    'Status': 'තත්ත්වය',
    'Action': 'ක්‍රියාව',
    'Water Allocation Requests': 'ජල බෙදාහැරීමේ ඉල්ලීම්',
    'Zone / Field': 'කලාපය / කුඹුර',
    'Request Time': 'ඉල්ලූ වේලාව',
    'Pending': 'අනුමැතිය අපේක්ෂාවෙන්',
    'Select Field for Irrigation': 'වාරිමාර්ගය සඳහා කුඹුර තෝරන්න',
    'Request automated water allocation': 'ස්වයංක්‍රීය ජල බෙදාහැරීමක් ඉල්ලන්න',
    'Please register a field first': 'පළමුව කුඹුරක් ලියාපදිංචි කරන්න',
    'Admin Control Center': 'පරිපාලක පාලන මධ්‍යස්ථානය',
    'Real-time System Administration & Water Approval':
        'තත්කාලීන පද්ධති පාලනය හා ජල අනුමැතිය',
    'Refresh Data': 'දත්ත නැවුම් කරන්න',
    'Real-time water request approvals, user management, and system audit trail.':
        'තත්කාලීන ජල ඉල්ලීම් අනුමැතිය, පරිශීලක කළමනාකරණය සහ පද්ධති විගණන සටහන.',
    'ADMIN CONTROL': 'පරිපාලක පාලනය',
    'SYSTEM ADMIN': 'පද්ධති පරිපාලක',
    'Priority Schedule': 'ප්‍රමුඛතා කාලසටහන',
    'AgTech Weather Telemetry': 'AgTech කාලගුණ දත්ත',
    'OK': 'හරි',
    'Adaptive Policy Mode': 'අනුවර්තන ප්‍රතිපත්ති ක්‍රමය',
    'Water Release': 'ජල නිකුතුව',
    'ML Water Release Predictor': 'ML ජල නිකුතු පුරෝකථනය',
    'Mahakandarawa Reservoir • ArcGIS & Weather AI':
        'මහකන්දරාව ජලාශය • ArcGIS සහ කාලගුණ AI',
    'Refresh Prediction': 'පුරෝකථනය නැවුම් කරන්න',
    'Target Reservoir:': 'ඉලක්ක ජලාශය:',
    'PREDICTED RELEASE AMOUNT': 'පුරෝකථිත ජල නිකුතු ප්‍රමාණය',
    'ArcGIS & Weather Realtime Inputs:': 'ArcGIS සහ තත්කාලීන කාලගුණ දත්ත:',
    'Water Depth': 'ජල ගැඹුර',
    'Capacity': 'ධාරිතාව',
    'Rainfall': 'වර්ෂාපතනය',
    'Release Demand': 'නිකුතු ඉල්ලුම',
    'Low': 'අඩු',
    'Medium': 'මධ්‍යම',
    'No priority schedule available': 'ප්‍රමුඛතා කාලසටහනක් නොමැත',
    'Total Area': 'මුළු භූමි ප්‍රමාණය',
    'Registered Fields': 'ලියාපදිංචි කුඹුරු',
    'Avg Moisture': 'සාමාන්‍ය තෙතමනය',
    'Avg Temp': 'සාමාන්‍ය උෂ්ණත්වය',
    'Zone Score (F1)': 'කලාප ලකුණ (F1)',
    'Zone Target (F2)': 'කලාප ඉලක්කය (F2)',
    'Total Zone Allocation Volume': 'මුළු කලාප ජල වෙන්කිරීම',
    'Liters': 'ලීටර්',
    'Previous-day rainfall': 'පෙර දින වර්ෂාපතනය',
    'Average days since irrigation': 'අවසන් වාරිමාර්ගයෙන් පසු සාමාන්‍ය දින',
    'Low Water Supply (<80 Acft/Day): 🔴 Priority-Based Scarcity Allocation by Zone Urgency Score (Formula 1 & 2 Applied).':
        'අඩු ජල සැපයුමකදී කලාප හදිසි ලකුණ අනුව ප්‍රමුඛතා බෙදාහැරීම ක්‍රියාත්මකයි.',
    'Low Water Supply Policy Active.':
        'අඩු ජල සැපයුම් ප්‍රතිපත්තිය ක්‍රියාත්මකයි.',
    'User Management': 'පරිශීලක කළමනාකරණය',
    'User Role Management': 'පරිශීලක භූමිකා කළමනාකරණය',
    'Create User': 'පරිශීලකයෙකු සාදන්න',
    'All Users': 'සියලු පරිශීලකයින්',
    'Setup New User': 'නව පරිශීලකයෙකු සකසන්න',
    'Assign roles: Admin · Officer · Farmer':
        'භූමිකාව ලබාදෙන්න: පරිපාලක · නිලධාරී · ගොවි',
    'Select Role': 'භූමිකාව තෝරන්න',
    'Username / Email': 'පරිශීලක නාමය / විද්‍යුත් තැපෑල',
    'Enter username or email': 'පරිශීලක නාමය හෝ විද්‍යුත් තැපෑල ඇතුළත් කරන්න',
    'Enter password': 'මුරපදය ඇතුළත් කරන්න',
    'Re-enter password': 'මුරපදය නැවත ඇතුළත් කරන්න',
    'Creating...': 'සාදමින්...',
    'CREATE USER': 'පරිශීලකයා සාදන්න',
    'Refresh': 'නැවුම් කරන්න',
    'Retry': 'නැවත උත්සාහ කරන්න',
    'No registered farmers found.\nTap refresh to load.':
        'ලියාපදිංචි ගොවීන් හමු නොවීය.\nපූරණය කිරීමට නැවුම් කරන්න.',
    'Load Users': 'පරිශීලකයින් පූරණය කරන්න',
    'Farmer': 'ගොවි',
    'Admin': 'පරිපාලක',
    'Officer': 'නිලධාරී',
    'FARMER': 'ගොවි',
    'ADMIN': 'පරිපාලක',
    'OFFICER': 'නිලධාරී',
    'System Metrics (Live)': 'පද්ධති දර්ශක (සජීවී)',
    'Live': 'සජීවී',
    'Total Users': 'මුළු පරිශීලකයින්',
    'Pending Requests': 'නිරාකරණ ඉල්ලීම්',
    'Approved': 'අනුමතයි',
    'Rejected': 'ප්‍රතික්ෂේපිතයි',
    'Total Requests': 'මුළු ඉල්ලීම්',
    'Awaiting approval': 'අනුමැතිය අපේක්ෂාවෙන්',
    'Water allocated': 'ජලය වෙන් කර ඇත',
    'Requests denied': 'ඉල්ලීම් ප්‍රතික්ෂේපිතයි',
    'Water allocation requests': 'ජල බෙදාහැරීමේ ඉල්ලීම්',
    'Action Needed': 'ක්‍රියාමාර්ගයක් අවශ්‍යයි',
    'Clear': 'ගැටලුවක් නැත',
    'Done': 'සම්පූර්ණයි',
    'Declined': 'ප්‍රතික්ෂේප කළා',
    'None': 'නැත',
    'All Time': 'සියලු කාලයම',
    'Export CSV': 'CSV ලෙස බාගත කරන්න',
    'Clear Table': 'වගුව හිස් කරන්න',
    'Approve': 'අනුමත කරන්න',
    'Reject': 'ප්‍රතික්ෂේප කරන්න',
    'Zone ESP32 Sensors': 'කලාප ESP32 සංවේදක',
    'No ESP32 devices registered yet.': 'තවම ESP32 උපාංග ලියාපදිංචි කර නැත.',
    'Farmer Water Requests': 'ගොවීන්ගේ ජල ඉල්ලීම්',
  };

  static String translate(
    BuildContext context,
    String key, [
    Map<String, Object?> parameters = const {},
  ]) {
    var value = Localizations.localeOf(context).languageCode == 'si'
        ? (_sinhala[key] ?? key)
        : key;
    for (final entry in parameters.entries) {
      value = value.replaceAll('{' + entry.key + '}', entry.value.toString());
    }
    return value;
  }
}

extension AppTranslationContext on BuildContext {
  String tr(String key, [Map<String, Object?> parameters = const {}]) =>
      AppTranslations.translate(this, key, parameters);
}

/// Compact language picker that can be reused in any app bar or screen.
class LanguageSelector extends StatelessWidget {
  final Color foregroundColor;
  final Color? backgroundColor;

  const LanguageSelector({
    super.key,
    this.foregroundColor = const Color(0xFF315849),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final currentLanguage = Localizations.localeOf(context).languageCode;
    return PopupMenuButton<String>(
      tooltip: context.tr('Language'),
      initialValue: currentLanguage,
      onSelected: AppLocaleController.instance.setLanguage,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'en',
          child: Row(
            children: [
              if (currentLanguage == 'en')
                const Icon(Icons.check_rounded, size: 18),
              if (currentLanguage != 'en') const SizedBox(width: 18),
              const SizedBox(width: 8),
              const Text('English'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'si',
          child: Row(
            children: [
              if (currentLanguage == 'si')
                const Icon(Icons.check_rounded, size: 18),
              if (currentLanguage != 'si') const SizedBox(width: 18),
              const SizedBox(width: 8),
              const Text('සිංහල'),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: backgroundColor ?? foregroundColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: foregroundColor.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.language_rounded, size: 18, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              currentLanguage == 'si' ? 'සිං' : 'EN',
              style: TextStyle(
                color: foregroundColor,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: foregroundColor,
            ),
          ],
        ),
      ),
    );
  }
}
