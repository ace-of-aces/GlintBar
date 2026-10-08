#import "GlintNowPlaying.h"
#include <dlfcn.h>
#include <unistd.h>

// Since macOS 15.4 MediaRemote answers now-playing queries from third-party processes
// with "nothing is playing". This library runs inside /usr/bin/perl, which is
// Apple-signed and may still ask, and relays the answers to Glint over stdout.
// Commands that need the same standing (seeking) come back over stdin.

typedef void (*MRRegisterForNotificationsFn)(dispatch_queue_t);
typedef void (*MRIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRNowPlayingInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRSetElapsedTimeFn)(double);

static MRIsPlayingFn isPlayingFn;
static MRNowPlayingInfoFn nowPlayingInfoFn;
static MRSetElapsedTimeFn setElapsedTimeFn;
static dispatch_queue_t queue;
static NSData *lastLine;

static void writeLine(NSDictionary *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!json || [json isEqualToData:lastLine]) return;
    lastLine = json;
    fwrite(json.bytes, 1, json.length, stdout);
    fputc('\n', stdout);
    fflush(stdout);
}

static NSString *stringValue(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSNumber *numberValue(NSDictionary *info, NSString *key) {
    id value = info[key];
    return [value isKindOfClass:NSNumber.class] ? value : nil;
}

/// Reads the current state and writes it if it changed. Runs on `queue`.
static void emitState(void) {
    isPlayingFn(queue, ^(Boolean playing) {
        nowPlayingInfoFn(queue, ^(CFDictionaryRef rawInfo) {
            NSDictionary *info = (__bridge NSDictionary *)rawInfo;
            NSMutableDictionary *payload = [@{ @"playing": playing ? @YES : @NO } mutableCopy];
            payload[@"title"] = stringValue(info, @"kMRMediaRemoteNowPlayingInfoTitle");
            payload[@"artist"] = stringValue(info, @"kMRMediaRemoteNowPlayingInfoArtist");
            // Position: `elapsed` was true at `timestamp` and advances at `rate`.
            payload[@"duration"] = numberValue(info, @"kMRMediaRemoteNowPlayingInfoDuration");
            payload[@"elapsed"] = numberValue(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime");
            payload[@"rate"] = numberValue(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate");
            id timestamp = info[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
            if ([timestamp isKindOfClass:NSDate.class]) {
                payload[@"timestamp"] = @([(NSDate *)timestamp timeIntervalSince1970]);
            }
            writeLine(payload);
        });
    });
}

static NSString *notificationName(void *mediaRemote, const char *symbol) {
    CFStringRef *name = dlsym(mediaRemote, symbol);
    return name ? (__bridge NSString *)*name : nil;
}

void glint_now_playing_stream(void) {
    @autoreleasepool {
        void *mediaRemote = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
        MRRegisterForNotificationsFn registerFn = mediaRemote ? dlsym(mediaRemote, "MRMediaRemoteRegisterForNowPlayingNotifications") : NULL;
        isPlayingFn = mediaRemote ? dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingApplicationIsPlaying") : NULL;
        nowPlayingInfoFn = mediaRemote ? dlsym(mediaRemote, "MRMediaRemoteGetNowPlayingInfo") : NULL;
        setElapsedTimeFn = mediaRemote ? dlsym(mediaRemote, "MRMediaRemoteSetElapsedTime") : NULL;
        if (!registerFn || !isPlayingFn || !nowPlayingInfoFn) {
            writeLine(@{ @"error": @"MediaRemote unavailable" });
            exit(1);
        }

        // Everything runs on the main queue, serviced by CFRunLoopRun below. (A private
        // serial queue stalls after the first nested MediaRemote callback.)
        queue = dispatch_get_main_queue();
        registerFn(queue);

        const char *symbols[] = {
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        };
        for (size_t i = 0; i < sizeof symbols / sizeof *symbols; i++) {
            NSString *name = notificationName(mediaRemote, symbols[i]);
            if (!name) continue;
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                emitState();
            }];
        }

        // Safety net for notifications that never arrive.
        static dispatch_source_t poll;
        poll = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
        dispatch_source_set_timer(poll, DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(poll, ^{ emitState(); });
        dispatch_resume(poll);

        // Glint sends commands as lines on stdin ("seek <seconds>") and holds it open;
        // when it quits or crashes, the pipe closes and we follow. The read blocks, so it
        // gets a thread of its own.
        [NSThread detachNewThreadWithBlock:^{
            char *line = NULL;
            size_t capacity = 0;
            while (getline(&line, &capacity, stdin) > 0) {
                double seconds;
                if (sscanf(line, "seek %lf", &seconds) == 1 && setElapsedTimeFn) {
                    dispatch_async(queue, ^{
                        setElapsedTimeFn(seconds);
                        emitState();
                    });
                }
            }
            exit(0);
        }];
    }
    // MediaRemote delivers its updates through the main run loop.
    CFRunLoopRun();
}
