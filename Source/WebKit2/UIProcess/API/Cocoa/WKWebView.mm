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
#import "WKWebViewInternal.h"

#if WK_API_ENABLED

#import "APIFormClient.h"
#import "FindClient.h"
#import "NavigationState.h"
#import "RemoteLayerTreeTransaction.h"
#import "RemoteObjectRegistry.h"
#import "RemoteObjectRegistryMessages.h"
#import "UIDelegate.h"
#import "ViewGestureController.h"
#import "ViewSnapshotStore.h"
#import "WKBackForwardListInternal.h"
#import "WKBackForwardListItemInternal.h"
#import "WKBrowsingContextHandleInternal.h"
#import "WKErrorInternal.h"
#import "WKHistoryDelegatePrivate.h"
#import "WKNSData.h"
#import "WKNSURLExtras.h"
#import "WKNavigationDelegate.h"
#import "WKNavigationInternal.h"
#import "WKPreferencesInternal.h"
#import "WKProcessPoolInternal.h"
#import "WKUIDelegate.h"
#import "WKUIDelegatePrivate.h"
#import "WKUserContentControllerInternal.h"
#import "WKWebViewConfigurationInternal.h"
#import "WKWebViewContentProvider.h"
#import "WebBackForwardList.h"
#import "WebCertificateInfo.h"
#import "WebContext.h"
#import "WebFormSubmissionListenerProxy.h"
#import "WebKitSystemInterface.h"
#import "WebPageGroup.h"
#import "WebPageProxy.h"
#import "WebPreferencesKeys.h"
#import "WebProcessProxy.h"
#import "WebSerializedScriptValue.h"
#import "_WKFindDelegate.h"
#import "_WKFormDelegate.h"
#import "_WKRemoteObjectRegistryInternal.h"
#import "_WKVisitedLinkProviderInternal.h"
#import "_WKWebsiteDataStoreInternal.h"
#import <JavaScriptCore/JSContext.h>
#import <JavaScriptCore/JSValue.h>
#import <wtf/HashMap.h>
#import <wtf/NeverDestroyed.h>
#import <wtf/RetainPtr.h>

#if PLATFORM(IOS)
#import "_WKFrameHandleInternal.h"
#import "_WKWebViewPrintFormatter.h"
#import "PrintInfo.h"
#import "ProcessThrottler.h"
#import "WKPDFView.h"
#import "WKScrollView.h"
#import "WKWebViewContentProviderRegistry.h"
#import "WebPageMessages.h"
#import <CoreGraphics/CGFloat.h>
#import <CoreGraphics/CGPDFDocumentPrivate.h>
#import <UIKit/UIApplication.h>
#import <UIKit/UIPeripheralHost_Private.h>
#import <UIKit/UIWindow_Private.h>
#import <QuartzCore/CARenderServer.h>
#import <QuartzCore/QuartzCorePrivate.h>

@interface UIScrollView (UIScrollViewInternal)
- (void)_adjustForAutomaticKeyboardInfo:(NSDictionary*)info animated:(BOOL)animated lastAdjustment:(CGFloat*)lastAdjustment;
- (BOOL)_isScrollingToTop;
@end

@interface UIPeripheralHost(UIKitInternal)
- (CGFloat)getVerticalOverlapForView:(UIView *)view usingKeyboardInfo:(NSDictionary *)info;
@end

@interface UIView (UIViewInternal)
- (UIViewController *)_viewControllerForAncestor;
@end

@interface UIWindow (UIWindowInternal)
- (BOOL)_isHostedInAnotherProcess;
@end

@interface UIViewController (UIViewControllerInternal)
- (UIViewController *)_rootAncestorViewController;
- (UIViewController *)_viewControllerForSupportedInterfaceOrientations;
@end
#endif

#if PLATFORM(MAC)
#import "WKViewInternal.h"
#import <WebCore/ColorMac.h>
#endif


static HashMap<WebKit::WebPageProxy*, WKWebView *>& pageToViewMap()
{
    static NeverDestroyed<HashMap<WebKit::WebPageProxy*, WKWebView *>> map;
    return map;
}

WKWebView* fromWebPageProxy(WebKit::WebPageProxy& page)
{
    return pageToViewMap().get(&page);
}

@implementation WKWebView {
    std::unique_ptr<WebKit::NavigationState> _navigationState;
    std::unique_ptr<WebKit::UIDelegate> _uiDelegate;

    RetainPtr<_WKRemoteObjectRegistry> _remoteObjectRegistry;
    _WKRenderingProgressEvents _observedRenderingProgressEvents;

    WebKit::WeakObjCPtr<id <_WKFormDelegate>> _formDelegate;
#if PLATFORM(IOS)
    RetainPtr<WKScrollView> _scrollView;
    RetainPtr<WKContentView> _contentView;

    BOOL _overridesMinimumLayoutSize;
    CGSize _minimumLayoutSizeOverride;
    BOOL _overridesMinimumLayoutSizeForMinimalUI;
    CGSize _minimumLayoutSizeOverrideForMinimalUI;
    BOOL _overridesMaximumUnobscuredSize;
    CGSize _maximumUnobscuredSizeOverride;
    BOOL _usesMinimalUI;
    BOOL _needsToNotifyDelegateAboutMinimalUI;
    CGRect _inputViewBounds;
    CGFloat _viewportMetaTagWidth;

    UIEdgeInsets _obscuredInsets;
    bool _isChangingObscuredInsetsInteractively;

    UIInterfaceOrientation _interfaceOrientationOverride;
    BOOL _overridesInterfaceOrientation;

    BOOL _needsResetViewStateAfterCommitLoadForMainFrame;
    BOOL _isAnimatingResize;
    CATransform3D _resizeAnimationTransformAdjustments;
    RetainPtr<UIView> _resizeAnimationView;
    CGFloat _lastAdjustmentForScroller;

    std::unique_ptr<WebKit::ViewGestureController> _gestureController;
    BOOL _allowsBackForwardNavigationGestures;

    RetainPtr<UIView <WKWebViewContentProvider>> _customContentView;
    RetainPtr<UIView> _customContentFixedOverlayView;

    WebCore::Color _scrollViewBackgroundColor;

    BOOL _delayUpdateVisibleContentRects;
    BOOL _hadDelayedUpdateVisibleContentRects;

    BOOL _pageIsPrintingToPDF;
    RetainPtr<CGPDFDocumentRef> _printedDocument;
#endif
#if PLATFORM(MAC)
    RetainPtr<WKView> _wkView;
#endif
}

- (instancetype)initWithFrame:(CGRect)frame
{
    return [self initWithFrame:frame configuration:adoptNS([[WKWebViewConfiguration alloc] init]).get()];
}

#if PLATFORM(IOS)
static int32_t deviceOrientationForUIInterfaceOrientation(UIInterfaceOrientation orientation)
{
    switch (orientation) {
    case UIInterfaceOrientationUnknown:
    case UIInterfaceOrientationPortrait:
        return 0;
    case UIInterfaceOrientationPortraitUpsideDown:
        return 180;
    case UIInterfaceOrientationLandscapeLeft:
        return -90;
    case UIInterfaceOrientationLandscapeRight:
        return 90;
    }
}

static int32_t deviceOrientation()
{
    return deviceOrientationForUIInterfaceOrientation([[UIApplication sharedApplication] statusBarOrientation]);
}
#endif

- (instancetype)initWithFrame:(CGRect)frame configuration:(WKWebViewConfiguration *)configuration
{
    if (!(self = [super initWithFrame:frame]))
        return nil;

    _configuration = adoptNS([configuration copy]);

    if (WKWebView *relatedWebView = [_configuration _relatedWebView]) {
        WKProcessPool *processPool = [_configuration processPool];
        WKProcessPool *relatedWebViewProcessPool = [relatedWebView->_configuration processPool];
        if (processPool && processPool != relatedWebViewProcessPool)
            [NSException raise:NSInvalidArgumentException format:@"Related web view %@ has process pool %@ but configuration specifies a different process pool %@", relatedWebView, relatedWebViewProcessPool, configuration.processPool];

        [_configuration setProcessPool:relatedWebViewProcessPool];
    }

    [_configuration _validate];

    CGRect bounds = self.bounds;

    WebKit::WebContext& context = *[_configuration processPool]->_context;

    WebKit::WebPageConfiguration webPageConfiguration;
    webPageConfiguration.preferences = [_configuration preferences]->_preferences.get();
    if (WKWebView *relatedWebView = [_configuration _relatedWebView])
        webPageConfiguration.relatedPage = relatedWebView->_page.get();

    webPageConfiguration.userContentController = [_configuration userContentController]->_userContentControllerProxy.get();
    webPageConfiguration.visitedLinkProvider = [_configuration _visitedLinkProvider]->_visitedLinkProvider.get();
    webPageConfiguration.session = [_configuration _websiteDataStore]->_session.get();
    
    RefPtr<WebKit::WebPageGroup> pageGroup;
    NSString *groupIdentifier = configuration._groupIdentifier;
    if (groupIdentifier.length) {
        pageGroup = WebKit::WebPageGroup::create(configuration._groupIdentifier);
        webPageConfiguration.pageGroup = pageGroup.get();
    }

    webPageConfiguration.preferenceValues.set(WebKit::WebPreferencesKey::suppressesIncrementalRenderingKey(), WebKit::WebPreferencesStore::Value(!![_configuration suppressesIncrementalRendering]));

#if PLATFORM(IOS)
    webPageConfiguration.preferenceValues.set(WebKit::WebPreferencesKey::mediaPlaybackAllowsAirPlayKey(), WebKit::WebPreferencesStore::Value(!![_configuration allowsInlineMediaPlayback]));
    webPageConfiguration.preferenceValues.set(WebKit::WebPreferencesKey::mediaPlaybackRequiresUserGestureKey(), WebKit::WebPreferencesStore::Value(!![_configuration mediaPlaybackRequiresUserAction]));
    webPageConfiguration.preferenceValues.set(WebKit::WebPreferencesKey::mediaPlaybackAllowsAirPlayKey(), WebKit::WebPreferencesStore::Value(!![_configuration mediaPlaybackAllowsAirPlay]));
#endif

#if PLATFORM(IOS)
    _scrollView = adoptNS([[WKScrollView alloc] initWithFrame:bounds]);
    [_scrollView setInternalDelegate:self];
    [_scrollView setBouncesZoom:YES];

    [self addSubview:_scrollView.get()];
    [_scrollView setBackgroundColor:[UIColor whiteColor]];

    _contentView = adoptNS([[WKContentView alloc] initWithFrame:bounds context:context configuration:std::move(webPageConfiguration) webView:self]);
    _page = [_contentView page];

    _page->setDeviceOrientation(deviceOrientation());

    [_contentView layer].anchorPoint = CGPointZero;
    [_contentView setFrame:bounds];
    [_scrollView addSubview:_contentView.get()];
    _viewportMetaTagWidth = -1;

    [self _frameOrBoundsChanged];

    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(_keyboardWillChangeFrame:) name:UIKeyboardWillChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(_keyboardDidChangeFrame:) name:UIKeyboardDidChangeFrameNotification object:nil];
    [center addObserver:self selector:@selector(_keyboardWillShow:) name:UIKeyboardWillShowNotification object:nil];
    [center addObserver:self selector:@selector(_keyboardWillHide:) name:UIKeyboardWillHideNotification object:nil];
    [center addObserver:self selector:@selector(_windowDidRotate:) name:UIWindowDidRotateNotification object:nil];
    [center addObserver:self selector:@selector(_contentSizeCategoryDidChange:) name:UIContentSizeCategoryDidChangeNotification object:nil];
    _page->contentSizeCategoryDidChange([self _contentSizeCategory]);

    [[_configuration _contentProviderRegistry] addPage:*_page];
