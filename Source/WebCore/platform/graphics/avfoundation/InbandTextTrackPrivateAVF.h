/*
 * Copyright (C) 2012-2014 Apple Inc. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#ifndef InbandTextTrackPrivateAVF_h
#define InbandTextTrackPrivateAVF_h

#if ENABLE(VIDEO) && (USE(AVFOUNDATION) || PLATFORM(IOS))

#include "InbandTextTrackPrivate.h"
#include "InbandTextTrackPrivateClient.h"
#include <wtf/text/StringBuilder.h>

namespace WebCore {

class AVFInbandTrackParent {
public:
    virtual ~AVFInbandTrackParent();
    
    virtual void trackModeChanged() = 0;
};

class InbandTextTrackPrivateAVF : public InbandTextTrackPrivate {
public:
    virtual ~InbandTextTrackPrivateAVF();

    virtual void setMode(InbandTextTrackPrivate::Mode) override;

    virtual int trackIndex() const override { return m_index; }
    void setTextTrackIndex(int index) { m_index = index; }

    virtual void disconnect();

    bool hasBeenReported() const { return m_hasBeenReported; }
    void setHasBeenReported(bool reported) { m_hasBeenReported = reported; }

    virtual void processCue(CFArrayRef, double);
    virtual void resetCueValues();

    void beginSeeking();
    void endSeeking() { m_seeking = false; }
    bool seeking() const { return m_seeking; }
    
    enum Category {
        LegacyClosedCaption,
        OutOfBand,
        InBand
    };
    virtual Category textTrackCategory() const = 0;
    
    virtual double startTimeVariance() const override { return 0.25; }
    
protected:
    InbandTextTrackPrivateAVF(AVFInbandTrackParent*);

    void processCueAttributes(CFAttributedStringRef, GenericCueData*);
    void removeCompletedCues();

    double m_currentCueStartTime;
    double m_currentCueEndTime;

    Vector<RefPtr<GenericCueData>> m_cues;
    AVFInbandTrackParent* m_owner;

    enum PendingCueStatus {
        None,
        DeliveredDuringSeek,
        Valid
    };
    PendingCueStatus m_pendingCueStatus;

    int m_index;
    bool m_hasBeenReported;
    bool m_seeking;
};

} // namespace WebCore

#endif //  ENABLE(VIDEO) && (USE(AVFOUNDATION) || PLATFORM(IOS))

#endif // InbandTextTrackPrivateAVF_h
