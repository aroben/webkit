/*
 * Copyright (C) 2013 Google Inc. All rights reserved.
 * Copyright (C) 2013 Orange
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are
 * met:
 *
 *     * Redistributions of source code must retain the above copyright
 * notice, this list of conditions and the following disclaimer.
 *     * Redistributions in binary form must reproduce the above
 * copyright notice, this list of conditions and the following disclaimer
 * in the documentation and/or other materials provided with the
 * distribution.
 *     * Neither the name of Google Inc. nor the names of its
 * contributors may be used to endorse or promote products derived from
 * this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#ifndef MediaSourceGStreamer_h
#define MediaSourceGStreamer_h

#if ENABLE(MEDIA_SOURCE) && USE(GSTREAMER)
#include "MediaSource.h"
#include "WebKitMediaSourceGStreamer.h"

namespace WebCore {

class MediaSourceGStreamer final : public MediaSourcePrivate {
public:
    static void open(MediaSourcePrivateClient*, WebKitMediaSrc*);
    ~MediaSourceGStreamer();
    AddStatus addSourceBuffer(const ContentType&, RefPtr<SourceBufferPrivate>&);
    MediaTime duration() { return m_duration; }
    void setDuration(const MediaTime&);
    void markEndOfStream(EndOfStreamStatus);
    void unmarkEndOfStream();
    MediaPlayer::ReadyState readyState() const { return m_readyState; }
    void setReadyState(MediaPlayer::ReadyState readyState) { m_readyState = readyState; }

private:
    RefPtr<MediaSourceClientGstreamer> m_client;
    MediaSourceGStreamer(WebKitMediaSrc*);
    MediaTime m_duration;
    MediaPlayer::ReadyState m_readyState;
};

}

#endif
#endif
