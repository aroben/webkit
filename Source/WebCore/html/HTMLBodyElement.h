/*
 * Copyright (C) 1999 Lars Knoll (knoll@kde.org)
 *           (C) 1999 Antti Koivisto (koivisto@kde.org)
 *           (C) 2000 Simon Hausmann <hausmann@kde.org>
 * Copyright (C) 2004, 2006, 2009, 2010 Apple Inc. All rights reserved.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public License
 * along with this library; see the file COPYING.LIB.  If not, write to
 * the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 */

#ifndef HTMLBodyElement_h
#define HTMLBodyElement_h

#include "HTMLElement.h"

namespace WebCore {

class Document;

class HTMLBodyElement final : public HTMLElement {
public:
    static PassRefPtr<HTMLBodyElement> create(Document&);
    static PassRefPtr<HTMLBodyElement> create(const QualifiedName&, Document&);
    virtual ~HTMLBodyElement();

    // Declared virtual in Element
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(blur);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(error);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(focus);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(load);

    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(beforeunload);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(hashchange);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(message);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(offline);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(online);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(popstate);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(resize);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(storage);
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(unload);

#if ENABLE(ORIENTATION_EVENTS)
    DEFINE_WINDOW_ATTRIBUTE_EVENT_LISTENER(orientationchange);
#endif

private:
    HTMLBodyElement(const QualifiedName&, Document&);

    virtual void parseAttribute(const QualifiedName&, const AtomicString&) override;
    virtual bool isPresentationAttribute(const QualifiedName&) const override;
    virtual void collectStyleForPresentationAttribute(const QualifiedName&, const AtomicString&, MutableStyleProperties&) override;

    virtual InsertionNotificationRequest insertedInto(ContainerNode&) override;

    virtual bool isURLAttribute(const Attribute&) const override;
    
    virtual bool supportsFocus() const override;

    virtual double scrollLeft() override;
    virtual void setScrollLeft(double) override;
    
    virtual double scrollTop() override;
    virtual void setScrollTop(double) override;
    
    virtual double scrollHeight() override;
    virtual double scrollWidth() override;
    
    virtual void addSubresourceAttributeURLs(ListHashSet<URL>&) const override;
};

NODE_TYPE_CASTS(HTMLBodyElement)

} //namespace

#endif
