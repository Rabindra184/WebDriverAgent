/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree.
 */

#import <XCTest/XCTest.h>

#import "FBSession.h"
#import "FBConfiguration.h"
#import "FBResponsePayload.h"
#import "FBRouteRequest-Private.h"
#import "FBSessionCommands.h"
#import "FBSettings.h"
#import "RouteResponse.h"
#import "XCUIApplicationDouble.h"

@interface FBSessionCommands (FBSessionlessSettingsTestable)
+ (id<FBResponsePayload>)handleGetSettings:(FBRouteRequest *)request;
+ (id<FBResponsePayload>)handleSetSettings:(FBRouteRequest *)request;
@end

@interface FBSessionTests : XCTestCase
@property (nonatomic, strong) FBSession *session;
@property (nonatomic, strong) XCUIApplication *testedApplication;
@property (nonatomic) BOOL shouldTerminateAppValue;
@end

@implementation FBSessionTests

- (void)setUp
{
  [super setUp];
  self.testedApplication = (id)XCUIApplicationDouble.new;
  self.shouldTerminateAppValue = FBConfiguration.sharedInstance.shouldTerminateApp;
  FBConfiguration.sharedInstance.shouldTerminateApp = NO;
  self.session = [FBSession initWithApplication:self.testedApplication];
}

- (void)tearDown
{
  [self.session kill];
  FBConfiguration.sharedInstance.shouldTerminateApp = self.shouldTerminateAppValue;
  [super tearDown];
}

- (void)testSessionFetching
{
  FBSession *fetchedSession = [FBSession sessionWithIdentifier:self.session.identifier];
  XCTAssertEqual(self.session, fetchedSession);
}

- (void)testSessionFetchingBadIdentifier
{
  XCTAssertNil([FBSession sessionWithIdentifier:@"FAKE_IDENTIFIER"]);
}

- (void)testSessionCreation
{
  XCTAssertNotNil(self.session.identifier);
  XCTAssertNotNil(self.session.elementCache);
}

- (void)testActiveSession
{
  XCTAssertEqual(self.session, [FBSession activeSession]);
}

- (void)testActiveSessionIsNilAfterKilling
{
  [self.session kill];
  XCTAssertNil([FBSession activeSession]);
}

// Sessionless /appium/settings routes hand the handlers a request without a session
- (NSDictionary *)sessionlessSettingsResponseWithSettings:(nullable NSDictionary *)settings
{
  FBRouteRequest *request = [FBRouteRequest routeRequestWithURL:[NSURL URLWithString:@"http://localhost:8100/appium/settings"]
                                                     parameters:@{}
                                                      arguments:nil == settings ? @{} : @{@"settings": settings}];
  XCTAssertNil(request.session);
  id<FBResponsePayload> payload = nil == settings
    ? [FBSessionCommands handleGetSettings:request]
    : [FBSessionCommands handleSetSettings:request];
  RouteResponse *response = [RouteResponse new];
  [payload dispatchWithResponse:response];
  return [NSJSONSerialization JSONObjectWithData:response.responseData options:0 error:nil];
}

- (void)testSettingsCanBeReadWithoutSession
{
  NSDictionary *value = [self sessionlessSettingsResponseWithSettings:nil][@"value"];
  XCTAssertEqualObjects(value[FB_SETTING_MJPEG_SERVER_FRAMERATE],
                        @(FBConfiguration.sharedInstance.mjpegServerFramerate));
  XCTAssertEqualObjects(value[FB_SETTING_DEFAULT_ALERT_ACTION], @"");
}

- (void)testSettingsCanBeChangedWithoutSession
{
  NSUInteger framerate = FBConfiguration.sharedInstance.mjpegServerFramerate;
  NSDictionary *value = [self sessionlessSettingsResponseWithSettings:@{
    FB_SETTING_MJPEG_SERVER_FRAMERATE: @(framerate + 1),
    // Session-specific settings must be ignored instead of failing the request
    FB_SETTING_DEFAULT_ACTIVE_APPLICATION: @"com.apple.Preferences",
    FB_SETTING_DEFAULT_ALERT_ACTION: @"accept",
  }][@"value"];
  NSUInteger changedFramerate = FBConfiguration.sharedInstance.mjpegServerFramerate;
  FBConfiguration.sharedInstance.mjpegServerFramerate = framerate;

  XCTAssertEqual(changedFramerate, framerate + 1);
  XCTAssertEqualObjects(value[FB_SETTING_MJPEG_SERVER_FRAMERATE], @(framerate + 1));
  XCTAssertNil(value[FB_SETTING_DEFAULT_ACTIVE_APPLICATION]);
  XCTAssertEqualObjects(value[FB_SETTING_DEFAULT_ALERT_ACTION], @"");
}

@end
