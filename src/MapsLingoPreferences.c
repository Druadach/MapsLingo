#include "MapsLingoPreferences.h"
#include <string.h>

typedef enum {
    MLApplication,
    MLLanguages,
    MLBackup,
    MLOriginalExists,
    MLOriginalValue,
    MLLatestExists,
    MLLatestValue,
    MLPendingExists,
    MLPendingValue,
    MLPickerShown,
    MLKeyCount
} MLKey;

typedef struct {
    CFStringRef keys[MLKeyCount];
} MLContext;

bool MLIsMapsApplication(void) {
    CFBundleRef bundle = CFBundleGetMainBundle();
    CFStringRef identifier = bundle ? CFBundleGetIdentifier(bundle) : NULL;
    char buffer[sizeof("com.apple.Maps")];
    return identifier && CFStringGetCString(identifier, buffer, sizeof(buffer), kCFStringEncodingUTF8) &&
           strcmp(buffer, "com.apple.Maps") == 0;
}

static void MLDisposeContext(MLContext *context) {
    for (size_t index = 0; index < MLKeyCount; index++) {
        if (context->keys[index]) {
            CFRelease(context->keys[index]);
        }
    }
}

static MLLanguageResult MLCreateContext(MLContext *context) {
    *context = (MLContext){0};
    if (!MLIsMapsApplication()) {
        return MLResultWrongApplication;
    }
    const char *names[MLKeyCount] = {
        "com.apple.Maps", "AppleLanguages", "MapsLingo.SafeBackup.v1",
        "hadOverride", "originalValue", "lastAppliedHadOverride", "lastAppliedValue",
        "pendingHadOverride", "pendingValue", "MapsLingo.PickerShown.v1"
    };
    for (size_t index = 0; index < MLKeyCount; index++) {
        context->keys[index] = CFStringCreateWithCString(kCFAllocatorDefault, names[index],
                                                        kCFStringEncodingUTF8);
        if (!context->keys[index]) {
            MLDisposeContext(context);
            return MLResultAllocationFailed;
        }
    }
    return MLResultSuccess;
}

static CFPropertyListRef MLCopyValue(const MLContext *context, MLKey key) {
    return CFPreferencesCopyValue(context->keys[key], context->keys[MLApplication],
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
}

static bool MLValuesEqual(CFPropertyListRef first, CFPropertyListRef second) {
    return first == second || (first && second && CFEqual(first, second));
}

static bool MLWriteValue(const MLContext *context, MLKey key, CFPropertyListRef value) {
    CFPreferencesSetValue(context->keys[key], value, context->keys[MLApplication],
                          kCFPreferencesCurrentUser, kCFPreferencesAnyHost);
    if (!CFPreferencesSynchronize(context->keys[MLApplication],
                                  kCFPreferencesCurrentUser, kCFPreferencesAnyHost)) {
        return false;
    }
    CFPropertyListRef readBack = MLCopyValue(context, key);
    bool matches = MLValuesEqual(readBack, value);
    if (readBack) {
        CFRelease(readBack);
    }
    return matches;
}

CFArrayRef MLCopySupportedLanguages(void) {
    if (!MLIsMapsApplication()) {
        return NULL;
    }
    CFArrayRef localizations = CFBundleCopyBundleLocalizations(CFBundleGetMainBundle());
    CFMutableArrayRef result = CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);
    if (!localizations || !result) {
        if (localizations) {
            CFRelease(localizations);
        }
        if (result) {
            CFRelease(result);
        }
        return NULL;
    }
    for (CFIndex index = 0; index < CFArrayGetCount(localizations); index++) {
        CFStringRef language = CFArrayGetValueAtIndex(localizations, index);
        char identifier[128];
        if (CFGetTypeID(language) != CFStringGetTypeID() ||
            !CFStringGetCString(language, identifier, sizeof(identifier), kCFStringEncodingUTF8) ||
            identifier[0] == '\0' || strcmp(identifier, "Base") == 0) {
            continue;
        }
        if (!CFArrayContainsValue(result, CFRangeMake(0, CFArrayGetCount(result)), language)) {
            CFArrayAppendValue(result, language);
        }
    }
    CFRelease(localizations);
    return result;
}

CFPropertyListRef MLCopyAppLanguageOverride(void) {
    MLContext context;
    if (MLCreateContext(&context) != MLResultSuccess) {
        return NULL;
    }
    CFPropertyListRef value = MLCopyValue(&context, MLLanguages);
    MLDisposeContext(&context);
    return value;
}

