/*
 * Copyright (C) 2012 Samsung Electronics
 *
 * All rights reserved.
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

#ifndef NavigatorContentUtilsClientEfl_h
#define NavigatorContentUtilsClientEfl_h

#if ENABLE(NAVIGATOR_CONTENT_UTILS)
#include "NavigatorContentUtilsClient.h"

#include <wtf/PassOwnPtr.h>

namespace WebCore {
class NavigatorContentUtilsClientEfl : public WebCore::NavigatorContentUtilsClient {
public:
    explicit NavigatorContentUtilsClientEfl(Evas_Object* view);

    ~NavigatorContentUtilsClientEfl() { }
    virtual void registerProtocolHandler(const String& scheme, const URL& baseURL, const URL&, const String& title);

#if ENABLE(CUSTOM_SCHEME_HANDLER)
    virtual CustomHandlersState isProtocolHandlerRegistered(const String& scheme, const URL& baseURL, const URL&);
    virtual void unregisterProtocolHandler(const String& scheme, const URL& baseURL, const URL&);
#endif

private:
    Evas_Object* m_view;
};
}

#endif
#endif // NavigatorContentUtilsClientEfl_h
