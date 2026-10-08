#import <Foundation/Foundation.h>

/// Streams now-playing changes to stdout as JSON lines, e.g.
/// `{"playing":true,"title":"…","artist":"…"}`, and exits when stdin closes.
/// Never returns. Meant to be called from /usr/bin/perl via DynaLoader.
void glint_now_playing_stream(void);