#endif

#if PLATFORM(MAC)
    _wkView = [[WKView alloc] initWithFrame:bounds context:context configuration:std::move(webPageConfiguration) webView:self];
    [self addSubview:_wkView.get()];
    _page = WebKit::toImpl([_wkView pageRef]);
#endif

    _page->setBackgroundExtendsBeyondPage(true);

    _navigationState = std::make_unique<WebKit::NavigationState>(self);
    _page->setPolicyClient(_navigationState->createPolicyClient());
    _page->setLoaderClient(_navigationState->createLoaderClient());

    _uiDelegate = std::make_unique<WebKit::UIDelegate>(self);
    _page->setUIClient(_uiDelegate->createUIClient());

    _page->setFindClient(std::make_unique<WebKit::FindClient>(self));

    pageToViewMap().add(_page.get(), self);

    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    [self release];
    return nil;
}

- (void)dealloc
{
    _page->close();

    [_remoteObjectRegistry _invalidate];
#if PLATFORM(IOS)
    [[_configuration _contentProviderRegistry] removePage:*_page];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#endif

    pageToViewMap().remove(_page.get());

    [super dealloc];
}

- (WKWebViewConfiguration *)configuration
{
    return [[_configuration copy] autorelease];
}

- (WKBackForwardList *)backForwardList
{
    return wrapper(_page->backForwardList());
}

- (id <WKNavigationDelegate>)navigationDelegate
{
    return _navigationState->navigationDelegate().autorelease();
}

- (void)setNavigationDelegate:(id <WKNavigationDelegate>)navigationDelegate
{
    _navigationState->setNavigationDelegate(navigationDelegate);
}

- (id <WKUIDelegate>)UIDelegate
{
    return _uiDelegate->delegate().autorelease();
}

- (void)setUIDelegate:(id<WKUIDelegate>)UIDelegate
{
    _uiDelegate->setDelegate(UIDelegate);
}

- (WKNavigation *)loadRequest:(NSURLRequest *)request
{
    uint64_t navigationID = _page->loadRequest(request);
    auto navigation = _navigationState->createLoadRequestNavigation(navigationID, request);

    return navigation.autorelease();
}

- (WKNavigation *)loadHTMLString:(NSString *)string baseURL:(NSURL *)baseURL
{
    uint64_t navigationID = _page->loadHTMLString(string, baseURL.absoluteString);
    auto navigation = _navigationState->createLoadDataNavigation(navigationID);

    return navigation.autorelease();
}

- (WKNavigation *)goToBackForwardListItem:(WKBackForwardListItem *)item
{
    uint64_t navigationID = _page->goToBackForwardItem(&item._item);

    auto navigation = _navigationState->createBackForwardNavigation(navigationID, item._item);

    return navigation.autorelease();
}

- (NSString *)title
{
    return _page->pageLoadState().title();
}

- (NSURL *)URL
{
    return [NSURL _web_URLWithWTFString:_page->pageLoadState().activeURL()];
}

- (BOOL)isLoading
{
    return _page->pageLoadState().isLoading();
}

- (double)estimatedProgress
{
    return _page->pageLoadState().estimatedProgress();
}

- (BOOL)hasOnlySecureContent
{
    return _page->pageLoadState().hasOnlySecureContent();
}

- (BOOL)canGoBack
{
    return _page->pageLoadState().canGoBack();
}

- (BOOL)canGoForward
{
    return _page->pageLoadState().canGoForward();
}

- (WKNavigation *)goBack
{
    uint64_t navigationID = _page->goBack();
    if (!navigationID)
        return nil;

    ASSERT(_page->backForwardList().currentItem());
    auto navigation = _navigationState->createBackForwardNavigation(navigationID, *_page->backForwardList().currentItem());

    return navigation.autorelease();
}

- (WKNavigation *)goForward
{
    uint64_t navigationID = _page->goForward();
    if (!navigationID)
        return nil;

    ASSERT(_page->backForwardList().currentItem());
    auto navigation = _navigationState->createBackForwardNavigation(navigationID, *_page->backForwardList().currentItem());

    return navigation.autorelease();
}

- (WKNavigation *)reload
{
    uint64_t navigationID = _page->reload(false);
    ASSERT(navigationID);

    auto navigation = _navigationState->createReloadNavigation(navigationID);
    return navigation.autorelease();
}

- (WKNavigation *)reloadFromOrigin
{
    uint64_t navigationID = _page->reload(true);
    ASSERT(navigationID);

    auto navigation = _navigationState->createReloadNavigation(navigationID);
    return navigation.autorelease();
}

- (void)stopLoading
{
    _page->stopLoading();
}

static WKErrorCode callbackErrorCode(WebKit::CallbackBase::Error error)
{
    switch (error) {
    case WebKit::CallbackBase::Error::None:
        ASSERT_NOT_REACHED();
        return WKErrorUnknown;

    case WebKit::CallbackBase::Error::Unknown:
        return WKErrorUnknown;

    case WebKit::CallbackBase::Error::ProcessExited:
        return WKErrorWebContentProcessTerminated;

    case WebKit::CallbackBase::Error::OwnerWasInvalidated:
        return WKErrorWebViewInvalidated;
    }
}

- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *))completionHandler
{
    auto handler = adoptNS([completionHandler copy]);

    _page->runJavaScriptInMainFrame(javaScriptString, [handler](WebKit::WebSerializedScriptValue* serializedScriptValue, WebKit::ScriptValueCallback::Error errorCode) {
        if (!handler)
            return;

        auto completionHandler = (void (^)(id, NSError *))handler.get();

        if (errorCode != WebKit::ScriptValueCallback::Error::None) {
            auto error = createNSError(callbackErrorCode(errorCode));
            if (errorCode == WebKit::ScriptValueCallback::Error::OwnerWasInvalidated) {
                // The OwnerWasInvalidated callback is synchronous. We don't want to call the block from within it
                // because that can trigger re-entrancy bugs in WebKit.
                // FIXME: It would be even better if GenericCallback did this for us.
                dispatch_async(dispatch_get_main_queue(), [completionHandler, error] {
                    completionHandler(nil, error.get());
                });
                return;
            }

            completionHandler(nil, error.get());
            return;
        }

        if (!serializedScriptValue) {
            completionHandler(nil, createNSError(WKErrorJavaScriptExceptionOccurred).get());
            return;
        }

        auto context = adoptNS([[JSContext alloc] init]);
        JSValueRef valueRef = serializedScriptValue->deserialize([context JSGlobalContextRef], 0);
        JSValue *value = [JSValue valueWithJSValueRef:valueRef inContext:context.get()];

        completionHandler([value toObject], nil);
    });
}

#pragma mark iOS-specific methods

#if PLATFORM(IOS)
- (void)setFrame:(CGRect)frame
{
    CGRect oldFrame = self.frame;
    [super setFrame:frame];

    if (!CGSizeEqualToSize(oldFrame.size, frame.size))
        [self _frameOrBoundsChanged];
}

- (void)setBounds:(CGRect)bounds
{
    CGRect oldBounds = self.bounds;
    [super setBounds:bounds];
    [_customContentFixedOverlayView setFrame:self.bounds];

    if (!CGSizeEqualToSize(oldBounds.size, bounds.size))
        [self _frameOrBoundsChanged];
}

- (UIScrollView *)scrollView
{
    return _scrollView.get();
}

- (WKBrowsingContextController *)browsingContextController
{
    return [_contentView browsingContextController];
}

static inline CGFloat floorToDevicePixel(CGFloat input, float deviceScaleFactor)
{
    return CGFloor(input * deviceScaleFactor) / deviceScaleFactor;
}

static CGSize roundScrollViewContentSize(const WebKit::WebPageProxy& page, CGSize contentSize)
{
    float deviceScaleFactor = page.deviceScaleFactor();
    return CGSizeMake(floorToDevicePixel(contentSize.width, deviceScaleFactor), floorToDevicePixel(contentSize.height, deviceScaleFactor));
}

- (void)_setHasCustomContentView:(BOOL)pageHasCustomContentView loadedMIMEType:(const WTF::String&)mimeType
{
    if (pageHasCustomContentView) {
        [_customContentView removeFromSuperview];
        [_customContentFixedOverlayView removeFromSuperview];

        Class representationClass = [[_configuration _contentProviderRegistry] providerForMIMEType:mimeType];
        ASSERT(representationClass);
        _customContentView = adoptNS([[representationClass alloc] init]);
        _customContentFixedOverlayView = adoptNS([[UIView alloc] initWithFrame:self.bounds]);
        [_customContentFixedOverlayView setUserInteractionEnabled:NO];

        [_contentView removeFromSuperview];
        [_scrollView addSubview:_customContentView.get()];
        [self addSubview:_customContentFixedOverlayView.get()];

        [_customContentView web_setMinimumSize:self.bounds.size];
        [_customContentView web_setScrollView:_scrollView.get()];
        [_customContentView web_setObscuredInsets:_obscuredInsets];
        [_customContentView web_setFixedOverlayView:_customContentFixedOverlayView.get()];
    } else if (_customContentView) {
        [_customContentView removeFromSuperview];
        _customContentView = nullptr;

        [_customContentFixedOverlayView removeFromSuperview];
        _customContentFixedOverlayView = nullptr;

        [_scrollView addSubview:_contentView.get()];
        [_scrollView setContentSize:roundScrollViewContentSize(*_page, [_contentView frame].size)];

        [_customContentFixedOverlayView setFrame:self.bounds];
        [self addSubview:_customContentFixedOverlayView.get()];
    }
}

- (void)_didFinishLoadingDataForCustomContentProviderWithSuggestedFilename:(const String&)suggestedFilename data:(NSData *)data
{
    ASSERT(_customContentView);
    [_customContentView web_setContentProviderData:data suggestedFilename:suggestedFilename];
}

- (void)_setViewportMetaTagWidth:(float)newWidth
{
    _viewportMetaTagWidth = newWidth;
}

- (void)_willInvokeUIScrollViewDelegateCallback
{
    _delayUpdateVisibleContentRects = YES;
}

- (void)_didInvokeUIScrollViewDelegateCallback
{
    _delayUpdateVisibleContentRects = NO;
    if (_hadDelayedUpdateVisibleContentRects) {
        _hadDelayedUpdateVisibleContentRects = NO;
        [self _updateVisibleContentRects];
    }
}

static CGFloat contentZoomScale(WKWebView* webView)
{
    UIView *zoomView;
    if (webView->_customContentView)
        zoomView = webView->_customContentView.get();
    else
        zoomView = webView->_contentView.get();

    CGFloat scale = [[zoomView layer] affineTransform].a;
    ASSERT(scale == [webView->_scrollView zoomScale]);
    return scale;
}