static bool MLValidState(const MLContext *context, CFDictionaryRef backup,
                         MLKey existsKey, MLKey valueKey, bool required) {
    CFBooleanRef exists = CFDictionaryGetValue(backup, context->keys[existsKey]);
    const void *value = CFDictionaryGetValue(backup, context->keys[valueKey]);
    if (!exists) {
        return !required && !value;
    }
    return CFGetTypeID(exists) == CFBooleanGetTypeID() &&
           CFBooleanGetValue(exists) == (value != NULL);
}

static bool MLValidBackup(const MLContext *context, CFPropertyListRef backup) {
    return backup && CFGetTypeID(backup) == CFDictionaryGetTypeID() &&
           MLValidState(context, backup, MLOriginalExists, MLOriginalValue, true) &&
           MLValidState(context, backup, MLLatestExists, MLLatestValue, false) &&
           MLValidState(context, backup, MLPendingExists, MLPendingValue, false);
}

static void MLSetState(const MLContext *context, CFMutableDictionaryRef backup,
                       MLKey existsKey, MLKey valueKey, CFPropertyListRef value) {
    CFDictionarySetValue(backup, context->keys[existsKey], value ? kCFBooleanTrue : kCFBooleanFalse);
    if (value) {
        CFDictionarySetValue(backup, context->keys[valueKey], value);
    } else {
        CFDictionaryRemoveValue(backup, context->keys[valueKey]);
    }
}

static bool MLMatchesState(const MLContext *context, CFDictionaryRef backup,
                           MLKey existsKey, MLKey valueKey, CFPropertyListRef current) {
    CFBooleanRef exists = CFDictionaryGetValue(backup, context->keys[existsKey]);
    if (!exists) {
        return false;
    }
    CFPropertyListRef value = CFDictionaryGetValue(backup, context->keys[valueKey]);
    return CFBooleanGetValue(exists) ? MLValuesEqual(value, current) : current == NULL;
}

MLLanguageResult MLApplyLanguage(CFStringRef language) {
    MLContext context;
    MLLanguageResult result = MLCreateContext(&context);
    if (result != MLResultSuccess) {
        return result;
    }
    CFArrayRef supported = NULL;
    CFArrayRef requested = NULL;
    CFPropertyListRef current = NULL;
    CFPropertyListRef saved = NULL;
    CFMutableDictionaryRef backup = NULL;
    if (language) {
        supported = MLCopySupportedLanguages();
        if (CFGetTypeID(language) != CFStringGetTypeID() || !supported ||
            !CFArrayContainsValue(supported, CFRangeMake(0, CFArrayGetCount(supported)), language)) {
            result = MLResultUnsupportedLanguage;
            goto finish;
        }
        const void *values[] = {language};
        requested = CFArrayCreate(kCFAllocatorDefault, values, 1, &kCFTypeArrayCallBacks);
        if (!requested) {
            result = MLResultAllocationFailed;
            goto finish;
        }
    }
    current = MLCopyValue(&context, MLLanguages);
    if (MLValuesEqual(current, requested)) {
        result = MLResultAlreadySelected;
        goto finish;
    }
    saved = MLCopyValue(&context, MLBackup);
    if (saved && !MLValidBackup(&context, saved)) {
        result = MLResultInvalidBackup;
        goto finish;
    }
    backup = saved ? CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, saved) :
        CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
                                  &kCFTypeDictionaryValueCallBacks);
    if (!backup) {
        result = MLResultAllocationFailed;
        goto finish;
    }
    if (!saved) {
        MLSetState(&context, backup, MLOriginalExists, MLOriginalValue, current);
    }
    MLSetState(&context, backup, MLLatestExists, MLLatestValue, current);
    MLSetState(&context, backup, MLPendingExists, MLPendingValue, requested);
    if (!MLWriteValue(&context, MLBackup, backup) || !MLWriteValue(&context, MLLanguages, requested)) {
        result = MLResultSynchronizationFailed;
        goto finish;
    }
    MLSetState(&context, backup, MLLatestExists, MLLatestValue, requested);
    CFDictionaryRemoveValue(backup, context.keys[MLPendingExists]);
    CFDictionaryRemoveValue(backup, context.keys[MLPendingValue]);
    if (!MLWriteValue(&context, MLBackup, backup)) {
        result = MLResultSynchronizationFailed;
    }
