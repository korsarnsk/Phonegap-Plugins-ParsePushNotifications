//
//  ParsePushNotificationPlugin.m
//  HelloWorld
//
//  Created by yoyo on 2/12/14.
//
//

#import "ParsePushNotificationPlugin.h"
#import <Parse/Parse.h>
#import "SSKeychain.h"

@implementation ParsePushNotificationPlugin

@synthesize callbackId;
@synthesize pendingNotifications = _pendingNotifications;

static NSDictionary *coldstartNotification;

NSMutableArray *jsEventQueue;
BOOL canDeliverNotifications = NO;

/*
   Ideally the UIApplicationDidFinishLaunchingNotification would go in pluginInitialize
   but it is too late in the life cycle to catch the actual event for remote notifications.

   For local notifications it is fine becuase the base CDVPlugin takes care of forwarding the event
   but not for remote notifications and as we dont want to make changes to the cordova base classes:

   We use the static load method to attach the observer and if the handler finds a corresponding notification
   it is stored in a static var.

   Later on in pluginInitialize we check if the static var conatins a notification and if yes use it

   Additionaly, weo make sure the notification callbacks in the client javascript are not delivered
   until the client app is ready for them by checking:
   1. The app is in the foreground
   2. The 'register' method has been called on the plugin - passing in a handler

   If either of these conditions is not true we hold onto notifications in a queue and then flush it to the client
   when they are fulfilled.

 */

/* Holds the notifications data */
- (NSMutableArray*)pendingNotifications {
    if(_pendingNotifications == nil) {
        _pendingNotifications = [[NSMutableArray alloc] init];
    }
    return _pendingNotifications;
}

/* Activates success callback with notifications as argument */
- (void)getNotifications:(CDVInvokedUrlCommand*)command {
    [self.commandDelegate runInBackground:^{
        CDVPluginResult* pluginResult = nil;
        NSString *notificationJSON = [self.pendingNotifications JSONString];
        
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:notificationJSON];
        
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
        [self.pendingNotifications removeAllObjects];
    }];
}

- (void)isPushAllowed:(CDVInvokedUrlCommand*)command {
    CDVPluginResult* pluginResult = nil;

    UIRemoteNotificationType rnType = UIRemoteNotificationTypeNone;
    UIUserNotificationSettings* settings = nil;
    UIUserNotificationType unType = UIUserNotificationTypeNone;

    if ([[UIApplication sharedApplication] respondsToSelector:@selector(isRegisteredForRemoteNotifications)]){
        // iOS = 8
        settings = [[UIApplication sharedApplication] currentUserNotificationSettings];
        unType = settings.types;
        if (unType == UIUserNotificationTypeNone) {
            NSLog(@"Push is disabled");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Push is disabled"];
        } else {
            NSLog(@"Push is enabled");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Push is enabled"];
        }
    }
    else {
        rnType = [[UIApplication sharedApplication] enabledRemoteNotificationTypes];
        if (rnType == UIRemoteNotificationTypeNone) {
            NSLog(@"Push is disabled");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Push is disabled"];
        } else {
            NSLog(@"Push is enabled");
            pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"Push is enabled"];
        }
    }

    [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

+(void) load
{
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkForColdStartNotification:)
         name:UIApplicationDidFinishLaunchingNotification object:nil];
}

+ (void) checkForColdStartNotification:(NSNotification *)notification
{
        NSDictionary *launchOptions = [notification userInfo];
        NSDictionary *payload = [launchOptions objectForKey: @"UIApplicationLaunchOptionsRemoteNotificationKey"];

        if(payload) {
                NSMutableDictionary *extendedPayload = [payload mutableCopy];
                [extendedPayload setObject:[NSNumber numberWithBool:NO] forKey:@"receivedInForeground"];
                coldstartNotification = extendedPayload;
        }
}

