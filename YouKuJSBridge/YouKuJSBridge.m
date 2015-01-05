//
//  YouKuJSBridge.m
//  YouKuJSBridge
//
//  Created by youku on 14/11/24.
//  Copyright (c) 2014年 YouKu. All rights reserved.
//

#import "YouKuJSBridge.h"

#if __has_feature(objc_arc_weak)
#define YKJB_WEAK __weak
#else
#define YKJB_WEAK __unsafe_unretained
#endif

typedef NSDictionary YKJBMessage;

@implementation YouKuJSBridge
{
    YKJB_WEAK UIWebView*                    _webView;                   //Webview
    YKJB_WEAK id                            _webViewDelegate;           //代理
    NSMutableArray*                         _startupMessageQueue;       //消息数组
    NSMutableDictionary*                    _responseCallbacks;         //回调字典
    NSMutableDictionary*                    _messageHandlers;           //
    long                                    _uniqueId;                  //id
    YKJBHandler                             _messageHandler;            //
    NSBundle *                              _resourceBundle;            //
    NSUInteger                              _numRequestsLoading;        //
}

@synthesize delegate = _delegate;

#pragma mark - Class Method

#pragma mark - 初始化
- (id)init
{
    if (self = [super init])
    {
        _startupMessageQueue = [NSMutableArray array];
        _responseCallbacks = [NSMutableDictionary dictionary];
        _uniqueId = 0;
    }
    return self;
}

#pragma mark - delloc
- (void)dealloc {
    [self _platformSpecificDealloc];
    
    _webView = nil;
    _webViewDelegate = nil;
    _startupMessageQueue = nil;
    _responseCallbacks = nil;
    _messageHandlers = nil;
    _messageHandler = nil;
}

#pragma mark - 允许打印
static bool logging = false;
+(void)enableLogging
{
    logging = true;
}

+(instancetype)bridgeForWebView:(UIWebView *)webView handler:(YKJBHandler)handler
{
    return [self bridgeForWebView:webView webViewDelegate:nil handler:handler];
}

+(instancetype)bridgeForWebView:(UIWebView *)webView webViewDelegate:(YKJB_WEBVIEW_DELEGATE_TYPE*)webViewDelegate handler:(YKJBHandler)handler
{
    return [self bridgeForWebView:webView webViewDelegate:webViewDelegate handler:handler resourceBundle:nil];
}

+(instancetype)bridgeForWebView:(UIWebView *)webView webViewDelegate:(YKJB_WEBVIEW_DELEGATE_TYPE*)webViewDelegate handler:(YKJBHandler)handler resourceBundle:(NSBundle *)bundle
{
    YouKuJSBridge* bridge = [[YouKuJSBridge alloc] init];
    [bridge _platformSpecificSetup:webView webViewDelegate:webViewDelegate handler:handler resourceBundle:bundle];
    return bridge;
}

-(void)send:(id)message
{
    [self send:message responseCallback:nil];
}

-(void)send:(id)message responseCallback:(YKJBResponseCallback)responseCallback
{
    [self _sendData:message responseCallback:responseCallback handlerName:nil];
}

-(void)registerHandler:(NSString *)handlerName handler:(YKJBHandler)handler
{
    _messageHandlers[handlerName] = [handler copy];
}

-(void)callHandler:(NSString *)handlerName
{
    [self callHandler:handlerName data:nil responseCallback:nil];
}

-(void)callHandler:(NSString *)handlerName data:(id)data
{
    [self callHandler:handlerName data:data responseCallback:nil];
}

-(void)callHandler:(NSString *)handlerName data:(id)data responseCallback:(YKJBResponseCallback)responseCallback
{
    [self _sendData:data responseCallback:responseCallback handlerName:handlerName];
}

#pragma mark - Platform agnostic internals