finish:
    if (backup) CFRelease(backup);
    if (saved) CFRelease(saved);
    if (current) CFRelease(current);
    if (requested) CFRelease(requested);
    if (supported) CFRelease(supported);
    MLDisposeContext(&context);
    return result;
}

MLLanguageResult MLRestoreOriginalLanguage(void) {
    MLContext context;
    MLLanguageResult result = MLCreateContext(&context);
    if (result != MLResultSuccess) {
        return result;
    }
    CFPropertyListRef saved = MLCopyValue(&context, MLBackup);
    CFPropertyListRef current = NULL;
    if (!saved) {
        result = MLResultNoBackup;
        goto finish;
    }
    if (!MLValidBackup(&context, saved)) {
        result = MLResultInvalidBackup;
        goto finish;
    }
    current = MLCopyValue(&context, MLLanguages);
    bool managed = MLMatchesState(&context, saved, MLLatestExists, MLLatestValue, current) ||
                   MLMatchesState(&context, saved, MLPendingExists, MLPendingValue, current);
    if (managed) {
        CFPropertyListRef original = CFDictionaryGetValue(saved, context.keys[MLOriginalValue]);
        if (!MLWriteValue(&context, MLLanguages, original)) {
            result = MLResultSynchronizationFailed;
            goto finish;
        }
    } else {
        result = MLResultPreservedExternalChange;
    }
    if (!MLWriteValue(&context, MLBackup, NULL)) {
        result = MLResultSynchronizationFailed;
    }
finish:
    if (current) CFRelease(current);
    if (saved) CFRelease(saved);
    MLDisposeContext(&context);
    return result;
}

bool MLHasPresentedPicker(void) {
    MLContext context;
    if (MLCreateContext(&context) != MLResultSuccess) {
        return false;
    }
    CFPropertyListRef shown = MLCopyValue(&context, MLPickerShown);
    bool result = shown && CFGetTypeID(shown) == CFBooleanGetTypeID() && CFBooleanGetValue(shown);
    if (shown) CFRelease(shown);
    MLDisposeContext(&context);
    return result;
}

bool MLMarkPickerPresented(void) {
    MLContext context;
    if (MLCreateContext(&context) != MLResultSuccess) {
        return false;
    }
    bool result = MLWriteValue(&context, MLPickerShown, kCFBooleanTrue);
    MLDisposeContext(&context);
    return result;
}

const char *MLResultMessage(MLLanguageResult result) {
    switch (result) {
        case MLResultSuccess:
            return "Saved for Maps only. Swipe Maps away in the app switcher, then reopen it.\n\n"
                   "已保存地图的语言设置。请在多任务界面划掉地图，再重新打开。";
        case MLResultAlreadySelected:
            return "This setting is already saved. Fully close and reopen Maps to apply it.\n\n"
                   "此设置已保存。请彻底关闭地图后重新打开，让设置生效。";
        case MLResultNoBackup:
            return "No original-language backup exists. Nothing was changed.\n\n"
                   "没有可恢复的原始语言备份，未做修改。";
        case MLResultPreservedExternalChange:
            return "A later language change was preserved. The old backup was removed.\n\n"
                   "保留了你后来通过其他方式设置的语言，已清除旧备份。";
        case MLResultWrongApplication:
            return "This library only supports Apple Maps.\n\n此插件仅适用于 Apple 地图。";
        case MLResultUnsupportedLanguage:
            return "This language is not in this copy of Maps. Nothing was changed.\n\n"
                   "当前地图版本未包含此语言，未做修改。";
        case MLResultInvalidBackup:
            return "The backup is invalid. Refusing to overwrite it or change the language.\n\n"
                   "备份格式异常，已停止修改，以免覆盖原始设置。";
        case MLResultAllocationFailed:
            return "Could not prepare the language setting. Nothing was changed.\n\n"
                   "无法准备语言设置，未做修改。";
        case MLResultSynchronizationFailed:
            return "The save could not be verified. Some settings may already have changed. "
                   "Fully close and reopen Maps, then check the saved selection.\n\n"
                   "无法确认设置已完整保存，部分修改可能已生效。请彻底关闭并重开地图，再检查选择。";
    }
    return "Unknown result / 未知结果";
}
