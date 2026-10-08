#import <Foundation/Foundation.h>

/// Streams now-playing changes to stdout as JSON lines, e.g.
/// `{"playing":true,"title":"…","artist":"…","duration":215,"elapsed":42.1,"rate":1,"timestamp":…}`,
/// accepts `seek <seconds>` lines on stdin, and exits when stdin closes.
/// Never returns. Meant to be called from /usr/bin/perl via DynaLoader.
void glint_now_playing_stream(void);