- (void)_updateScrollViewBackground
{
    WebCore::Color color;
    if (_customContentView)
        color = [_customContentView backgroundColor].CGColor;
    else
        color = _page->pageExtendedBackgroundColor();
    CGFloat zoomScale = contentZoomScale(self);
    CGFloat minimumZoomScale = [_scrollView minimumZoomScale];
    if (zoomScale < minimumZoomScale) {
        CGFloat slope = 12;
        CGFloat opacity = std::max<CGFloat>(1 - slope * (minimumZoomScale - zoomScale), 0);
        color = WebCore::colorWithOverrideAlpha(color.rgb(), opacity);
    }

    if (_scrollViewBackgroundColor == color)
        return;

    _scrollViewBackgroundColor = color;

    RetainPtr<UIColor*> uiBackgroundColor = adoptNS([[UIColor alloc] initWithCGColor:cachedCGColor(color, WebCore::ColorSpaceDeviceRGB)]);
    [_scrollView setBackgroundColor:uiBackgroundColor.get()];
}

- (void)_setUsesMinimalUI:(BOOL)usesMinimalUI
{
    _usesMinimalUI = usesMinimalUI;
    _needsToNotifyDelegateAboutMinimalUI = YES;
}

- (BOOL)_usesMinimalUI
{
    return _usesMinimalUI;
}

- (void)_processDidExit
{
    if (!_customContentView && _isAnimatingResize) {
        NSUInteger indexOfResizeAnimationView = [[_scrollView subviews] indexOfObject:_resizeAnimationView.get()];
        [_scrollView insertSubview:_contentView.get() atIndex:indexOfResizeAnimationView];
        [_resizeAnimationView removeFromSuperview];
        _resizeAnimationView = nil;

        _isAnimatingResize = NO;
        _resizeAnimationTransformAdjustments = CATransform3DIdentity;
    }
    [_contentView setFrame:self.bounds];
    [_scrollView setBackgroundColor:[UIColor whiteColor]];
    [_scrollView setContentOffset:CGPointMake(-_obscuredInsets.left, -_obscuredInsets.top)];
    [_scrollView setZoomScale:1];

    _viewportMetaTagWidth = -1;
    _needsResetViewStateAfterCommitLoadForMainFrame = NO;
    _scrollViewBackgroundColor = WebCore::Color();
    _delayUpdateVisibleContentRects = NO;
    _hadDelayedUpdateVisibleContentRects = NO;
}

- (void)_didCommitLoadForMainFrame
{
    _needsResetViewStateAfterCommitLoadForMainFrame = YES;
    _usesMinimalUI = NO;
}

- (void)_didCommitLayerTree:(const WebKit::RemoteLayerTreeTransaction&)layerTreeTransaction
{
    if (_customContentView)
        return;

    if (_isAnimatingResize) {
        [_resizeAnimationView layer].sublayerTransform = _resizeAnimationTransformAdjustments;
        return;
    }

    [_scrollView setContentSize:roundScrollViewContentSize(*_page, [_contentView frame].size)];
    [_scrollView setMinimumZoomScale:layerTreeTransaction.minimumScaleFactor()];
    [_scrollView setMaximumZoomScale:layerTreeTransaction.maximumScaleFactor()];
    [_scrollView setZoomEnabled:layerTreeTransaction.allowsUserScaling()];
    if (!layerTreeTransaction.scaleWasSetByUIProcess() && ![_scrollView isZooming] && ![_scrollView isZoomBouncing] && ![_scrollView _isAnimatingZoom])
        [_scrollView setZoomScale:layerTreeTransaction.pageScaleFactor()];

    [self _updateScrollViewBackground];

    if (_gestureController)
        _gestureController->setRenderTreeSize(layerTreeTransaction.renderTreeSize());

    if (_needsToNotifyDelegateAboutMinimalUI || _needsResetViewStateAfterCommitLoadForMainFrame) {
        _needsToNotifyDelegateAboutMinimalUI = NO;

        auto delegate = _uiDelegate->delegate();
        if ([delegate respondsToSelector:@selector(_webView:usesMinimalUI:)])
            [static_cast<id <WKUIDelegatePrivate>>(delegate.get()) _webView:self usesMinimalUI:_usesMinimalUI];
    }

    if (_needsResetViewStateAfterCommitLoadForMainFrame) {
        _needsResetViewStateAfterCommitLoadForMainFrame = NO;
        [_scrollView setContentOffset:CGPointMake(-_obscuredInsets.left, -_obscuredInsets.top)];
    }
}

- (void)_dynamicViewportUpdateChangedTargetToScale:(double)newScale position:(CGPoint)newScrollPosition
{
    if (_isAnimatingResize) {
        CGFloat animatingScaleTarget = [[_resizeAnimationView layer] transform].m11;
        double currentTargetScale = animatingScaleTarget * [[_contentView layer] transform].m11;
        double scale = newScale / currentTargetScale;
        _resizeAnimationTransformAdjustments = CATransform3DMakeScale(scale, scale, 0);

        CGPoint newContentOffset = CGPointMake(newScrollPosition.x * newScale, newScrollPosition.y * newScale);
        newContentOffset.x -= _obscuredInsets.left;
        newContentOffset.y -= _obscuredInsets.top;
        CGPoint currentContentOffset = [_scrollView contentOffset];

        _resizeAnimationTransformAdjustments.m41 = (currentContentOffset.x - newContentOffset.x) / animatingScaleTarget;
        _resizeAnimationTransformAdjustments.m42 = (currentContentOffset.y - newContentOffset.y) / animatingScaleTarget;
    }
}

- (WebKit::ViewSnapshot)_takeViewSnapshot
{
    float deviceScale = WKGetScreenScaleFactor();
    CGSize snapshotSize = self.bounds.size;
    snapshotSize.width *= deviceScale;
    snapshotSize.height *= deviceScale;

    WebKit::ViewSnapshot snapshot;
    snapshot.slotID = [WebKit::ViewSnapshotStore::snapshottingContext() createImageSlot:snapshotSize hasAlpha:YES];

    CATransform3D transform = CATransform3DMakeScale(deviceScale, deviceScale, 1);
    CARenderServerCaptureLayerWithTransform(MACH_PORT_NULL, self.layer.context.contextId, (uint64_t)self.layer, snapshot.slotID, 0, 0, &transform);

    snapshot.size = WebCore::expandedIntSize(WebCore::FloatSize(snapshotSize));
    snapshot.imageSizeInBytes = snapshotSize.width * snapshotSize.height * 4;

    return snapshot;
}

- (void)_zoomToPoint:(WebCore::FloatPoint)point atScale:(double)scale
{
    double maximumZoomDuration = 0.4;
    double minimumZoomDuration = 0.1;
    double zoomDurationFactor = 0.3;

    CGFloat zoomScale = contentZoomScale(self);
    CFTimeInterval duration = std::min(fabs(log(zoomScale) - log(scale)) * zoomDurationFactor + minimumZoomDuration, maximumZoomDuration);

    if (scale != zoomScale)
        _page->willStartUserTriggeredZooming();

    [_scrollView _zoomToCenter:point scale:scale duration:duration];
}

- (void)_zoomToRect:(WebCore::FloatRect)targetRect atScale:(double)scale origin:(WebCore::FloatPoint)origin
{
    // FIMXE: Some of this could be shared with _scrollToRect.
    const double visibleRectScaleChange = contentZoomScale(self) / scale;
    const WebCore::FloatRect visibleRect([self convertRect:self.bounds toView:_contentView.get()]);
    const WebCore::FloatRect unobscuredRect([self _contentRectForUserInteraction]);

    const WebCore::FloatSize topLeftObscuredInsetAfterZoom((unobscuredRect.minXMinYCorner() - visibleRect.minXMinYCorner()) * visibleRectScaleChange);
    const WebCore::FloatSize bottomRightObscuredInsetAfterZoom((visibleRect.maxXMaxYCorner() - unobscuredRect.maxXMaxYCorner()) * visibleRectScaleChange);

    const WebCore::FloatSize unobscuredRectSizeAfterZoom(unobscuredRect.size() * visibleRectScaleChange);

    // Center to the target rect.
    WebCore::FloatPoint unobscuredRectLocationAfterZoom = targetRect.location() - (unobscuredRectSizeAfterZoom - targetRect.size()) * 0.5;

    // Center to the tap point instead in case the target rect won't fit in a direction.
    if (targetRect.width() > unobscuredRectSizeAfterZoom.width())
        unobscuredRectLocationAfterZoom.setX(origin.x() - unobscuredRectSizeAfterZoom.width() / 2);
    if (targetRect.height() > unobscuredRectSizeAfterZoom.height())
        unobscuredRectLocationAfterZoom.setY(origin.y() - unobscuredRectSizeAfterZoom.height() / 2);

    // We have computed where we want the unobscured rect to be. Now adjust for the obscuring insets.
    WebCore::FloatRect visibleRectAfterZoom(unobscuredRectLocationAfterZoom, unobscuredRectSizeAfterZoom);
    visibleRectAfterZoom.move(-topLeftObscuredInsetAfterZoom);
    visibleRectAfterZoom.expand(topLeftObscuredInsetAfterZoom + bottomRightObscuredInsetAfterZoom);

    [self _zoomToPoint:visibleRectAfterZoom.center() atScale:scale];
}

static WebCore::FloatPoint constrainContentOffset(WebCore::FloatPoint contentOffset, WebCore::FloatSize contentSize, WebCore::FloatSize unobscuredContentSize)
{
    WebCore::FloatSize maximumContentOffset = contentSize - unobscuredContentSize;
    contentOffset = contentOffset.shrunkTo(WebCore::FloatPoint(maximumContentOffset.width(), maximumContentOffset.height()));
    contentOffset = contentOffset.expandedTo(WebCore::FloatPoint());
    return contentOffset;
}

- (void)_scrollToContentOffset:(WebCore::FloatPoint)contentOffset
{
    if (_isAnimatingResize)
        return;

    [_scrollView _stopScrollingAndZoomingAnimations];

    WebCore::FloatPoint scaledOffset = contentOffset;
    CGFloat zoomScale = contentZoomScale(self);
    scaledOffset.scale(zoomScale, zoomScale);

    scaledOffset -= WebCore::FloatSize(_obscuredInsets.left, _obscuredInsets.top);
    [_scrollView setContentOffset:scaledOffset];
}

- (BOOL)_scrollToRect:(WebCore::FloatRect)targetRect origin:(WebCore::FloatPoint)origin minimumScrollDistance:(float)minimumScrollDistance
{
    WebCore::FloatRect unobscuredContentRect([self _contentRectForUserInteraction]);
    WebCore::FloatPoint unobscuredContentOffset = unobscuredContentRect.location();
    WebCore::FloatSize contentSize([_contentView bounds].size);

    // Center the target rect in the scroll view.
    // If the target doesn't fit in the scroll view, center on the gesture location instead.
    WebCore::FloatPoint newUnobscuredContentOffset;
    if (targetRect.width() <= unobscuredContentRect.width())
        newUnobscuredContentOffset.setX(targetRect.x() - (unobscuredContentRect.width() - targetRect.width()) / 2);
    else
        newUnobscuredContentOffset.setX(origin.x() - unobscuredContentRect.width() / 2);
    if (targetRect.height() <= unobscuredContentRect.height())
        newUnobscuredContentOffset.setY(targetRect.y() - (unobscuredContentRect.height() - targetRect.height()) / 2);
    else
        newUnobscuredContentOffset.setY(origin.y() - unobscuredContentRect.height() / 2);
    newUnobscuredContentOffset = constrainContentOffset(newUnobscuredContentOffset, contentSize, unobscuredContentRect.size());

    if (unobscuredContentOffset == newUnobscuredContentOffset) {
        if (targetRect.width() > unobscuredContentRect.width())
            newUnobscuredContentOffset.setX(origin.x() - unobscuredContentRect.width() / 2);
        if (targetRect.height() > unobscuredContentRect.height())
            newUnobscuredContentOffset.setY(origin.y() - unobscuredContentRect.height() / 2);
        newUnobscuredContentOffset = constrainContentOffset(newUnobscuredContentOffset, contentSize, unobscuredContentRect.size());
    }

    WebCore::FloatSize scrollViewOffsetDelta = newUnobscuredContentOffset - unobscuredContentOffset;
    scrollViewOffsetDelta.scale(contentZoomScale(self));

    float scrollDistance = scrollViewOffsetDelta.diagonalLength();
    if (scrollDistance < minimumScrollDistance)
        return false;

    [_scrollView setContentOffset:([_scrollView contentOffset] + scrollViewOffsetDelta) animated:YES];
    return true;
}