- (void)unregister:(CDVInvokedUrlCommand*)command;
{
        self.callbackId = command.callbackId;

        [[UIApplication sharedApplication] unregisterForRemoteNotifications];
        [self successWithMessage:@"unregistered"];
}

- (void)register :(CDVInvokedUrlCommand*)command;
{
        NSMutableDictionary* options = [command.arguments objectAtIndex:0];

        NSString *appId = [options objectForKey:@"appId"];
        NSString *clientKey = [options objectForKey:@"clientKey"];

        [Parse setApplicationId:appId clientKey:clientKey];

        // Register for Push Notitications, if running iOS 8
        if ([[UIApplication sharedApplication] respondsToSelector:@selector(registerUserNotificationSettings:)]) {
                UIUserNotificationType userNotificationTypes = (UIUserNotificationTypeAlert |
                                                                UIUserNotificationTypeBadge |
                                                                UIUserNotificationTypeSound);
                UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:userNotificationTypes
                                                        categories:nil];
                [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
                [[UIApplication sharedApplication] registerForRemoteNotifications];
        } else {
                // Register for Push Notifications before iOS 8
                [[UIApplication sharedApplication] registerForRemoteNotificationTypes:(UIRemoteNotificationTypeBadge |
                                                                                       UIRemoteNotificationTypeAlert |
                                                                                       UIRemoteNotificationTypeSound)];
        }


        self.callbackId = command.callbackId;

        [self flushNotificationEventQueue];
        canDeliverNotifications = YES;
}


- (void)getInstallationId:(CDVInvokedUrlCommand*) command
{
        [self.commandDelegate runInBackground:^{
                 CDVPluginResult* pluginResult = nil;
                 PFInstallation *currentInstallation = [PFInstallation currentInstallation];
                 NSString *installId = currentInstallation.installationId;
                 pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:installId];
                 [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
         }];
}
- (void)getEndUserId:(CDVInvokedUrlCommand*) command
{
        [self.commandDelegate runInBackground:^{
                 CDVPluginResult* pluginResult = nil;

                 NSString *storedUUID = [SSKeychain passwordForService:@"com.perkins.ftwinteractive" account:@"perkins_user"];
                 NSLog(@"Current UUID:  %@", storedUUID);
                 if(nil == storedUUID) {
                         NSString *UUID = [[[UIDevice currentDevice] identifierForVendor] UUIDString];

                         NSLog(@"Storing %@ in keychain as UUID", UUID);
                         [SSKeychain setPassword:UUID forService:@"com.perkins.ftwinteractive" account:@"perkins_user"];
                         storedUUID = UUID;
                 }


                 pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:storedUUID];
                 [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
         }];
}

- (void)getSubscriptions: (CDVInvokedUrlCommand *)command
{
        NSArray *channels = [PFInstallation currentInstallation].channels;
        CDVPluginResult* pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:channels];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)subscribeToChannel: (CDVInvokedUrlCommand *)command
{
        CDVPluginResult* pluginResult = nil;
        PFInstallation *currentInstallation = [PFInstallation currentInstallation];
        NSString *channel = [command.arguments objectAtIndex:0];
        [currentInstallation addUniqueObject:channel forKey:@"channels"];
        [currentInstallation saveInBackground];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void)unsubscribeFromChannel: (CDVInvokedUrlCommand *)command
{
        CDVPluginResult* pluginResult = nil;
        PFInstallation *currentInstallation = [PFInstallation currentInstallation];
        NSString *channel = [command.arguments objectAtIndex:0];
        [currentInstallation removeObject:channel forKey:@"channels"];
        [currentInstallation saveInBackground];
        pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}


- (void)didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
        NSMutableDictionary *results = [NSMutableDictionary dictionary];
        NSString *token = [[[[deviceToken description] stringByReplacingOccurrencesOfString:@"<"withString:@""]
                            stringByReplacingOccurrencesOfString:@">" withString:@""]
                           stringByReplacingOccurrencesOfString: @" " withString: @""];
        [results setValue:token forKey:@"deviceToken"];

