#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "MapsLingoPreferences.h"
#include <dispatch/dispatch.h>
#include <os/log.h>
#include <stdlib.h>
#include <string.h>

static id MLCallbacks;
static NSHashTable<UIWindow *> *MLInstalledWindows;
static __weak UINavigationController *MLPicker;
static __weak UITableViewController *MLPickerTable;
static NSArray<NSString *> *MLLanguageIDs;
static id MLSavedOverride;
static NSLocale *MLEnglishLocale;
static BOOL MLRefreshScheduled;
static BOOL MLShouldShowWelcome;
static BOOL MLNeedsWelcomeMarker;
static NSUInteger MLRetryCount;

static void MLScheduleRefresh(void);
static BOOL MLPresentPicker(UIWindow *window);

static NSString *MLText(const char *text) {
    return [NSString stringWithUTF8String:text];
}

static void MLReloadSelection(void) {
    MLSavedOverride = CFBridgingRelease(MLCopyAppLanguageOverride());
    [MLPickerTable.tableView reloadData];
}

static void MLClosePicker(id target, SEL command) {
    (void)target;
    (void)command;
    [MLPicker dismissViewControllerAnimated:YES completion:nil];
}

static NSInteger MLNumberOfSections(id target, SEL command, UITableView *tableView) {
    (void)target;
    (void)command;
    (void)tableView;
    return 2;
}

static NSInteger MLNumberOfRows(id target, SEL command, UITableView *tableView, NSInteger section) {
    (void)target;
    (void)command;
    (void)tableView;
    return section == 0 ? (NSInteger)MLLanguageIDs.count + 1 : 1;
}

static NSString *MLHeaderTitle(id target, SEL command, UITableView *tableView, NSInteger section) {
    (void)target;
    (void)command;
    (void)tableView;
    return MLText(section == 0 ? "Language / 语言" : "Recovery / 恢复");
}

static NSString *MLFooterTitle(id target, SEL command, UITableView *tableView, NSInteger section) {
    (void)target;
    (void)command;
    (void)tableView;
    if (section == 0) {
        return MLText("Only languages bundled with Maps are listed. The checkmark shows the SAVED setting, "
                      "not the language of the currently open screen. Fully close and reopen Maps after a change.\n\n"
                      "仅列出地图自带的语言。勾选表示已保存的设置，不代表当前界面已切换；修改后请彻底关闭并重开地图。");
    }
    return MLText("To reopen this panel, hold TWO fingers still on Maps for 1.2 seconds. "
                  "Restore Original recovers the setting saved before this plug-in. "
                  "Follow System removes only Maps' language override.\n\n"
                  "以后在地图内双指按住不动 1.2 秒，可再次打开此面板。“恢复原设置”恢复首次修改前的备份，"
                  "“跟随系统”只移除地图的独立语言设置。\n\n"
                  "MapsLingo " ML_VERSION " · No telemetry / 无遥测");
}

static BOOL MLIsLanguageSelected(NSString *language) {
    return [MLSavedOverride isKindOfClass:[NSArray class]] &&
           [MLSavedOverride count] == 1 && [[MLSavedOverride firstObject] isEqual:language];
}

static UITableViewCell *MLCellForRow(id target, SEL command, UITableView *tableView, NSIndexPath *indexPath) {
    (void)target;
    (void)command;
    NSString *reuseID = MLText("MapsLingoOption");
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseID];
    }
    cell.textLabel.numberOfLines = 0;
    cell.detailTextLabel.numberOfLines = 0;
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.textColor = [UIColor labelColor];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    if (indexPath.section == 1) {
        cell.textLabel.text = MLText("Restore Original / 恢复原设置");
        cell.detailTextLabel.text = MLText("Restore the first backup; preserve later external changes.");
        return cell;
    }
    if (indexPath.row == 0) {
        cell.textLabel.text = MLText("Follow System / 跟随系统");
        cell.detailTextLabel.text = MLText("Use the system's preferred languages / 使用系统首选语言");
        if (!MLSavedOverride) cell.accessoryType = UITableViewCellAccessoryCheckmark;
        return cell;
    }
    NSString *identifier = MLLanguageIDs[(NSUInteger)indexPath.row - 1];
    NSLocale *nativeLocale = [[NSLocale alloc] initWithLocaleIdentifier:identifier];
    cell.textLabel.text = [nativeLocale displayNameForKey:NSLocaleIdentifier value:identifier] ?: identifier;
    NSString *englishName = [MLEnglishLocale displayNameForKey:NSLocaleIdentifier value:identifier] ?: identifier;
    cell.detailTextLabel.text = [NSString stringWithFormat:MLText("%@ · %@"), englishName, identifier];
    if (MLIsLanguageSelected(identifier)) cell.accessoryType = UITableViewCellAccessoryCheckmark;
    return cell;
}