- (void)_zoomOutWithOrigin:(WebCore::FloatPoint)origin
{
    [self _zoomToPoint:origin atScale:[_scrollView minimumZoomScale]];
}

// focusedElementRect and selectionRect are both in document coordinates.
- (void)_zoomToFocusRect:(WebCore::FloatRect)focusedElementRectInDocumentCoordinates selectionRect:(WebCore::FloatRect)selectionRectInDocumentCoordinates fontSize:(float)fontSize minimumScale:(double)minimumScale maximumScale:(double)maximumScale allowScaling:(BOOL)allowScaling forceScroll:(BOOL)forceScroll
{
    const double WKWebViewStandardFontSize = 16;
    const double kMinimumHeightToShowContentAboveKeyboard = 106;
    const CFTimeInterval UIWebFormAnimationDuration = 0.25;
    const double CaretOffsetFromWindowEdge = 20;

    // Zoom around the element's bounding frame. We use a "standard" size to determine the proper frame.
    double scale = allowScaling ? std::min(std::max(WKWebViewStandardFontSize / fontSize, minimumScale), maximumScale) : contentZoomScale(self);
    CGFloat documentWidth = [_contentView bounds].size.width;
    scale = CGRound(documentWidth * scale) / documentWidth;

    UIWindow *window = [_scrollView window];

    WebCore::FloatRect focusedElementRectInNewScale = focusedElementRectInDocumentCoordinates;
    focusedElementRectInNewScale.scale(scale);
    focusedElementRectInNewScale.moveBy([_contentView frame].origin);

    // Find the portion of the view that is visible on the screen.
    UIViewController *topViewController = [[[_scrollView _viewControllerForAncestor] _rootAncestorViewController] _viewControllerForSupportedInterfaceOrientations];
    UIView *fullScreenView = topViewController.view;
    if (!fullScreenView)
        fullScreenView = window;

    CGRect unobscuredScrollViewRectInWebViewCoordinates = UIEdgeInsetsInsetRect([self bounds], _obscuredInsets);
    CGRect visibleScrollViewBoundsInWebViewCoordinates = CGRectIntersection(unobscuredScrollViewRectInWebViewCoordinates, [fullScreenView convertRect:[fullScreenView bounds] toView:self]);
    CGRect formAssistantFrameInWebViewCoordinates = [window convertRect:_inputViewBounds toView:self];
    CGRect intersectionBetweenScrollViewAndFormAssistant = CGRectIntersection(visibleScrollViewBoundsInWebViewCoordinates, formAssistantFrameInWebViewCoordinates);
    CGSize visibleSize = visibleScrollViewBoundsInWebViewCoordinates.size;

    CGFloat visibleOffsetFromTop = 0;
    if (!CGRectIsEmpty(intersectionBetweenScrollViewAndFormAssistant)) {
        CGFloat heightVisibleAboveFormAssistant = CGRectGetMinY(intersectionBetweenScrollViewAndFormAssistant) - CGRectGetMinY(visibleScrollViewBoundsInWebViewCoordinates);
        CGFloat heightVisibleBelowFormAssistant = CGRectGetMaxY(visibleScrollViewBoundsInWebViewCoordinates) - CGRectGetMaxY(intersectionBetweenScrollViewAndFormAssistant);

        if (heightVisibleAboveFormAssistant >= kMinimumHeightToShowContentAboveKeyboard || heightVisibleBelowFormAssistant < heightVisibleAboveFormAssistant)
            visibleSize.height = heightVisibleAboveFormAssistant;
        else {
            visibleSize.height = heightVisibleBelowFormAssistant;
            visibleOffsetFromTop = CGRectGetMaxY(intersectionBetweenScrollViewAndFormAssistant) - CGRectGetMinY(visibleScrollViewBoundsInWebViewCoordinates);
        }
    }

    BOOL selectionRectIsNotNull = !selectionRectInDocumentCoordinates.isZero();
    if (!forceScroll) {
        CGRect currentlyVisibleRegionInWebViewCoordinates;
        currentlyVisibleRegionInWebViewCoordinates.origin = unobscuredScrollViewRectInWebViewCoordinates.origin;
        currentlyVisibleRegionInWebViewCoordinates.origin.y += visibleOffsetFromTop;
        currentlyVisibleRegionInWebViewCoordinates.size = visibleSize;

        // Don't bother scrolling if the entire node is already visible, whether or not we got a selectionRect.
        if (CGRectContainsRect(currentlyVisibleRegionInWebViewCoordinates, [self convertRect:focusedElementRectInDocumentCoordinates fromView:_contentView.get()]))
            return;

        // Don't bother scrolling if we have a valid selectionRect and it is already visible.
        if (selectionRectIsNotNull && CGRectContainsRect(currentlyVisibleRegionInWebViewCoordinates, [self convertRect:selectionRectInDocumentCoordinates fromView:_contentView.get()]))
            return;
    }

    // We want to zoom to the left/top corner of the DOM node, with as much spacing on all sides as we
    // can get based on the visible area after zooming (workingFrame).  The spacing in either dimension is half the
    // difference between the size of the DOM node and the size of the visible frame.
    CGFloat horizontalSpaceInWebViewCoordinates = std::max((visibleSize.width - focusedElementRectInNewScale.width()) / 2.0, 0.0);
    CGFloat verticalSpaceInWebViewCoordinates = std::max((visibleSize.height - focusedElementRectInNewScale.height()) / 2.0, 0.0);

    CGPoint topLeft;
    topLeft.x = focusedElementRectInNewScale.x() - horizontalSpaceInWebViewCoordinates;
    topLeft.y = focusedElementRectInNewScale.y() - verticalSpaceInWebViewCoordinates - visibleOffsetFromTop;

    CGFloat minimumAllowableHorizontalOffsetInWebViewCoordinates = -INFINITY;
    CGFloat minimumAllowableVerticalOffsetInWebViewCoordinates = -INFINITY;
    if (selectionRectIsNotNull) {
        WebCore::FloatRect selectionRectInNewScale = selectionRectInDocumentCoordinates;
        selectionRectInNewScale.scale(scale);
        selectionRectInNewScale.moveBy([_contentView frame].origin);
        minimumAllowableHorizontalOffsetInWebViewCoordinates = CGRectGetMaxX(selectionRectInNewScale) + CaretOffsetFromWindowEdge - visibleSize.width;
        minimumAllowableVerticalOffsetInWebViewCoordinates = CGRectGetMaxY(selectionRectInNewScale) + CaretOffsetFromWindowEdge - visibleSize.height - visibleOffsetFromTop;
    }

    WebCore::FloatRect documentBoundsInNewScale = [_contentView bounds];
    documentBoundsInNewScale.scale(scale);
    documentBoundsInNewScale.moveBy([_contentView frame].origin);

    // Constrain the left edge in document coordinates so that:
    //  - it isn't so small that the scrollVisibleRect isn't visible on the screen
    //  - it isn't so great that the document's right edge is less than the right edge of the screen
    if (selectionRectIsNotNull && topLeft.x < minimumAllowableHorizontalOffsetInWebViewCoordinates)
        topLeft.x = minimumAllowableHorizontalOffsetInWebViewCoordinates;
    else {
        CGFloat maximumAllowableHorizontalOffset = CGRectGetMaxX(documentBoundsInNewScale) - visibleSize.width;
        if (topLeft.x > maximumAllowableHorizontalOffset)
            topLeft.x = maximumAllowableHorizontalOffset;
    }

    // Constrain the top edge in document coordinates so that:
    //  - it isn't so small that the scrollVisibleRect isn't visible on the screen
    //  - it isn't so great that the document's bottom edge is higher than the top of the form assistant
    if (selectionRectIsNotNull && topLeft.y < minimumAllowableVerticalOffsetInWebViewCoordinates)
        topLeft.y = minimumAllowableVerticalOffsetInWebViewCoordinates;
    else {
        CGFloat maximumAllowableVerticalOffset = CGRectGetMaxY(documentBoundsInNewScale) - visibleSize.height;
        if (topLeft.y > maximumAllowableVerticalOffset)
            topLeft.y = maximumAllowableVerticalOffset;
    }

    WebCore::FloatPoint newCenter = CGPointMake(topLeft.x + unobscuredScrollViewRectInWebViewCoordinates.size.width / 2.0, topLeft.y + unobscuredScrollViewRectInWebViewCoordinates.size.height / 2.0);

    if (scale != contentZoomScale(self))
        _page->willStartUserTriggeredZooming();

    // The newCenter has been computed in the new scale, but _zoomToCenter expected the center to be in the original scale.
    newCenter.scale(1 / scale, 1 / scale);
    [_scrollView _zoomToCenter:newCenter
                        scale:scale
                     duration:UIWebFormAnimationDuration
                        force:YES];
}

- (BOOL)_zoomToRect:(WebCore::FloatRect)targetRect withOrigin:(WebCore::FloatPoint)origin fitEntireRect:(BOOL)fitEntireRect minimumScale:(double)minimumScale maximumScale:(double)maximumScale minimumScrollDistance:(float)minimumScrollDistance
{
    const float maximumScaleFactorDeltaForPanScroll = 0.02;

    double currentScale = contentZoomScale(self);

    WebCore::FloatSize unobscuredContentSize([self _contentRectForUserInteraction].size);
    double horizontalScale = unobscuredContentSize.width() * currentScale / targetRect.width();
    double verticalScale = unobscuredContentSize.height() * currentScale / targetRect.height();

    horizontalScale = std::min(std::max(horizontalScale, minimumScale), maximumScale);
    verticalScale = std::min(std::max(verticalScale, minimumScale), maximumScale);

    double targetScale = fitEntireRect ? std::min(horizontalScale, verticalScale) : horizontalScale;
    if (fabs(targetScale - currentScale) < maximumScaleFactorDeltaForPanScroll) {
        if ([self _scrollToRect:targetRect origin:origin minimumScrollDistance:minimumScrollDistance])
            return true;
    } else if (targetScale != currentScale) {
        [self _zoomToRect:targetRect atScale:targetScale origin:origin];
        return true;
    }
    
    return false;
}

- (void)didMoveToWindow
{
    _page->viewStateDidChange(WebCore::ViewState::IsInWindow);
}