#if !TARGET_IPHONE_SIMULATOR

        PFInstallation *currentInstallation = [PFInstallation currentInstallation];
        [currentInstallation setDeviceTokenFromData:deviceToken];
        if (currentInstallation.badge != 0) {
            currentInstallation.badge = 0;
        }
        [currentInstallation saveInBackground];
        [self successWithMessage:[NSString stringWithFormat:@"%@", token]];
#endif
}

- (void)didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
        [self failWithMessage:@"" withError:error];
}

- (void)didReceiveRemoteNotificationWithPayload: (NSDictionary *)payload
{
        NSLog(@"didReceiveRemoteNotificationWithPayload received");
        [self.pendingNotifications addObject:payload];
        /*NSDictionary *aps = [payload objectForKey:@"aps"];
        NSMutableDictionary *data = [[payload objectForKey:@"data"] mutableCopy];

        if(data == nil) {
                data = [[NSMutableDictionary alloc] init];
        }*/

        /*

           the aps.alert value is required in order for the ios notification center to have something to show
           or else it wouls show the full JSON payload.

           however on the js side we want to access all the properties for this notification inside a single
           object and care not for ios specific implemenataion such as the aps wrapper

           we could just duplicate the text and have it in both *aps.alert* and inside data.message but as the
           payload size limit is only 256 bytes it is better to check if an explicit data.message value exists
           and if not just copy aps.alert into it

         */

        /*if([aps objectForKey:@"alert"]) {
                if(![data objectForKey:@"message"]) {
                        [data setObject:[aps objectForKey:@"alert"] forKey:@"message"];
                }
        }*/

        BOOL receivedInForeground = [[payload objectForKey:@"receivedInForeground"] boolValue];
        NSString* stateName = receivedInForeground ? @"foreground" : @"background";

        /*NSMutableDictionary *data = [[payload allKeys] mutableCopy];*/
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];

        NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];

        NSLog(@"Msg: %@", json);

        NSString * jsCallBack = [NSString stringWithFormat:@"setTimeout(function(){window.parsePush.ontrigger('%@', %@)},0)", stateName, json];

        if(receivedInForeground) {
                [self.webView stringByEvaluatingJavaScriptFromString:jsCallBack];
        }
        else
        {
                if(jsEventQueue == nil)
                {
                        jsEventQueue = [[NSMutableArray alloc] init];
                }

                [jsEventQueue addObject:jsCallBack];
                [PFAnalytics trackAppOpenedWithRemoteNotificationPayload:payload];
        }
}


- (void) didBecomeActive:(NSNotification *)notification
{
        if(canDeliverNotifications)
        {
                [self flushNotificationEventQueue];
        }

}

-(void) flushNotificationEventQueue
{
        if(jsEventQueue != nil && [jsEventQueue count] > 0)
        {
                for(NSString *notificationEvent in jsEventQueue)
                {
                        [self.commandDelegate evalJs:notificationEvent];
                }

                [jsEventQueue removeAllObjects];
        }
}

- (void) pluginInitialize
{
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didBecomeActive:)
         name:UIApplicationDidBecomeActiveNotification object:nil];

        if(coldstartNotification)
        {
                [self didReceiveRemoteNotificationWithPayload:coldstartNotification];
                coldstartNotification = nil;
        }
}


-(void)successWithMessage:(NSString *)message
{
        CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:message];

        [self.commandDelegate sendPluginResult:commandResult callbackId:self.callbackId];
}

-(void)failWithMessage:(NSString *)message withError:(NSError *)error
{
        NSString        *errorMessage = (error) ?[NSString stringWithFormat:@"%@ - %@", message, [error localizedDescription]] : message;
        CDVPluginResult *commandResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorMessage];

        [self.commandDelegate sendPluginResult:commandResult callbackId:self.callbackId];
}

@end