#pragma mark - 
- (void)_sendData:(id)data responseCallback:(YKJBResponseCallback)responseCallback handlerName:(NSString*)handlerName
{
    NSMutableDictionary* message = [NSMutableDictionary dictionary];
    
    if (data)
    {
        message[@"data"] = data;
    }
    
    if (responseCallback)
    {
        NSString* callbackId = [NSString stringWithFormat:@"objc_cb_%ld", ++_uniqueId];
        _responseCallbacks[callbackId] = [responseCallback copy];
        message[@"callbackId"] = callbackId;
    }
    
    if (handlerName)
    {
        message[@"handlerName"] = handlerName;
    }
    [self _queueMessage:message];
}

- (void)_queueMessage:(YKJBMessage*)message
{
    if (_startupMessageQueue)
    {
        [_startupMessageQueue addObject:message];
    }
    else
    {
        [self _dispatchMessage:message];
    }
}

- (void)_dispatchMessage:(YKJBMessage*)message
{
    NSString *messageJSON = [self _serializeMessage:message];
    [self _log:@"SEND" json:messageJSON];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\'" withString:@"\\\'"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\r" withString:@"\\r"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\f" withString:@"\\f"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\u2028" withString:@"\\u2028"];
    messageJSON = [messageJSON stringByReplacingOccurrencesOfString:@"\u2029" withString:@"\\u2029"];
    
    NSString* javascriptCommand = [NSString stringWithFormat:@"YoukuJSBridge._handleMessageFromObjC('%@');", messageJSON];
    if ([[NSThread currentThread] isMainThread])
    {
        [_webView stringByEvaluatingJavaScriptFromString:javascriptCommand];
    }
    else
    {
        __strong UIWebView* strongWebView = _webView;
        dispatch_sync(dispatch_get_main_queue(), ^{
            [strongWebView stringByEvaluatingJavaScriptFromString:javascriptCommand];
        });
    }
}

- (void)_flushMessageQueue
{
    NSString *messageQueueString = [_webView stringByEvaluatingJavaScriptFromString:@"YoukuJSBridge._fetchQueue();"];
    
    id messages = [self _deserializeMessageJSON:messageQueueString];
    if (![messages isKindOfClass:[NSArray class]])
    {
        NSLog(@"YoukuJSBridge: WARNING: Invalid %@ received: %@", [messages class], messages);
        return;
    }
    for (YKJBMessage* message in messages)
    {
        if (![message isKindOfClass:[YKJBMessage class]])
        {
            NSLog(@"YoukuJSBridge: WARNING: Invalid %@ received: %@", [message class], message);
            continue;
        }
        [self _log:@"RCVD" json:message];
        
        NSString* responseId = message[@"responseId"];
        if (responseId)
        {
            YKJBResponseCallback responseCallback = _responseCallbacks[responseId];
            responseCallback(message[@"responseData"]);
            [_responseCallbacks removeObjectForKey:responseId];
        }
        else
        {
            YKJBResponseCallback responseCallback = NULL;
            NSString* callbackId = message[@"callbackId"];
            if (callbackId)
            {
                responseCallback = ^(id responseData)
                {
                    if (responseData == nil)
                    {
                        responseData = [NSNull null];
                    }
                    
                    YKJBMessage* msg = @{ @"responseId":callbackId, @"responseData":responseData };
                    [self _queueMessage:msg];
                };
            }
            else
            {
                responseCallback = ^(id ignoreResponseData)
                {
                    // Do nothing
                };
            }
            
            YKJBHandler handler;
            if (message[@"handlerName"])
            {
                handler = _messageHandlers[message[@"handlerName"]];
            }
            else
            {
                handler = _messageHandler;
            }
            
            if (!handler)
            {
                [NSException raise:@"YKJBNoHandlerException" format:@"No handler for message from JS: %@", message];
            }
            
            handler(message[@"data"], responseCallback);
        }
    }
}

- (NSString *)_serializeMessage:(id)message {
    return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:message options:0 error:nil] encoding:NSUTF8StringEncoding];
}