#pragma mark - UIScrollViewDelegate

- (BOOL)usesStandardContentView
{
    return !_customContentView;
}

- (CGSize)scrollView:(UIScrollView*)scrollView contentSizeForZoomScale:(CGFloat)scale withProposedSize:(CGSize)proposedSize
{
    return roundScrollViewContentSize(*_page, proposedSize);
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView
{
    ASSERT(_scrollView == scrollView);

    if (_customContentView)
        return _customContentView.get();

    return _contentView.get();
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view
{
    if (![self usesStandardContentView])
        return;

    if (scrollView.pinchGestureRecognizer.state == UIGestureRecognizerStateBegan) {
        _page->willStartUserTriggeredZooming();
        [_contentView scrollViewWillStartPanOrPinchGesture];
    }
    [_contentView willStartZoomOrScroll];
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    if (![self usesStandardContentView])
        return;

    if (scrollView.panGestureRecognizer.state == UIGestureRecognizerStateBegan)
        [_contentView scrollViewWillStartPanOrPinchGesture];
    [_contentView willStartZoomOrScroll];
}

- (void)_didFinishScrolling
{
    if (![self usesStandardContentView])
        return;

    [self _updateVisibleContentRects];
    [_contentView didFinishScrolling];
}

- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset
{
    // Work around <rdar://problem/16374753> by avoiding deceleration while
    // zooming. We'll animate to the right place once the zoom finishes.
    if ([scrollView isZooming])
        *targetContentOffset = [scrollView contentOffset];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    // If we're decelerating, scroll offset will be updated when scrollViewDidFinishDecelerating: is called.
    if (!decelerate)
        [self _didFinishScrolling];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    [self _didFinishScrolling];
}

- (void)scrollViewDidScrollToTop:(UIScrollView *)scrollView
{
    [self _didFinishScrolling];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (![self usesStandardContentView])
        [_customContentView scrollViewDidScroll:(UIScrollView *)scrollView];

    [self _updateVisibleContentRects];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView
{
    [self _updateScrollViewBackground];
    [self _updateVisibleContentRects];
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(UIView *)view atScale:(CGFloat)scale
{
    ASSERT(scrollView == _scrollView);
    [self _updateVisibleContentRects];
    [_contentView didZoomToScale:scale];
}

- (void)_frameOrBoundsChanged
{
    CGRect bounds = self.bounds;
    if (!_isAnimatingResize) {
        if (!_overridesMinimumLayoutSize)
            _page->setViewportConfigurationMinimumLayoutSize(WebCore::FloatSize(bounds.size));
        if (!_overridesMinimumLayoutSizeForMinimalUI)
            _page->setViewportConfigurationMinimumLayoutSizeForMinimalUI(WebCore::FloatSize(bounds.size));
        if (!_overridesMaximumUnobscuredSize)
            _page->setMaximumUnobscuredSize(WebCore::FloatSize(bounds.size));
    }

    [_scrollView setFrame:bounds];
    [_contentView setMinimumSize:bounds.size];
    [_customContentView web_setMinimumSize:bounds.size];
    [self _updateVisibleContentRects];
}

// Unobscured content rect where the user can interact. When the keyboard is up, this should be the area above or bellow the keyboard, wherever there is enough space.
- (CGRect)_contentRectForUserInteraction
{
    // FIXME: handle split keyboard.
    UIEdgeInsets obscuredInsets = _obscuredInsets;
    obscuredInsets.bottom = std::max(_obscuredInsets.bottom, _inputViewBounds.size.height);
    CGRect unobscuredRect = UIEdgeInsetsInsetRect(self.bounds, obscuredInsets);
    return [self convertRect:unobscuredRect toView:_contentView.get()];
}

- (void)_updateVisibleContentRects
{
    if (![self usesStandardContentView])
        return;

    if (_delayUpdateVisibleContentRects) {
        _hadDelayedUpdateVisibleContentRects = YES;
        return;
    }

    if (_isAnimatingResize)
        return;

    CGRect fullViewRect = self.bounds;
    CGRect visibleRectInContentCoordinates = [self convertRect:fullViewRect toView:_contentView.get()];

    CGRect unobscuredRect = UIEdgeInsetsInsetRect(fullViewRect, _obscuredInsets);
    CGRect unobscuredRectInContentCoordinates = [self convertRect:unobscuredRect toView:_contentView.get()];

    CGFloat scaleFactor = contentZoomScale(self);

    BOOL isStableState = !(_isChangingObscuredInsetsInteractively || [_scrollView isDragging] || [_scrollView isDecelerating] || [_scrollView isZooming] || [_scrollView isZoomBouncing] || [_scrollView _isAnimatingZoom] || [_scrollView _isScrollingToTop]);
    [_contentView didUpdateVisibleRect:visibleRectInContentCoordinates
        unobscuredRect:unobscuredRectInContentCoordinates
        unobscuredRectInScrollViewCoordinates:unobscuredRect
        scale:scaleFactor minimumScale:[_scrollView minimumZoomScale]
        inStableState:isStableState isChangingObscuredInsetsInteractively:_isChangingObscuredInsetsInteractively];
}

- (void)_keyboardChangedWithInfo:(NSDictionary *)keyboardInfo adjustScrollView:(BOOL)adjustScrollView
{
    NSValue *endFrameValue = [keyboardInfo objectForKey:UIKeyboardFrameEndUserInfoKey];
    if (!endFrameValue)
        return;

    // The keyboard rect is always in screen coordinates. In the view services case the window does not
    // have the interface orientation rotation transformation; its host does. So, it makes no sense to
    // clip the keyboard rect against its screen.
    if ([[self window] _isHostedInAnotherProcess])
        _inputViewBounds = [self.window convertRect:[endFrameValue CGRectValue] fromWindow:nil];
    else
        _inputViewBounds = [self.window convertRect:CGRectIntersection([endFrameValue CGRectValue], self.window.screen.bounds) fromWindow:nil];

    [self _updateVisibleContentRects];

    if (adjustScrollView)
        [_scrollView _adjustForAutomaticKeyboardInfo:keyboardInfo animated:YES lastAdjustment:&_lastAdjustmentForScroller];
}

- (void)_keyboardWillChangeFrame:(NSNotification *)notification
{
    if ([_contentView isAssistingNode])
        [self _keyboardChangedWithInfo:notification.userInfo adjustScrollView:YES];
}

- (void)_keyboardDidChangeFrame:(NSNotification *)notification
{
    [self _keyboardChangedWithInfo:notification.userInfo adjustScrollView:NO];
}

- (void)_keyboardWillShow:(NSNotification *)notification
{
    if ([_contentView isAssistingNode])
        [self _keyboardChangedWithInfo:notification.userInfo adjustScrollView:YES];
}

- (void)_keyboardWillHide:(NSNotification *)notification
{
    // Ignore keyboard will hide notifications sent during rotation. They're just there for
    // backwards compatibility reasons and processing the will hide notification would
    // temporarily screw up the the unobscured view area.
    if ([[UIPeripheralHost sharedInstance] rotationState])
        return;

    [self _keyboardChangedWithInfo:notification.userInfo adjustScrollView:YES];
}

- (void)_windowDidRotate:(NSNotification *)notification
{
    if (!_overridesInterfaceOrientation)
        _page->setDeviceOrientation(deviceOrientation());
}

- (void)_contentSizeCategoryDidChange:(NSNotification *)notification
{
    _page->contentSizeCategoryDidChange([self _contentSizeCategory]);
}

- (NSString *)_contentSizeCategory
{
    return [[UIApplication sharedApplication] preferredContentSizeCategory];
}

- (void)setAllowsBackForwardNavigationGestures:(BOOL)allowsBackForwardNavigationGestures
{
    if (_allowsBackForwardNavigationGestures == allowsBackForwardNavigationGestures)
        return;

    _allowsBackForwardNavigationGestures = allowsBackForwardNavigationGestures;

    if (allowsBackForwardNavigationGestures) {
        if (!_gestureController) {
            _gestureController = std::make_unique<WebKit::ViewGestureController>(*_page);
            _gestureController->installSwipeHandler(self, [self scrollView]);
        }
    } else
        _gestureController = nullptr;

    _page->setShouldRecordNavigationSnapshots(allowsBackForwardNavigationGestures);
}

- (BOOL)allowsBackForwardNavigationGestures
{
    return _allowsBackForwardNavigationGestures;
}

#endif

#pragma mark OS X-specific methods

#if PLATFORM(MAC)

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
    [_wkView setFrame:self.bounds];
}

- (void)setAllowsBackForwardNavigationGestures:(BOOL)allowsBackForwardNavigationGestures
{
    [_wkView setAllowsBackForwardNavigationGestures:allowsBackForwardNavigationGestures];
}

- (BOOL)allowsBackForwardNavigationGestures
{
    return [_wkView allowsBackForwardNavigationGestures];
}

- (void)setAllowsMagnification:(BOOL)allowsMagnification
{
    [_wkView setAllowsMagnification:allowsMagnification];
}

- (BOOL)allowsMagnification
{
    return [_wkView allowsMagnification];
}

- (void)setMagnification:(CGFloat)magnification
{
    [_wkView setMagnification:magnification];
}

- (CGFloat)magnification
{
    return [_wkView magnification];
}

- (void)setMagnification:(CGFloat)magnification centeredAtPoint:(CGPoint)point
{
    [_wkView setMagnification:magnification centeredAtPoint:NSPointFromCGPoint(point)];
}

#endif

@end

@implementation WKWebView (WKPrivate)

- (_WKRemoteObjectRegistry *)_remoteObjectRegistry
{
    if (!_remoteObjectRegistry) {
        _remoteObjectRegistry = adoptNS([[_WKRemoteObjectRegistry alloc] _initWithMessageSender:*_page]);
        _page->process().context().addMessageReceiver(Messages::RemoteObjectRegistry::messageReceiverName(), _page->pageID(), [_remoteObjectRegistry remoteObjectRegistry]);
    }

    return _remoteObjectRegistry.get();
}

- (WKBrowsingContextHandle *)_handle
{
    return [[[WKBrowsingContextHandle alloc] _initWithPageID:_page->pageID()] autorelease];
}

- (_WKRenderingProgressEvents)_observedRenderingProgressEvents
{
    return _observedRenderingProgressEvents;
}

- (id <WKHistoryDelegatePrivate>)_historyDelegate
{
    return _navigationState->historyDelegate().autorelease();
}

- (void)_setHistoryDelegate:(id <WKHistoryDelegatePrivate>)historyDelegate
{
    _navigationState->setHistoryDelegate(historyDelegate);
}

- (NSURL *)_unreachableURL
{
    return [NSURL _web_URLWithWTFString:_page->pageLoadState().unreachableURL()];
}

- (void)_loadAlternateHTMLString:(NSString *)string baseURL:(NSURL *)baseURL forUnreachableURL:(NSURL *)unreachableURL
{
    _page->loadAlternateHTMLString(string, [baseURL _web_originalDataAsWTFString], [unreachableURL _web_originalDataAsWTFString]);
}

- (WKNavigation *)_reload
{
    return [self reload];
}

- (NSArray *)_certificateChain
{
    if (WebKit::WebFrameProxy* mainFrame = _page->mainFrame())
        return mainFrame->certificateInfo() ? (NSArray *)mainFrame->certificateInfo()->certificateInfo().certificateChain() : nil;

    return nil;
}

- (NSURL *)_committedURL
{
    return [NSURL _web_URLWithWTFString:_page->pageLoadState().url()];
}

- (NSString *)_applicationNameForUserAgent
{
    return _page->applicationNameForUserAgent();
}

- (void)_setApplicationNameForUserAgent:(NSString *)applicationNameForUserAgent
{
    _page->setApplicationNameForUserAgent(applicationNameForUserAgent);
}

- (NSString *)_customUserAgent
{
    return _page->customUserAgent();
}

- (void)_setCustomUserAgent:(NSString *)_customUserAgent
{
    _page->setCustomUserAgent(_customUserAgent);
}

- (pid_t)_webProcessIdentifier
{
    return _page->isValid() ? _page->processIdentifier() : 0;
}

- (void)_killWebContentProcess
{
    if (!_page->isValid())
        return;

    _page->process().terminate();
}

- (void)_didRelaunchProcess
{
#if PLATFORM(IOS)
    WebCore::FloatSize boundsSize(self.bounds.size);
    _page->setViewportConfigurationMinimumLayoutSize(_overridesMinimumLayoutSize ? WebCore::FloatSize(_minimumLayoutSizeOverride) : boundsSize);
    _page->setViewportConfigurationMinimumLayoutSizeForMinimalUI(_overridesMinimumLayoutSizeForMinimalUI ? WebCore::FloatSize(_minimumLayoutSizeOverrideForMinimalUI) : boundsSize);
    _page->setMaximumUnobscuredSize(_overridesMaximumUnobscuredSize ? WebCore::FloatSize(_maximumUnobscuredSizeOverride) : boundsSize);
#endif
}

- (NSData *)_sessionState
{
    return [wrapper(*_page->sessionStateData(nullptr, nullptr).leakRef()) autorelease];
}

static void releaseNSData(unsigned char*, const void* data)
{
    [(NSData *)data release];
}

- (void)_restoreFromSessionState:(NSData *)sessionState
{
    [sessionState retain];
    _page->restoreFromSessionStateData(API::Data::createWithoutCopying((const unsigned char*)sessionState.bytes, sessionState.length, releaseNSData, sessionState).get());
}

- (void)_close
{
    _page->close();
}

- (BOOL)_privateBrowsingEnabled
{
    return [_configuration preferences]->_preferences->privateBrowsingEnabled();
}

- (void)_setPrivateBrowsingEnabled:(BOOL)privateBrowsingEnabled
{
    [_configuration preferences]->_preferences->setPrivateBrowsingEnabled(privateBrowsingEnabled);
}

- (BOOL)_allowsRemoteInspection
{
#if ENABLE(REMOTE_INSPECTOR)
    return _page->allowsRemoteInspection();
#else
    return NO;
#endif
}

- (void)_setAllowsRemoteInspection:(BOOL)allow
{
#if ENABLE(REMOTE_INSPECTOR)
    _page->setAllowsRemoteInspection(allow);
#endif
}

- (BOOL)_addsVisitedLinks
{
    return _page->addsVisitedLinks();
}

- (void)_setAddsVisitedLinks:(BOOL)addsVisitedLinks
{
    _page->setAddsVisitedLinks(addsVisitedLinks);
}

static inline WebCore::LayoutMilestones layoutMilestones(_WKRenderingProgressEvents events)
{
    WebCore::LayoutMilestones milestones = 0;

    if (events & _WKRenderingProgressEventFirstLayout)
        milestones |= WebCore::DidFirstLayout;

    if (events & _WKRenderingProgressEventFirstPaintWithSignificantArea)
        milestones |= WebCore::DidHitRelevantRepaintedObjectsAreaThreshold;

    return milestones;
}

- (void)_setObservedRenderingProgressEvents:(_WKRenderingProgressEvents)observedRenderingProgressEvents
{
    _observedRenderingProgressEvents = observedRenderingProgressEvents;
    _page->listenForLayoutMilestones(layoutMilestones(observedRenderingProgressEvents));
}

- (void)_runJavaScriptInMainFrame:(NSString *)scriptString
{
    [self evaluateJavaScript:scriptString completionHandler:^(id, NSError *) { }];
}

- (void)_getWebArchiveDataWithCompletionHandler:(void (^)(NSData *, NSError *))completionHandler
{
    auto handler = adoptNS([completionHandler copy]);

    _page->getWebArchiveOfFrame(_page->mainFrame(), [handler](API::Data* data, WebKit::CallbackBase::Error error) {
        void (^completionHandlerBlock)(NSData *, NSError *) = (void (^)(NSData *, NSError *))handler.get();
        if (error != WebKit::CallbackBase::Error::None) {
            // FIXME: Pipe a proper error in from the WebPageProxy.
            RetainPtr<NSError> error = adoptNS([[NSError alloc] init]);
            completionHandlerBlock(nil, error.get());
        } else
            completionHandlerBlock(wrapper(*data), nil);
    });
}

- (_WKPaginationMode)_paginationMode
{
    switch (_page->paginationMode()) {
    case WebCore::Pagination::Unpaginated:
        return _WKPaginationModeUnpaginated;
    case WebCore::Pagination::LeftToRightPaginated:
        return _WKPaginationModeLeftToRight;
    case WebCore::Pagination::RightToLeftPaginated:
        return _WKPaginationModeRightToLeft;
    case WebCore::Pagination::TopToBottomPaginated:
        return _WKPaginationModeTopToBottom;
    case WebCore::Pagination::BottomToTopPaginated:
        return _WKPaginationModeBottomToTop;
    }

    ASSERT_NOT_REACHED();
    return _WKPaginationModeUnpaginated;
}

- (void)_setPaginationMode:(_WKPaginationMode)paginationMode
{
    WebCore::Pagination::Mode mode;
    switch (paginationMode) {
    case _WKPaginationModeUnpaginated:
        mode = WebCore::Pagination::Unpaginated;
        break;
    case _WKPaginationModeLeftToRight:
        mode = WebCore::Pagination::LeftToRightPaginated;
        break;
    case _WKPaginationModeRightToLeft:
        mode = WebCore::Pagination::RightToLeftPaginated;
        break;
    case _WKPaginationModeTopToBottom:
        mode = WebCore::Pagination::TopToBottomPaginated;
        break;
    case _WKPaginationModeBottomToTop:
        mode = WebCore::Pagination::BottomToTopPaginated;
        break;
    default:
        return;
    }

    _page->setPaginationMode(mode);
}

- (BOOL)_paginationBehavesLikeColumns
{
    return _page->paginationBehavesLikeColumns();
}

- (void)_setPaginationBehavesLikeColumns:(BOOL)behavesLikeColumns
{
    _page->setPaginationBehavesLikeColumns(behavesLikeColumns);
}

- (CGFloat)_pageLength
{
    return _page->pageLength();
}

- (void)_setPageLength:(CGFloat)pageLength
{
    _page->setPageLength(pageLength);
}

- (CGFloat)_gapBetweenPages
{
    return _page->gapBetweenPages();
}

- (void)_setGapBetweenPages:(CGFloat)gapBetweenPages
{
    _page->setGapBetweenPages(gapBetweenPages);
}

- (NSUInteger)_pageCount
{
    return _page->pageCount();
}

- (BOOL)_supportsTextZoom
{
    return _page->supportsTextZoom();
}

- (double)_textZoomFactor
{
    return _page->textZoomFactor();
}

- (void)_setTextZoomFactor:(double)zoomFactor
{
    _page->setTextZoomFactor(zoomFactor);
}

- (double)_pageZoomFactor
{
    return _page->pageZoomFactor();
}

- (void)_setPageZoomFactor:(double)zoomFactor
{
    _page->setPageZoomFactor(zoomFactor);
}

- (id <_WKFindDelegate>)_findDelegate
{
    return [static_cast<WebKit::FindClient&>(_page->findClient()).delegate().leakRef() autorelease];
}

- (void)_setFindDelegate:(id<_WKFindDelegate>)findDelegate
{
    static_cast<WebKit::FindClient&>(_page->findClient()).setDelegate(findDelegate);
}

static inline WebKit::FindOptions toFindOptions(_WKFindOptions wkFindOptions)
{
    unsigned findOptions = 0;

    if (wkFindOptions & _WKFindOptionsCaseInsensitive)
        findOptions |= WebKit::FindOptionsCaseInsensitive;
    if (wkFindOptions & _WKFindOptionsAtWordStarts)
        findOptions |= WebKit::FindOptionsAtWordStarts;
    if (wkFindOptions & _WKFindOptionsTreatMedialCapitalAsWordStart)
        findOptions |= WebKit::FindOptionsTreatMedialCapitalAsWordStart;
    if (wkFindOptions & _WKFindOptionsBackwards)
        findOptions |= WebKit::FindOptionsBackwards;
    if (wkFindOptions & _WKFindOptionsWrapAround)
        findOptions |= WebKit::FindOptionsWrapAround;
    if (wkFindOptions & _WKFindOptionsShowOverlay)
        findOptions |= WebKit::FindOptionsShowOverlay;
    if (wkFindOptions & _WKFindOptionsShowFindIndicator)
        findOptions |= WebKit::FindOptionsShowFindIndicator;
    if (wkFindOptions & _WKFindOptionsShowHighlight)
        findOptions |= WebKit::FindOptionsShowHighlight;
    if (wkFindOptions & _WKFindOptionsDetermineMatchIndex)
        findOptions |= WebKit::FindOptionsDetermineMatchIndex;

    return static_cast<WebKit::FindOptions>(findOptions);
}

- (void)_countStringMatches:(NSString *)string options:(_WKFindOptions)options maxCount:(NSUInteger)maxCount
{
    _page->countStringMatches(string, toFindOptions(options), maxCount);
}

- (void)_findString:(NSString *)string options:(_WKFindOptions)options maxCount:(NSUInteger)maxCount
{
    _page->findString(string, toFindOptions(options), maxCount);
}

- (void)_hideFindUI
{
    _page->hideFindUI();
}

- (id <_WKFormDelegate>)_formDelegate
{
    return _formDelegate.getAutoreleased();
}

- (void)_setFormDelegate:(id <_WKFormDelegate>)formDelegate
{
    _formDelegate = formDelegate;

    class FormClient : public API::FormClient {
    public:
        explicit FormClient(WKWebView *webView)
            : m_webView(webView)
        {
        }

        virtual ~FormClient() { }

        virtual bool willSubmitForm(WebKit::WebPageProxy*, WebKit::WebFrameProxy*, WebKit::WebFrameProxy* sourceFrame, const Vector<std::pair<WTF::String, WTF::String>>& textFieldValues, API::Object* userData, WebKit::WebFormSubmissionListenerProxy* listener) override
        {
            if (userData && userData->type() != API::Object::Type::Data) {
                ASSERT(!userData || userData->type() == API::Object::Type::Data);
                m_webView->_page->process().connection()->markCurrentlyDispatchedMessageAsInvalid();
                return false;
            }

            auto formDelegate = m_webView->_formDelegate.get();

            if (![formDelegate respondsToSelector:@selector(_webView:willSubmitFormValues:userObject:submissionHandler:)])
                return false;

            auto valueMap = adoptNS([[NSMutableDictionary alloc] initWithCapacity:textFieldValues.size()]);
            for (const auto& pair : textFieldValues)
                [valueMap setObject:pair.second forKey:pair.first];

            NSObject <NSSecureCoding> *userObject = nil;
            if (API::Data* data = static_cast<API::Data*>(userData)) {
                auto nsData = adoptNS([[NSData alloc] initWithBytesNoCopy:const_cast<void*>(static_cast<const void*>(data->bytes())) length:data->size() freeWhenDone:NO]);
                auto unarchiver = adoptNS([[NSKeyedUnarchiver alloc] initForReadingWithData:nsData.get()]);
                [unarchiver setRequiresSecureCoding:YES];
                @try {
                    userObject = [unarchiver decodeObjectOfClass:[NSObject class] forKey:@"userObject"];
                } @catch (NSException *exception) {
                    LOG_ERROR("Failed to decode user data: %@", exception);
                }
            }

            [formDelegate _webView:m_webView willSubmitFormValues:valueMap.get() userObject:userObject submissionHandler:^{
                listener->continueSubmission();
            }];
            return true;
        }

    private:
        WKWebView *m_webView;
    };

    if (formDelegate)
        _page->setFormClient(std::make_unique<FormClient>(self));
    else
        _page->setFormClient(nullptr);
}

#pragma mark iOS-specific methods

#if PLATFORM(IOS)

- (CGSize)_minimumLayoutSizeOverride
{
    ASSERT(_overridesMinimumLayoutSize);
    return _minimumLayoutSizeOverride;
}

- (void)_setMinimumLayoutSizeOverride:(CGSize)minimumLayoutSizeOverride
{
    _overridesMinimumLayoutSize = YES;
    if (CGSizeEqualToSize(_minimumLayoutSizeOverride, minimumLayoutSizeOverride))
        return;

    _minimumLayoutSizeOverride = minimumLayoutSizeOverride;
    if (!_isAnimatingResize)
        _page->setViewportConfigurationMinimumLayoutSize(WebCore::FloatSize(minimumLayoutSizeOverride));
}

- (CGSize)_minimumLayoutSizeOverrideForMinimalUI
{
    ASSERT(_overridesMinimumLayoutSizeForMinimalUI);
    return _minimumLayoutSizeOverrideForMinimalUI;
}

- (void)_setMinimumLayoutSizeOverrideForMinimalUI:(CGSize)size
{
    _overridesMinimumLayoutSizeForMinimalUI = YES;
    if (CGSizeEqualToSize(_minimumLayoutSizeOverrideForMinimalUI, size))
        return;

    _minimumLayoutSizeOverrideForMinimalUI = size;
    if (!_isAnimatingResize)
        _page->setViewportConfigurationMinimumLayoutSizeForMinimalUI(WebCore::FloatSize(size));
}

- (UIEdgeInsets)_obscuredInsets
{
    return _obscuredInsets;
}

- (void)_setObscuredInsets:(UIEdgeInsets)obscuredInsets
{
    ASSERT(obscuredInsets.top >= 0);
    ASSERT(obscuredInsets.left >= 0);
    ASSERT(obscuredInsets.bottom >= 0);
    ASSERT(obscuredInsets.right >= 0);

    if (UIEdgeInsetsEqualToEdgeInsets(_obscuredInsets, obscuredInsets))
        return;

    _obscuredInsets = obscuredInsets;

    [self _updateVisibleContentRects];
    [_customContentView web_setObscuredInsets:obscuredInsets];
}

- (void)_setInterfaceOrientationOverride:(UIInterfaceOrientation)interfaceOrientation
{
    if (!_overridesInterfaceOrientation)
        [[NSNotificationCenter defaultCenter] removeObserver:self name:UIWindowDidRotateNotification object:nil];

    _overridesInterfaceOrientation = YES;

    if (interfaceOrientation == _interfaceOrientationOverride)
        return;

    _interfaceOrientationOverride = interfaceOrientation;

    if (!_isAnimatingResize)
        _page->setDeviceOrientation(deviceOrientationForUIInterfaceOrientation(_interfaceOrientationOverride));
}

- (UIInterfaceOrientation)_interfaceOrientationOverride
{
    ASSERT(_overridesInterfaceOrientation);
    return _interfaceOrientationOverride;
}

- (CGSize)_maximumUnobscuredSizeOverride
{
    ASSERT(_overridesMaximumUnobscuredSize);
    return _maximumUnobscuredSizeOverride;
}

- (void)_setMaximumUnobscuredSizeOverride:(CGSize)size
{
    ASSERT(size.width <= self.bounds.size.width && size.height <= self.bounds.size.height);
    _overridesMaximumUnobscuredSize = YES;
    if (CGSizeEqualToSize(_maximumUnobscuredSizeOverride, size))
        return;

    _maximumUnobscuredSizeOverride = size;
    if (!_isAnimatingResize)
        _page->setMaximumUnobscuredSize(WebCore::FloatSize(size));
}

- (void)_setBackgroundExtendsBeyondPage:(BOOL)backgroundExtends
{
    _page->setBackgroundExtendsBeyondPage(backgroundExtends);
}

- (BOOL)_backgroundExtendsBeyondPage
{
    return _page->backgroundExtendsBeyondPage();
}

- (void)_beginInteractiveObscuredInsetsChange
{
    ASSERT(!_isChangingObscuredInsetsInteractively);
    _isChangingObscuredInsetsInteractively = YES;
}

- (void)_endInteractiveObscuredInsetsChange
{
    ASSERT(_isChangingObscuredInsetsInteractively);
    _isChangingObscuredInsetsInteractively = NO;
    [self _updateVisibleContentRects];
}

- (void)_beginAnimatedResizeWithUpdates:(void (^)(void))updateBlock
{
    _isAnimatingResize = YES;

    if (_customContentView) {
        updateBlock();
        return;
    }

    _resizeAnimationTransformAdjustments = CATransform3DIdentity;

    NSUInteger indexOfContentView = [[_scrollView subviews] indexOfObject:_contentView.get()];
    _resizeAnimationView = adoptNS([[UIView alloc] init]);
    [_scrollView insertSubview:_resizeAnimationView.get() atIndex:indexOfContentView];
    [_resizeAnimationView addSubview:_contentView.get()];
    WebCore::FloatRect oldUnobscuredContentRect = _page->unobscuredContentRect();

    updateBlock();

    CGRect newBounds = self.bounds;
    CGSize newMinimumLayoutSize = newBounds.size;

    CGSize contentSizeInContentViewCoordinates = [_contentView bounds].size;
    [_scrollView setMinimumZoomScale:std::min(newMinimumLayoutSize.width / contentSizeInContentViewCoordinates.width, [_scrollView minimumZoomScale])];
    [_scrollView setMaximumZoomScale:std::max(newMinimumLayoutSize.width / contentSizeInContentViewCoordinates.width, [_scrollView maximumZoomScale])];

    // Compute the new scale to keep the current content width in the scrollview.
    CGFloat oldWebViewWidthInContentViewCoordinates = oldUnobscuredContentRect.width();
    CGFloat visibleContentViewWidthInContentCoordinates = std::min(contentSizeInContentViewCoordinates.width, oldWebViewWidthInContentViewCoordinates);
    CGFloat targetScale = newMinimumLayoutSize.width / visibleContentViewWidthInContentCoordinates;
    CGFloat resizeAnimationViewAnimationScale = targetScale / contentZoomScale(self);
    [_resizeAnimationView setTransform:CGAffineTransformMakeScale(resizeAnimationViewAnimationScale, resizeAnimationViewAnimationScale)];

    // Compute a new position to keep the content centered.
    CGPoint originalContentCenter = oldUnobscuredContentRect.center();
    CGPoint originalContentCenterInSelfCoordinates = [self convertPoint:originalContentCenter fromView:_contentView.get()];
    CGRect futureUnobscuredRectInSelfCoordinates = UIEdgeInsetsInsetRect(newBounds, _obscuredInsets);
    CGPoint futureUnobscuredRectCenterInSelfCoordinates = CGPointMake(futureUnobscuredRectInSelfCoordinates.origin.x + futureUnobscuredRectInSelfCoordinates.size.width / 2, futureUnobscuredRectInSelfCoordinates.origin.y + futureUnobscuredRectInSelfCoordinates.size.height / 2);

    CGPoint originalContentOffset = [_scrollView contentOffset];
    CGPoint contentOffset = originalContentOffset;
    contentOffset.x += (originalContentCenterInSelfCoordinates.x - futureUnobscuredRectCenterInSelfCoordinates.x);
    contentOffset.y += (originalContentCenterInSelfCoordinates.y - futureUnobscuredRectCenterInSelfCoordinates.y);

    // Limit the new offset within the scrollview, we do not want to rubber band programmatically.
    CGSize futureContentSizeInSelfCoordinates = CGSizeMake(contentSizeInContentViewCoordinates.width * targetScale, contentSizeInContentViewCoordinates.height * targetScale);
    CGFloat maxHorizontalOffset = futureContentSizeInSelfCoordinates.width - newBounds.size.width + _obscuredInsets.right;
    contentOffset.x = std::min(contentOffset.x, maxHorizontalOffset);
    CGFloat maxVerticalOffset = futureContentSizeInSelfCoordinates.height - newBounds.size.height + _obscuredInsets.bottom;
    contentOffset.y = std::min(contentOffset.y, maxVerticalOffset);

    contentOffset.x = std::max(contentOffset.x, -_obscuredInsets.left);
    contentOffset.y = std::max(contentOffset.y, -_obscuredInsets.top);

    // Make the top/bottom edges "sticky" within 1 pixel.
    if (oldUnobscuredContentRect.maxY() > contentSizeInContentViewCoordinates.height - 1)
        contentOffset.y = maxVerticalOffset;
    if (oldUnobscuredContentRect.y() < 1)
        contentOffset.y = -_obscuredInsets.top;

    // FIXME: if we have content centered after double tap to zoom, we should also try to keep that rect in view.
    [_scrollView setContentSize:roundScrollViewContentSize(*_page, futureContentSizeInSelfCoordinates)];
    [_scrollView setContentOffset:contentOffset];

    CGRect visibleRectInContentCoordinates = [self convertRect:newBounds toView:_contentView.get()];
    CGRect unobscuredRectInContentCoordinates = [self convertRect:futureUnobscuredRectInSelfCoordinates toView:_contentView.get()];

    CGSize minimumLayoutSize = newBounds.size;
    if (_overridesMinimumLayoutSize)
        minimumLayoutSize = _minimumLayoutSizeOverride;

    CGSize minimumLayoutSizeForMinimalUI = minimumLayoutSize;
    if (_overridesMinimumLayoutSizeForMinimalUI)
        minimumLayoutSizeForMinimalUI = _minimumLayoutSizeOverrideForMinimalUI;

    CGSize maximumUnobscuredSize = newBounds.size;
    if (_overridesMaximumUnobscuredSize)
        maximumUnobscuredSize = _maximumUnobscuredSizeOverride;

    int32_t orientation;
    if (_overridesInterfaceOrientation)
        orientation = deviceOrientationForUIInterfaceOrientation(_interfaceOrientationOverride);
    else
        orientation = _page->deviceOrientation();

    _page->dynamicViewportSizeUpdate(WebCore::FloatSize(minimumLayoutSize), WebCore::FloatSize(minimumLayoutSizeForMinimalUI), WebCore::FloatSize(maximumUnobscuredSize), visibleRectInContentCoordinates, unobscuredRectInContentCoordinates, futureUnobscuredRectInSelfCoordinates, targetScale, orientation);
}

- (void)_endAnimatedResize
{
    _page->synchronizeDynamicViewportUpdate();

    if (!_customContentView && _isAnimatingResize) {
        NSUInteger indexOfResizeAnimationView = [[_scrollView subviews] indexOfObject:_resizeAnimationView.get()];
        [_scrollView insertSubview:_contentView.get() atIndex:indexOfResizeAnimationView];

        CALayer *contentViewLayer = [_contentView layer];
        CATransform3D resizeAnimationTransformAdjustements = _resizeAnimationTransformAdjustments;
        CGFloat adjustmentScale = resizeAnimationTransformAdjustements.m11;
        contentViewLayer.sublayerTransform = CATransform3DIdentity;

        CGFloat animatingScaleTarget = [[_resizeAnimationView layer] transform].m11;
        CALayer *contentLayer = [_contentView layer];
        CATransform3D contentLayerTransform = contentLayer.transform;
        CGFloat currentScale = [[_resizeAnimationView layer] transform].m11 * contentLayerTransform.m11;

        // We cannot use [UIScrollView setZoomScale:] directly because the UIScrollView delegate would get a callback with
        // an invalid contentOffset. The real content offset is only set below.
        // Since there is no public API for setting both the zoomScale and the contentOffset, we set the zoomScale manually
        // on the zoom layer and then only change the contentOffset.
        CGFloat adjustedScale = adjustmentScale * currentScale;
        contentLayerTransform.m11 = adjustedScale;
        contentLayerTransform.m22 = adjustedScale;
        contentLayer.transform = contentLayerTransform;

        CGPoint currentScrollOffset = [_scrollView contentOffset];
        double horizontalScrollAdjustement = _resizeAnimationTransformAdjustments.m41 * animatingScaleTarget;
        double verticalScrollAdjustment = _resizeAnimationTransformAdjustments.m42 * animatingScaleTarget;

        [_scrollView setContentSize:roundScrollViewContentSize(*_page, [_contentView frame].size)];
        [_scrollView setContentOffset:CGPointMake(currentScrollOffset.x - horizontalScrollAdjustement, currentScrollOffset.y - verticalScrollAdjustment)];

        [_resizeAnimationView removeFromSuperview];
        _resizeAnimationView = nil;
    }

    _isAnimatingResize = NO;
    _resizeAnimationTransformAdjustments = CATransform3DIdentity;

    [self _updateVisibleContentRects];
}

- (void)_showInspectorIndication
{
    [_contentView setShowingInspectorIndication:YES];
}

- (void)_hideInspectorIndication
{
    [_contentView setShowingInspectorIndication:NO];
}

- (void)_setOverlaidAccessoryViewsInset:(CGSize)inset
{
    [_customContentView web_setOverlaidAccessoryViewsInset:inset];
}

- (void)_snapshotRect:(CGRect)rectInViewCoordinates intoImageOfWidth:(CGFloat)imageWidth completionHandler:(void(^)(CGImageRef))completionHandler
{
    CGRect snapshotRectInContentCoordinates = [self convertRect:rectInViewCoordinates toView:_contentView.get()];
    CGFloat imageHeight = imageWidth / snapshotRectInContentCoordinates.size.width * snapshotRectInContentCoordinates.size.height;
    CGSize imageSize = CGSizeMake(imageWidth, imageHeight);
    
#if PLATFORM(IOS)
    WebKit::ProcessThrottler::BackgroundActivityToken* activityToken = new WebKit::ProcessThrottler::BackgroundActivityToken(_page->process().throttler());
#endif
    
    void(^copiedCompletionHandler)(CGImageRef) = [completionHandler copy];
    _page->takeSnapshot(WebCore::enclosingIntRect(snapshotRectInContentCoordinates), WebCore::expandedIntSize(WebCore::FloatSize(imageSize)), WebKit::SnapshotOptionsExcludeDeviceScaleFactor, [=](const WebKit::ShareableBitmap::Handle& imageHandle, WebKit::CallbackBase::Error) {
#if PLATFORM(IOS)
        // Automatically delete when this goes out of scope.
        auto uniqueActivityToken = std::unique_ptr<WebKit::ProcessThrottler::BackgroundActivityToken>(activityToken);
#endif
        
        if (imageHandle.isNull()) {
            copiedCompletionHandler(nullptr);
            [copiedCompletionHandler release];
            return;
        }

        RefPtr<WebKit::ShareableBitmap> bitmap = WebKit::ShareableBitmap::create(imageHandle, WebKit::SharedMemory::ReadOnly);

        if (!bitmap) {
            copiedCompletionHandler(nullptr);
            [copiedCompletionHandler release];
            return;
        }

        RetainPtr<CGImageRef> cgImage;
        cgImage = bitmap->makeCGImage();
        copiedCompletionHandler(cgImage.get());
        [copiedCompletionHandler release];
    });
}

- (void)_overrideLayoutParametersWithMinimumLayoutSize:(CGSize)minimumLayoutSize minimumLayoutSizeForMinimalUI:(CGSize)minimumLayoutSizeForMinimalUI maximumUnobscuredSizeOverride:(CGSize)maximumUnobscuredSizeOverride
{
    // FIXME: After Safari is updated to use this function instead of setting the parameters separately, we should remove
    // the individual setters and send a single message to send everything at once to the WebProcess.
    self._minimumLayoutSizeOverride = minimumLayoutSize;
    self._minimumLayoutSizeOverrideForMinimalUI = minimumLayoutSizeForMinimalUI;
    self._maximumUnobscuredSizeOverride = maximumUnobscuredSizeOverride;
}

- (UIView *)_viewForFindUI
{
    return [self viewForZoomingInScrollView:[self scrollView]];
}

- (BOOL)_isDisplayingPDF
{
    return [_customContentView isKindOfClass:[WKPDFView class]];
}

- (NSData *)_dataForDisplayedPDF
{
    if (![self _isDisplayingPDF])
        return nil;
    CGPDFDocumentRef pdfDocument = [(WKPDFView *)_customContentView pdfDocument];
    return [(NSData *)CGDataProviderCopyData(CGPDFDocumentGetDataProvider(pdfDocument)) autorelease];
}

- (NSString *)_suggestedFilenameForDisplayedPDF
{
    if (![self _isDisplayingPDF])
        return nil;
    return [(WKPDFView *)_customContentView.get() suggestedFilename];
}

- (CGFloat)_viewportMetaTagWidth
{
    return _viewportMetaTagWidth;
}

- (_WKWebViewPrintFormatter *)_webViewPrintFormatter
{
    UIViewPrintFormatter *viewPrintFormatter = self.viewPrintFormatter;
    ASSERT([viewPrintFormatter isKindOfClass:[_WKWebViewPrintFormatter class]]);
    return (_WKWebViewPrintFormatter *)viewPrintFormatter;
}

#else

#pragma mark - OS X-specific methods

- (NSColor *)_pageExtendedBackgroundColor
{
    WebCore::Color color = _page->pageExtendedBackgroundColor();
    if (!color.isValid())
        return nil;

    return nsColor(color);
}

- (BOOL)_drawsTransparentBackground
{
    return _page->drawsTransparentBackground();
}

- (void)_setDrawsTransparentBackground:(BOOL)drawsTransparentBackground
{
    _page->setDrawsTransparentBackground(drawsTransparentBackground);
}

- (void)_setTopContentInset:(CGFloat)contentInset
{
    _page->setTopContentInset(contentInset);
}

- (CGFloat)_topContentInset
{
    return _page->topContentInset();
}

#endif

@end

#if !TARGET_OS_IPHONE

@implementation WKWebView (WKIBActions)

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)item
{
    SEL action = item.action;

    if (action == @selector(goBack:))
        return !!_page->backForwardList().backItem();

    if (action == @selector(goForward:))
        return !!_page->backForwardList().forwardItem();

    if (action == @selector(stopLoading:)) {
        // FIXME: Return no if we're stopped.
        return YES;
    }

    if (action == @selector(reload:) || action == @selector(reloadFromOrigin:)) {
        // FIXME: Return no if we're loading.
        return YES;
    }

    return NO;
}

- (IBAction)goBack:(id)sender
{
    [self goBack];
}

- (IBAction)goForward:(id)sender
{
    [self goForward];
}

- (IBAction)reload:(id)sender
{
    [self reload];
}

- (IBAction)reloadFromOrigin:(id)sender
{
    [self reloadFromOrigin];
}

- (IBAction)stopLoading:(id)sender
{
    _page->stopLoading();
}

@end

#endif

#if PLATFORM(IOS)
@implementation WKWebView (_WKWebViewPrintFormatter)

- (Class)_printFormatterClass
{
    return [_WKWebViewPrintFormatter class];
}

- (NSInteger)_computePageCountAndStartDrawingToPDFForFrame:(_WKFrameHandle *)frame printInfo:(const WebKit::PrintInfo&)printInfo firstPage:(uint32_t)firstPage computedTotalScaleFactor:(double&)totalScaleFactor
{
    if ([self _isDisplayingPDF])
        return CGPDFDocumentGetNumberOfPages([(WKPDFView *)_customContentView pdfDocument]);

    _pageIsPrintingToPDF = YES;
    Vector<WebCore::IntRect> pageRects;
    uint64_t frameID = frame ? frame._frameID : _page->mainFrame()->frameID();
    if (!_page->sendSync(Messages::WebPage::ComputePagesForPrintingAndStartDrawingToPDF(frameID, printInfo, firstPage), Messages::WebPage::ComputePagesForPrintingAndStartDrawingToPDF::Reply(pageRects, totalScaleFactor)))
        return 0;
    return pageRects.size();
}

- (void)_endPrinting
{
    _pageIsPrintingToPDF = NO;
    _printedDocument = nullptr;
    _page->send(Messages::WebPage::EndPrinting());
}

// FIXME: milliseconds::max() overflows when converted to nanoseconds, causing condition_variable::wait_for() to believe
// a timeout occurred on any spurious wakeup. Use nanoseconds::max() (converted to ms) to avoid this. We should perhaps
// change waitForAndDispatchImmediately() to take nanoseconds to avoid this issue.
static constexpr std::chrono::milliseconds didFinishLoadingTimeout = std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::nanoseconds::max());

- (CGPDFDocumentRef)_printedDocument
{
    if ([self _isDisplayingPDF]) {
        ASSERT(!_pageIsPrintingToPDF);
        return [(WKPDFView *)_customContentView pdfDocument];
    }

    if (_pageIsPrintingToPDF) {
        if (!_page->process().connection()->waitForAndDispatchImmediately<Messages::WebPageProxy::DidFinishDrawingPagesToPDF>(_page->pageID(), didFinishLoadingTimeout)) {
            ASSERT_NOT_REACHED();
            return nullptr;
        }
        ASSERT(!_pageIsPrintingToPDF);
    }
    return _printedDocument.get();
}

- (void)_setPrintedDocument:(CGPDFDocumentRef)printedDocument
{
    if (!_pageIsPrintingToPDF)
        return;
    ASSERT(![self _isDisplayingPDF]);
    _printedDocument = printedDocument;
    _pageIsPrintingToPDF = NO;
}

@end
#endif

#endif // WK_API_ENABLED