static void MLDidSelectRow(id target, SEL command, UITableView *tableView, NSIndexPath *indexPath) {
    (void)target;
    (void)command;
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    MLLanguageResult result;
    if (indexPath.section == 1) {
        result = MLRestoreOriginalLanguage();
    } else {
        NSString *identifier = indexPath.row == 0 ? nil : MLLanguageIDs[(NSUInteger)indexPath.row - 1];
        result = MLApplyLanguage((__bridge CFStringRef)identifier);
    }
    os_log(OS_LOG_DEFAULT, "[MapsLingo " ML_VERSION "] Language action result: %d", (int)result);
    MLReloadSelection();
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:MLText("Maps Language")
        message:MLText(MLResultMessage(result)) preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:MLText("OK / 好") style:UIAlertActionStyleDefault handler:nil]];
    [MLPickerTable presentViewController:alert animated:YES completion:nil];
}

static void MLOpenFromGesture(id target, SEL command, UILongPressGestureRecognizer *gesture) {
    (void)target;
    (void)command;
    if (gesture.state == UIGestureRecognizerStateBegan) {
        MLPresentPicker((UIWindow *)gesture.view);
    }
}

static BOOL MLAllowSimultaneousGestures(id target, SEL command, UIGestureRecognizer *gesture,
                                        UIGestureRecognizer *otherGesture) {
    (void)target;
    (void)command;
    (void)gesture;
    (void)otherGesture;
    return YES;
}

static void MLRefreshAfterNotification(void *context) {
    (void)context;
    MLRetryCount = 0;
    MLScheduleRefresh();
}

static void MLApplicationChanged(id target, SEL command, NSNotification *notification) {
    (void)target;
    (void)command;
    (void)notification;
    dispatch_async_f(dispatch_get_main_queue(), NULL, MLRefreshAfterNotification);
}

static BOOL MLAddProtocolMethod(Class callbackClass, const char *protocolName,
                                const char *selectorName, IMP implementation) {
    Protocol *protocol = objc_getProtocol(protocolName);
    SEL selector = sel_registerName(selectorName);
    if (!protocol) return NO;
    struct objc_method_description method = protocol_getMethodDescription(protocol, selector, YES, YES);
    if (!method.types) method = protocol_getMethodDescription(protocol, selector, NO, YES);
    return method.types && class_addMethod(callbackClass, selector, implementation, method.types);
}

