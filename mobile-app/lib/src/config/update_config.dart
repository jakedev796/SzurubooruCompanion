/// Build-time or runtime config for the in-app update source (GitHub Releases).
class UpdateConfig {
  UpdateConfig._();

  static const String githubOwner = 'jakedev796';
  static const String githubRepo = 'SzurubooruCompanion';

  /// List releases (newest first). Used to find the latest release that has mobile assets (version.json).
  static String get listReleasesUrl =>
      'https://api.github.com/repos/$githubOwner/$githubRepo/releases?per_page=30';
}
