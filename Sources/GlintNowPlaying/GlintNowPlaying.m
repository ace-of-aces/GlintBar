#import "GlintNowPlaying.h"
#include <dlfcn.h>
#include <unistd.h>

// Since macOS 15.4 MediaRemote answers now-playing queries from third-party processes
// with "nothing is playing". This library runs inside /usr/bin/perl, which is
// Apple-signed and may still ask, and relays the answers to Glint over stdout.

typedef void (*MRRegisterForNotificationsFn)(dispatch_queue_t);
typedef void (*MRIsPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRNowPlayingInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));

static MRIsPlayingFn isPlayingFn;
static MRNowPlayingInfoFn nowPlayingInfoFn;
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

/// Reads the current state and writes it if it changed. Runs on `queue`.
static void emitState(void) {
    isPlayingFn(queue, ^(Boolean playing) {
        nowPlayingInfoFn(queue, ^(CFDictionaryRef rawInfo) {
            NSDictionary *info = (__bridge NSDictionary *)rawInfo;
            NSMutableDictionary *payload = [@{ @"playing": playing ? @YES : @NO } mutableCopy];
            payload[@"title"] = stringValue(info, @"kMRMediaRemoteNowPlayingInfoTitle");
            payload[@"artist"] = stringValue(info, @"kMRMediaRemoteNowPlayingInfoArtist");
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

        // Glint holds our stdin open; when it quits or crashes, the pipe closes and we follow.
        // The read blocks, so it gets a thread of its own rather than `queue`.
        [NSThread detachNewThreadWithBlock:^{
            char buffer[64];
            while (read(STDIN_FILENO, buffer, sizeof buffer) > 0) {}
            exit(0);
        }];
    }
    // MediaRemote delivers its updates through the main run loop.
    CFRunLoopRun();
}
