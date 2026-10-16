class AppStrings {
  AppStrings._();

  // App
  static const String appName = 'DocSift';
  static const String appTagline = 'Your Secure Knowledge Vault';

  // Auth
  static const String setPinTitle = 'Create Your PIN';
  static const String setPinSubtitle =
      'This PIN encrypts your vault. Never share it — there is no recovery.';
  static const String confirmPinTitle = 'Confirm Your PIN';
  static const String confirmPinSubtitle =
      'Re-enter your 6-digit PIN to confirm.';
  static const String enterPinTitle = 'Unlock Vault';
  static const String enterPinSubtitle = 'Enter your PIN to access DocSift.';
  static const String pinMismatch = 'PINs do not match. Please try again.';
  static const String pinIncorrect = 'Incorrect PIN. Try again.';
  static const String pinLockedOut = 'Vault locked. Too many failed attempts.';
  static const String biometricLabel = 'Use biometric to unlock';

  // Dashboard
  static const String dashboardTitle = 'My Vault';
  static const String recentFiles = 'Recent Files';
  static const String categories = 'Categories';
  static const String allFiles = 'All Files';
  static const String starred = 'Starred';
  static const String noFilesYet = 'No files yet';
  static const String noFilesSubtitle =
      'Tap the + button to import your first document.';
  static const String importFile = 'Import File';

  // Categories
  static const String documents = 'Documents';
  static const String images = 'Images';
  static const String pdfs = 'PDFs';
  static const String media = 'Media';
  static const String notes = 'Notes';
  static const String archives = 'Archives';
  static const String sheets = 'Sheets';
  static const String others = 'Others';

  // Search
  static const String searchTitle = 'Search Vault';
  static const String searchHint = 'Search documents, content...';
  static const String noResults = 'No results found';
  static const String noResultsSubtitle =
      'Try different keywords or check spelling.';

  // AI
  static const String aiTitle = 'Ask DocSift AI';
  static const String aiHint = 'Ask anything about your documents...';
  static const String aiThinking = 'Thinking...';
  static const String aiNoAnswer = 'No relevant information found in your vault.';
  static const String aiSourceLabel = 'Source';

  // Settings
  static const String settingsTitle = 'Settings';
  static const String changePin = 'Change PIN';
  static const String biometricUnlock = 'Biometric Unlock';
  static const String autoLock = 'Auto-Lock Timer';
  static const String darkMode = 'Dark Mode';
  static const String storageUsed = 'Storage Used';
  static const String about = 'About DocSift';
  static const String version = 'Version 1.0.0';
  static const String deleteVault = 'Delete Entire Vault';
  static const String deleteVaultConfirm =
      'This will permanently delete all your files and data. This cannot be undone.';

  // Common
  static const String cancel = 'Cancel';
  static const String confirm = 'Confirm';
  static const String delete = 'Delete';
  static const String save = 'Save';
  static const String ok = 'OK';
  static const String retry = 'Retry';
  static const String loading = 'Loading...';
  static const String processing = 'Processing...';
  static const String encrypting = 'Encrypting file...';
  static const String decrypting = 'Decrypting...';
  static const String extractingText = 'Extracting text...';
  static const String done = 'Done';
  static const String error = 'Something went wrong';
  static const String unknownError = 'An unknown error occurred.';
}
