/*
 * Copyright (C) 2014 Apple Inc. All rights reserved.
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
 * THIS SOFTWARE IS PROVIDED BY APPLE INC. AND ITS CONTRIBUTORS ``AS IS''
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 * THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL APPLE INC. OR ITS CONTRIBUTORS
 * BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "config.h"
#import "TelephoneNumberOverlayController.h"

#if ENABLE(TELEPHONE_NUMBER_DETECTION) && PLATFORM(MAC)

#import <WebCore/Document.h>
#import <WebCore/FloatQuad.h>
#import <WebCore/FrameView.h>
#import <WebCore/GraphicsContext.h>
#import <WebCore/MainFrame.h>
#import <WebCore/SoftLinking.h>

#if __has_include(<DataDetectors/DDHighlightDrawing.h>)
#import <DataDetectors/DDHighlightDrawing.h>
#else
typedef void* DDHighlightRef;
#endif

#if __has_include(<DataDetectors/DDHighlightDrawing_Private.h>)
#import <DataDetectors/DDHighlightDrawing_Private.h>
#endif

SOFT_LINK_PRIVATE_FRAMEWORK_OPTIONAL(DataDetectors)
SOFT_LINK(DataDetectors, DDHighlightCreateWithRectsInVisibleRect, DDHighlightRef, (CFAllocatorRef allocator, CGRect * rects, CFIndex count, CGRect globalVisibleRect, Boolean withArrow), (allocator, rects, count, globalVisibleRect, withArrow))
SOFT_LINK(DataDetectors, DDHighlightGetLayerWithContext, CGLayerRef, (DDHighlightRef highlight, CGContextRef context), (highlight, context))
SOFT_LINK(DataDetectors, DDHighlightGetBoundingRect, CGRect, (DDHighlightRef highlight), (highlight))
SOFT_LINK(DataDetectors, DDHighlightPointIsOnHighlight, Boolean, (DDHighlightRef highlight, CGPoint point, Boolean* onButton), (highlight, point, onButton))

using namespace WebCore;

namespace WebKit {

static IntRect textQuadsToBoundingRectForRange(Range& range)
{
    Vector<FloatQuad> textQuads;
    range.textQuads(textQuads);
    FloatRect boundingRect;
    for (auto& quad : textQuads)
        boundingRect.unite(quad.boundingBox());
    return enclosingIntRect(boundingRect);
}

void TelephoneNumberOverlayController::drawRect(PageOverlay* overlay, WebCore::GraphicsContext& graphicsContext, const WebCore::IntRect& dirtyRect)
{
    // Only draw an individual telephone number highlight if there is precisely one telephone number selected.
    if (m_currentSelectionRanges.isEmpty() || m_currentSelectionRanges.size() > 1) {
        clearHighlights();
        return;
    }

    CGContextRef cgContext = graphicsContext.platformContext();
    auto& range = m_currentSelectionRanges[0];

    // FIXME: This will choke if the range wraps around the edge of the view.
    // What should we do in that case?
    IntRect rect = textQuadsToBoundingRectForRange(*range);

    // Convert to the main document's coordinate space.
    // FIXME: It's a little crazy to call contentsToWindow and then windowToContents in order to get the right coordinate space.
    // We should consider adding conversion functions to ScrollView for contentsToDocument(). Right now, contentsToRootView() is
    // not equivalent to what we need when you have a topContentInset or a header banner.
    FrameView* viewForRange = range->ownerDocument().view();
    if (!viewForRange)
        return;
    FrameView& mainFrameView = *m_webPage->corePage()->mainFrame().view();
    rect.setLocation(mainFrameView.windowToContents(viewForRange->contentsToWindow(rect.location())));

    // If the selection rect is completely outside this drawing tile, don't process it further
    if (!rect.intersects(dirtyRect))
        return;

    CGRect cgRects[] = { (CGRect)rect };

    RetainPtr<DDHighlightRef> highlight = adoptCF(DDHighlightCreateWithRectsInVisibleRect(nullptr, cgRects, 1, viewForRange->boundsRect(), true));
    m_highlightedTelephoneNumberData = TelephoneNumberData::create(range.get(), highlight.get());

    Boolean onButton;
    bool onHighlight = DDHighlightPointIsOnHighlight(highlight.get(), (CGPoint)m_lastMouseMovePosition, &onButton);

    m_highlightedTelephoneNumberData->setHovered(onHighlight);

    // Don't draw the highlight if the mouse is not hovered over it.
    if (!onHighlight)
        return;

    // Check and see if the mouse is currently down inside this highlight's button.
    if (m_mouseDownPosition != IntPoint() && onButton)
        m_currentMouseDownNumber = m_highlightedTelephoneNumberData;
    
    CGLayerRef highlightLayer = DDHighlightGetLayerWithContext(highlight.get(), cgContext);
    CGRect highlightBoundingRect = DDHighlightGetBoundingRect(highlight.get());
    
    GraphicsContextStateSaver stateSaver(graphicsContext);

    graphicsContext.translate(toFloatSize(highlightBoundingRect.origin));
    graphicsContext.scale(FloatSize(1, -1));
    graphicsContext.translate(FloatSize(0, -highlightBoundingRect.size.height));
    
    CGRect highlightDrawRect = highlightBoundingRect;
    highlightDrawRect.origin.x = 0;
    highlightDrawRect.origin.y = 0;
    
    CGContextDrawLayerInRect(cgContext, highlightDrawRect, highlightLayer);
}
    
void TelephoneNumberOverlayController::handleTelephoneClick(TelephoneNumberData* number, const IntPoint& point)
{
    ASSERT(number);

    m_webPage->handleTelephoneNumberClick(number->range()->text(), point);
}
    
bool TelephoneNumberOverlayController::mouseEvent(PageOverlay*, const WebMouseEvent& event)
{
    m_lastMouseMovePosition = m_webPage->corePage()->mainFrame().view()->rootViewToContents(event.position());

    if (m_highlightedTelephoneNumberData) {
        Boolean onButton;
        bool hovered = DDHighlightPointIsOnHighlight(m_highlightedTelephoneNumberData->highlight(), (CGPoint)m_lastMouseMovePosition, &onButton);

        if (hovered != m_highlightedTelephoneNumberData->isHovered())
            m_telephoneNumberOverlay->setNeedsDisplay();

        m_highlightedTelephoneNumberData->setHovered(hovered);
    }

    // If this event has nothing to do with the left button, it clears the current mouse down tracking and we're done processing it.
    if (event.button() != WebMouseEvent::LeftButton) {
        clearMouseDownInformation();
        return false;
    }
    
    RefPtr<TelephoneNumberData> currentNumber = m_currentMouseDownNumber;
    
    // Check and see if the mouse went up and we have a current mouse down highlight button.
    if (event.type() == WebEvent::MouseUp && currentNumber) {
        clearMouseDownInformation();
        
        // If the mouse lifted while still over the highlight button that it went down on, then that is a click.
        Boolean onButton;
        if (DDHighlightPointIsOnHighlight(currentNumber->highlight(), (CGPoint)m_lastMouseMovePosition, &onButton) && onButton) {
            handleTelephoneClick(currentNumber.get(), m_webPage->corePage()->mainFrame().view()->contentsToWindow(m_lastMouseMovePosition));
            
            return true;
        }
        
        return false;
    }
    
    // Check and see if the mouse moved within the confines of the DD highlight button.
    if (event.type() == WebEvent::MouseMove && currentNumber) {
        Boolean onButton;
        
        // Moving with the mouse button down is okay as long as the mouse never leaves the highlight button.
        if (DDHighlightPointIsOnHighlight(currentNumber->highlight(), (CGPoint)m_lastMouseMovePosition, &onButton) && onButton)
            return true;
        
        clearMouseDownInformation();
        
        return false;
    }
    
    // Check and see if the mouse went down over a DD highlight button.
    if (event.type() == WebEvent::MouseDown) {
        ASSERT(!m_currentMouseDownNumber);
        
        Boolean onButton;
        if (DDHighlightPointIsOnHighlight(m_highlightedTelephoneNumberData->highlight(), (CGPoint)m_lastMouseMovePosition, &onButton) && onButton) {
            m_mouseDownPosition = m_lastMouseMovePosition;
            m_currentMouseDownNumber = m_highlightedTelephoneNumberData;
            
            m_telephoneNumberOverlay->setNeedsDisplay();
            return true;
        }

        return false;
    }
        
    return false;
}
    
void TelephoneNumberOverlayController::clearMouseDownInformation()
{
    m_currentMouseDownNumber = nullptr;
    m_mouseDownPosition = IntPoint();
}
    
void TelephoneNumberOverlayController::clearHighlights()
{
    m_highlightedTelephoneNumberData = nullptr;
    m_currentMouseDownNumber = nullptr;
}
    
}

#endif // ENABLE(TELEPHONE_NUMBER_DETECTION) && PLATFORM(MAC)