static BOOL MLRegisterCallbacks(void) {
    Class superclass = objc_getClass("NSObject");
    if (!superclass) return NO;
    Class callbackClass = objc_allocateClassPair(superclass, "ML031LanguageCallbacks", 0);
    if (!callbackClass) return NO;
    const char *protocolNames[] = {"UITableViewDataSource", "UITableViewDelegate", "UIGestureRecognizerDelegate"};
    for (size_t index = 0; index < sizeof(protocolNames) / sizeof(protocolNames[0]); index++) {
        Protocol *protocol = objc_getProtocol(protocolNames[index]);
        if (!protocol || !class_addProtocol(callbackClass, protocol)) {
            objc_disposeClassPair(callbackClass);
            return NO;
        }
    }
    BOOL installed =
        MLAddProtocolMethod(callbackClass, "UITableViewDataSource", "numberOfSectionsInTableView:",
                            (IMP)MLNumberOfSections) &&
        MLAddProtocolMethod(callbackClass, "UITableViewDataSource", "tableView:numberOfRowsInSection:",
                            (IMP)MLNumberOfRows) &&
        MLAddProtocolMethod(callbackClass, "UITableViewDataSource", "tableView:cellForRowAtIndexPath:",
                            (IMP)MLCellForRow) &&
        MLAddProtocolMethod(callbackClass, "UITableViewDataSource", "tableView:titleForHeaderInSection:",
                            (IMP)MLHeaderTitle) &&
        MLAddProtocolMethod(callbackClass, "UITableViewDataSource", "tableView:titleForFooterInSection:",
                            (IMP)MLFooterTitle) &&
        MLAddProtocolMethod(callbackClass, "UITableViewDelegate", "tableView:didSelectRowAtIndexPath:",
                            (IMP)MLDidSelectRow) &&
        MLAddProtocolMethod(callbackClass, "UIGestureRecognizerDelegate",
                            "gestureRecognizer:shouldRecognizeSimultaneouslyWithGestureRecognizer:",
                            (IMP)MLAllowSimultaneousGestures) &&
        class_addMethod(callbackClass, sel_registerName("ml_closePicker"), (IMP)MLClosePicker, "v@:") &&
        class_addMethod(callbackClass, sel_registerName("ml_openFromGesture:"), (IMP)MLOpenFromGesture, "v@:@") &&
        class_addMethod(callbackClass, sel_registerName("ml_applicationChanged:"), (IMP)MLApplicationChanged, "v@:@");
    if (!installed) {
        objc_disposeClassPair(callbackClass);
        return NO;
    }
    objc_registerClassPair(callbackClass);
    MLCallbacks = [[callbackClass alloc] init];
    return MLCallbacks != nil;
}

static NSArray<UIWindow *> *MLForegroundWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState != UISceneActivationStateForegroundActive ||
            ![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (!window.hidden && window.alpha > 0 && window.windowLevel == UIWindowLevelNormal &&
                window.rootViewController) {
                [windows addObject:window];
            }
        }
    }
    return windows;
}

static UIViewController *MLVisibleController(UIViewController *controller) {
    while (controller) {
        UIViewController *next = controller.presentedViewController;
        if (!next && [controller isKindOfClass:[UINavigationController class]]) {
            next = ((UINavigationController *)controller).visibleViewController;
        }
        if (!next && [controller isKindOfClass:[UITabBarController class]]) {
            next = ((UITabBarController *)controller).selectedViewController;
        }
        if (!next || next == controller) break;
        controller = next;
    }
    return controller;
}

static BOOL MLPresentPicker(UIWindow *window) {
    if (!MLCallbacks || !window || MLPicker ||
        [UIApplication sharedApplication].applicationState != UIApplicationStateActive) {
        return NO;
    }
    UIViewController *presenter = MLVisibleController(window.rootViewController);
    if (!presenter || !presenter.viewIfLoaded.window || presenter.isBeingDismissed ||
        presenter.isBeingPresented || presenter.transitionCoordinator ||
        [presenter isKindOfClass:[UIAlertController class]]) {
        return NO;
    }
    NSArray<NSString *> *available = CFBridgingRelease(MLCopySupportedLanguages());
    NSMutableArray<NSString *> *ordered = [[available sortedArrayUsingSelector:
        @selector(localizedCaseInsensitiveCompare:)] mutableCopy];
    if (!ordered) ordered = [NSMutableArray array];
    NSArray<NSString *> *priority = [NSArray arrayWithObjects:
        MLText("zh-Hans"), MLText("zh-Hant"), MLText("en"), nil];
    for (NSString *language in [priority reverseObjectEnumerator]) {
        if ([ordered containsObject:language]) {
            [ordered removeObject:language];
            [ordered insertObject:language atIndex:0];
        }
    }
    MLLanguageIDs = ordered;
    MLEnglishLocale = [[NSLocale alloc] initWithLocaleIdentifier:MLText("en_US")];
    UITableViewController *controller = [[UITableViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
    controller.title = MLText("Maps Language");
    controller.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:MLCallbacks action:sel_registerName("ml_closePicker")];
    controller.tableView.dataSource = (id<UITableViewDataSource>)MLCallbacks;
    controller.tableView.delegate = (id<UITableViewDelegate>)MLCallbacks;
    controller.tableView.rowHeight = UITableViewAutomaticDimension;
    controller.tableView.estimatedRowHeight = 64;
    MLPickerTable = controller;
    MLReloadSelection();
    UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:controller];
    navigation.modalPresentationStyle = UIModalPresentationFormSheet;
    MLPicker = navigation;
    MLShouldShowWelcome = NO;
    MLNeedsWelcomeMarker = !MLHasPresentedPicker();
    MLRetryCount = 0;
    [presenter presentViewController:navigation animated:YES completion:nil];
    MLScheduleRefresh();
    return YES;
}

