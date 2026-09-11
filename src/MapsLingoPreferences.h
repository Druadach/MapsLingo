#ifndef MAPS_LINGO_PREFERENCES_H
#define MAPS_LINGO_PREFERENCES_H

#include <CoreFoundation/CoreFoundation.h>
#include <stdbool.h>

#ifndef ML_VERSION
#define ML_VERSION "development"
#endif

typedef enum {
    MLResultSuccess,
    MLResultAlreadySelected,
    MLResultNoBackup,
    MLResultPreservedExternalChange,
    MLResultWrongApplication,
    MLResultUnsupportedLanguage,
    MLResultInvalidBackup,
    MLResultAllocationFailed,
    MLResultSynchronizationFailed
} MLLanguageResult;

bool MLIsMapsApplication(void);
CFArrayRef MLCopySupportedLanguages(void) CF_RETURNS_RETAINED;
CFPropertyListRef MLCopyAppLanguageOverride(void) CF_RETURNS_RETAINED;
MLLanguageResult MLApplyLanguage(CFStringRef language);
MLLanguageResult MLRestoreOriginalLanguage(void);
bool MLHasPresentedPicker(void);
bool MLMarkPickerPresented(void);
const char *MLResultMessage(MLLanguageResult result);

#endif
