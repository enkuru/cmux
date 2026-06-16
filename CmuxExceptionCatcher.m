#import "CmuxExceptionCatcher.h"

NSException * _Nullable cmux_runCatchingNSException(void (NS_NOESCAPE ^block)(void)) {
    @try {
        block();
        return nil;
    } @catch (NSException *exception) {
        return exception;
    }
}
