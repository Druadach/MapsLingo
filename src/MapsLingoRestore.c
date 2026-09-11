#include "MapsLingoPreferences.h"
#include <dispatch/dispatch.h>
#include <os/log.h>
#include <stdlib.h>
#include <string.h>

static void MLRestoreOnMainQueue(void *context) {
    (void)context;
    if (!MLIsMapsApplication()) {
        return;
    }
    MLLanguageResult result = MLRestoreOriginalLanguage();
    os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT,
                     "[MapsLingoRestore " ML_VERSION "] %{public}s", MLResultMessage(result));
}

__attribute__((constructor)) static void MLInitializeRestore(void) {
    const char *programName = getprogname();
    if (programName && strcmp(programName, "Maps") == 0) {
        dispatch_async_f(dispatch_get_main_queue(), NULL, MLRestoreOnMainQueue);
    }
}
