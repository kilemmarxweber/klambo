/// Mis a jour par tool/bump_version.ps1 avant chaque build APK.
const String appVersionName = "0.1.1";
const int appVersionCode = 11;

String get appVersionLabel => "$appVersionName+$appVersionCode";