static void MLRefreshOnMainQueue(void *context) {
    (void)context;
    MLRefreshScheduled = NO;
    UINavigationController *picker = MLPicker;
    if (MLNeedsWelcomeMarker && picker.viewIfLoaded.window &&
        !picker.isBeingPresented && !picker.isBeingDismissed) {
        MLNeedsWelcomeMarker = NO;
        if (!MLMarkPickerPresented()) {
            os_log(OS_LOG_DEFAULT, "[MapsLingo " ML_VERSION "] Could not save the first-run marker.");
        }
    }
    NSArray<UIWindow *> *windows = MLForegroundWindows();
    UIWindow *preferredWindow = nil;
    for (UIWindow *window in windows) {
        if (!preferredWindow || window.isKeyWindow) preferredWindow = window;
        if ([MLInstalledWindows containsObject:window]) continue;
        UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc]
            initWithTarget:MLCallbacks action:sel_registerName("ml_openFromGesture:")];
        gesture.numberOfTouchesRequired = 2;
        gesture.minimumPressDuration = 1.2;
        gesture.cancelsTouchesInView = NO;
        gesture.delaysTouchesBegan = NO;
        gesture.delaysTouchesEnded = NO;
        gesture.delegate = (id<UIGestureRecognizerDelegate>)MLCallbacks;
        [window addGestureRecognizer:gesture];
        [MLInstalledWindows addObject:window];
    }
    if (MLShouldShowWelcome) MLPresentPicker(preferredWindow);
    if ((MLShouldShowWelcome || MLNeedsWelcomeMarker) && MLRetryCount < 12) {
        MLRetryCount++;
        MLScheduleRefresh();
    }
}

static void MLScheduleRefresh(void) {
    if (MLRefreshScheduled) return;
    MLRefreshScheduled = YES;
    dispatch_after_f(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC / 2),
                     dispatch_get_main_queue(), NULL, MLRefreshOnMainQueue);
}

static void MLInitializeOnMainQueue(void *context) {
    (void)context;
    if (!MLIsMapsApplication() || MLCallbacks) return;
    if (!MLRegisterCallbacks()) {
        os_log(OS_LOG_DEFAULT, "[MapsLingo " ML_VERSION "] Runtime callback registration failed; picker disabled.");
        return;
    }
    MLInstalledWindows = [NSHashTable weakObjectsHashTable];
    MLShouldShowWelcome = !MLHasPresentedPicker();
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    SEL changed = sel_registerName("ml_applicationChanged:");
    [center addObserver:MLCallbacks selector:changed name:UIApplicationDidBecomeActiveNotification object:nil];
    [center addObserver:MLCallbacks selector:changed name:UIWindowDidBecomeKeyNotification object:nil];
    [center addObserver:MLCallbacks selector:changed name:UIWindowDidBecomeVisibleNotification object:nil];
    MLScheduleRefresh();
    os_log(OS_LOG_DEFAULT, "[MapsLingo " ML_VERSION "] Runtime callbacks registered; no existing methods replaced.");
}

__attribute__((constructor)) static void MLInitializePicker(void) {
    const char *programName = getprogname();
    if (programName && strcmp(programName, "Maps") == 0) {
        dispatch_async_f(dispatch_get_main_queue(), NULL, MLInitializeOnMainQueue);
    }
}