- (NSArray*)_deserializeMessageJSON:(NSString *)messageJSON {
    return [NSJSONSerialization JSONObjectWithData:[messageJSON dataUsingEncoding:NSUTF8StringEncoding] options:NSJSONReadingAllowFragments error:nil];
}

- (void)_log:(NSString *)action json:(id)json
{
    if (!logging)
        return;
    if (![json isKindOfClass:[NSString class]])
    {
        json = [self _serializeMessage:json];
    }
    if ([json length] > 500)
    {
        NSLog(@"YKJB %@: %@ [...]", action, [json substringToIndex:500]);
    }
    else
    {
        NSLog(@"YKJB %@: %@", action, json);
    }
}

#pragma mark - webViewDelegate

- (void) _platformSpecificSetup:(UIWebView*)webView webViewDelegate:(id<UIWebViewDelegate>)webViewDelegate handler:(YKJBHandler)messageHandler resourceBundle:(NSBundle*)bundle
{
    _messageHandler = messageHandler;
    _webView = webView;
    _webViewDelegate = webViewDelegate;
    _messageHandlers = [NSMutableDictionary dictionary];
    _webView.delegate = self;
    _resourceBundle = bundle;
}

- (void) _platformSpecificDealloc
{
    _webView.delegate = nil;
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    if (webView != _webView)
        return;
    
    _numRequestsLoading--;
    
    if (_numRequestsLoading == 0 && ![[webView stringByEvaluatingJavaScriptFromString:@"typeof YoukuJSBridge == 'object'"] isEqualToString:@"true"])
    {
        NSBundle *bundle = _resourceBundle ? _resourceBundle : [NSBundle mainBundle];
        NSString *filePath = [bundle pathForResource:@"YouKuJSBridge" ofType:@"txt"];
        NSString *js = [NSString stringWithContentsOfFile:filePath encoding:NSUTF8StringEncoding error:nil];
        [webView stringByEvaluatingJavaScriptFromString:js];
    }
    
    if (_startupMessageQueue)
    {
        for (id queuedMessage in _startupMessageQueue)
        {
            [self _dispatchMessage:queuedMessage];
        }
        _startupMessageQueue = nil;
    }
    
    __strong YKJB_WEBVIEW_DELEGATE_TYPE* strongDelegate = _webViewDelegate;
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webViewDidFinishLoad:)])
    {
        [strongDelegate webViewDidFinishLoad:webView];
    }
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    if (webView != _webView)
        return;
    
    _numRequestsLoading--;
    
    __strong YKJB_WEBVIEW_DELEGATE_TYPE* strongDelegate = _webViewDelegate;
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [strongDelegate webView:webView didFailLoadWithError:error];
    }
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    if (webView != _webView)
        return YES;
    NSURL *url = [request URL];
    __strong YKJB_WEBVIEW_DELEGATE_TYPE* strongDelegate = _webViewDelegate;
    if ([[url scheme] isEqualToString:kCustomProtocolScheme])
    {
        if ([[url host] isEqualToString:kQueueHasMessage])
        {
            [self _flushMessageQueue];
        }
        else
        {
            NSLog(@"YoukuJSBridge: WARNING: Received unknown WebViewJavascriptBridge command %@://%@", kCustomProtocolScheme, [url path]);
        }
        return NO;
    }
    else if (strongDelegate && [strongDelegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)])
    {
        return [strongDelegate webView:webView shouldStartLoadWithRequest:request navigationType:navigationType];
    }
    else
    {
        return YES;
    }
}

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    if (webView != _webView)
        return;
    
    _numRequestsLoading++;
    
    __strong YKJB_WEBVIEW_DELEGATE_TYPE* strongDelegate = _webViewDelegate;
    if (strongDelegate && [strongDelegate respondsToSelector:@selector(webViewDidStartLoad:)])
    {
        [strongDelegate webViewDidStartLoad:webView];
    }
}

@end

@implementation returnObject


@end
