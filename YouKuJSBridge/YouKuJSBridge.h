//
//  YouKuJSBridge.h
//  YouKuJSBridge
//
//  Created by youku on 14/11/24.
//  Copyright (c) 2014年 YouKu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

//用于区分来源
#define kCustomProtocolScheme @"ykjbscheme"
#define kQueueHasMessage      @"__YKJB_QUEUE_MESSAGE__"

#define YKJB_WEBVIEW_DELEGATE_TYPE NSObject<UIWebViewDelegate>

typedef void (^YKJBResponseCallback)(id responseData);
typedef void (^YKJBHandler)(id data, YKJBResponseCallback responseCallback);

@interface returnObject : NSObject

@property(nonatomic,strong) NSString * error;
@property(nonatomic,strong) NSString * videoId;
@property(nonatomic,strong) NSString * shareTarget;
@property(nonatomic,strong) NSString * timepoint;
@property(nonatomic,strong) NSString * freshVideoId;
@property(nonatomic,strong) NSString * state;

@end

@protocol YouKuJSBridgeDelegate <NSObject>

@required

@end

@interface YouKuJSBridge : YKJB_WEBVIEW_DELEGATE_TYPE

@property(nonatomic)id<YouKuJSBridgeDelegate>delegate;

+ (instancetype)bridgeForWebView:(UIWebView*)webView handler:(YKJBHandler)handler;
+ (instancetype)bridgeForWebView:(UIWebView*)webView webViewDelegate:(YKJB_WEBVIEW_DELEGATE_TYPE*)webViewDelegate handler:(YKJBHandler)handler;
+ (instancetype)bridgeForWebView:(UIWebView*)webView webViewDelegate:(YKJB_WEBVIEW_DELEGATE_TYPE*)webViewDelegate handler:(YKJBHandler)handler resourceBundle:(NSBundle*)bundle;
+ (void)enableLogging;

- (void)send:(id)message;
- (void)send:(id)message responseCallback:(YKJBResponseCallback)responseCallback;
- (void)registerHandler:(NSString*)handlerName handler:(YKJBHandler)handler;
- (void)callHandler:(NSString*)handlerName;
- (void)callHandler:(NSString*)handlerName data:(id)data;
- (void)callHandler:(NSString*)handlerName data:(id)data responseCallback:(YKJBResponseCallback)responseCallback;

@end
