//
//  LRSpeakHelper.m
//  liveroom
//
//  Created by 杜洁鹏 on 2019/4/11.
//  Copyright © 2019 Easemob. All rights reserved.
//

#import "Headers.h"
#import "LRSpeakHelper.h"
#import "LRGCDMulticastDelegate.h"
#import "LRRoomModel.h"

#define kKeepHandleTime 30

@interface LRSpeakHelper () <EMConferenceManagerDelegate>
{
    LRGCDMulticastDelegate <LRSpeakHelperDelegate> *_delegates;
    NSString *_currentMonopolyTalker;
    int _time;
}

@property (nonatomic, strong) NSString *pubStreamId;
@property (nonatomic, strong) NSTimer *monopolyTimer;

@end

@implementation LRSpeakHelper
+ (LRSpeakHelper *)sharedInstance {
    static dispatch_once_t onceToken;
    static LRSpeakHelper *helper_;
    dispatch_once(&onceToken, ^{
        helper_ = [[LRSpeakHelper alloc] init];
    });
    return helper_;
}

- (instancetype)init {
    if (self = [super init]) {
        _delegates = (LRGCDMulticastDelegate<LRSpeakHelperDelegate> *)[[LRGCDMulticastDelegate alloc] init];
        [EMClient.sharedClient.conferenceManager addDelegate:self delegateQueue:nil];
        
        [NSNotificationCenter.defaultCenter addObserver:self
                                               selector:@selector(agreedToBeAudience:)
                                                   name:LR_Receive_ToBe_Audience_Notification
                                                 object:nil];
    }
    return self;
}

- (void)addDeelgate:(id<LRSpeakHelperDelegate>)aDelegate delegateQueue:(dispatch_queue_t)aQueue {
    if (!aQueue) {
        aQueue = dispatch_get_main_queue();
    }
    [_delegates addDelegate:aDelegate delegateQueue:aQueue];
}

- (void)removeDelegate:(id<LRSpeakHelperDelegate>)aDelegate {
    [_delegates removeDelegate:aDelegate];
}

// 加入语音会议
- (void)joinSpeakRoomWithRoomId:(NSString *)aRoomId
                       password:(NSString *)aPassword
                     completion:(void(^)(NSString *errorInfo, BOOL success))aCompletion {
    __weak typeof(self) weakSelf = self;
    [EMClient.sharedClient.conferenceManager joinConferenceWithConfId:aRoomId
                                                             password:aPassword
                                                           completion:^(EMCallConference *aCall, EMError *aError)
    {
        if (!aError) {
            weakSelf.conference = aCall;
            [EMClient.sharedClient.conferenceManager startMonitorSpeaker:weakSelf.conference
                                                            timeInterval:1500
                                                              completion:^(EMError *aError)
            {
                
            }];
        }
        if (aCompletion) {
            aCompletion(aError.errorDescription, !aError);
        }
    }];
}

// 离开语音会议
- (void)leaveSpeakRoomWithRoomId:(NSString *)aRoomId
                      completion:(void(^)(NSString *errorInfo, BOOL success))aCompletion {
    [EMClient.sharedClient.conferenceManager leaveConference:self.conference
                                                  completion:^(EMError *aError)
    {
        if (aCompletion) {
            aCompletion(aError.errorDescription, !aError);
        }
    }];
}


// 设置房间属性
- (void)setupRoomType:(LRRoomType)aType {
    NSString *value;
    switch (aType) {
        case LRRoomType_Communication:
        {
            value = @"communication";
        }
            break;
        case LRRoomType_Host:
        {
            value = @"host";
        }
            break;
        case LRRoomType_Monopoly:
        {
            value = @"monopoly";
        }
            break;
        default:
            break;
    }
    if (value) {
        [EMClient.sharedClient.conferenceManager addAndUpdateConferenceAttribute:@"type"
                                                                           value:value
                                                                      completion:^(EMError * _Nullable saError)
         {
             
         }];
    }
}

// 发布自己的流，并更新ui
- (void)setupMySelfToSpeaker {
    __weak typeof(self) weakSekf = self;
    EMStreamParam *param = [[EMStreamParam alloc] init];
    param.streamName = kCurrentUsername;
    param.enableVideo = NO;
    param.isMute = YES;
    [EMClient.sharedClient.conferenceManager publishConference:self.conference
                                                   streamParam:param
                                                    completion:^(NSString *aPubStreamId, EMError *aError)
     {
         if(!aError) {
             weakSekf.pubStreamId = aPubStreamId;
             [self->_delegates receiveSomeoneOnSpeaker:kCurrentUsername streamId:aPubStreamId mute:YES];
         }
    }];
}

// 停止发布自己的流，并更新ui
- (void)setupMySelfToAudiance {
    [EMClient.sharedClient.conferenceManager
     unpublishConference:self.conference
     streamId:self.pubStreamId
     completion:^(EMError *aError) {
        
    }];
    [_delegates receiveSomeoneOffSpeaker:kCurrentUsername];
}


#pragma mark - admin
// 设置用户为主播
- (void)setupUserToSpeaker:(NSString *)aUsername {
    NSString *applyUid = [[EMClient sharedClient].conferenceManager getMemberNameWithAppkey:[EMClient sharedClient].options.appkey username:aUsername];
    
    [EMClient.sharedClient.conferenceManager
     changeMemberRoleWithConfId:self.conference.confId
     memberNames:@[applyUid] role:EMConferenceRoleSpeaker
     completion:^(EMError *aError) {
         
     }];
}

// 设置用户为听众
- (void)setupUserToAudiance:(NSString *)aUsername {
    NSString *applyUid = [[EMClient sharedClient].conferenceManager getMemberNameWithAppkey:[EMClient sharedClient].options.appkey username:aUsername];
    
    [EMClient.sharedClient.conferenceManager
     changeMemberRoleWithConfId:self.conference.confId
     memberNames:@[applyUid]
     role:EMConferenceRoleAudience
     completion:^(EMError *aError) {
         
     }];
}

// 拒绝用户上麦申请
- (void)forbidUserOnSpeaker:(NSString *)aUsername {
    EMCmdMessageBody *body = [[EMCmdMessageBody alloc] initWithAction:@""];
    EMMessage *msg = [[EMMessage alloc] initWithConversationID:aUsername
                                                          from:kCurrentUsername
                                                            to:aUsername
                                                          body:body
                                                           ext:@{kRequestKey:kRequestToBe_Rejected}];
    msg.chatType =  EMChatTypeChat;
    [EMClient.sharedClient.chatManager sendMessage:msg progress:nil completion:nil];
}

- (void)setupSpeakerMicOn:(NSString *)aUsername {
    [EMClient.sharedClient.conferenceManager addAndUpdateConferenceAttribute:@"talker"
                                                                       value:aUsername
                                                                  completion:nil];
}

- (void)setupSpeakerMicOff:(NSString *)aUsername {
    if (!self.roomModel) {
        return;
    }
    [EMClient.sharedClient.conferenceManager addAndUpdateConferenceAttribute:@"talker"
                                                                       value:@""
                                                                  completion:nil];
}

#pragma mark - user
// 申请上麦
- (void)requestOnSpeaker:(LRRoomModel *)aRoom
            completion:(void(^)(NSString *errorInfo, BOOL success))aCompletion {
    
    if (self.conference.role == EMConferenceRoleSpeaker) {
        [self roleDidChanged:self.conference];
        return;
    }
    
    EMCmdMessageBody *body = [[EMCmdMessageBody alloc] initWithAction:@""];
    EMMessage *msg = [[EMMessage alloc] initWithConversationID:aRoom.owner
                                                          from:kCurrentUsername
                                                            to:aRoom.owner
                                                          body:body
                                                           ext:@{kRequestKey:kRequestToBe_Speaker}];
    
    msg.chatType = EMChatTypeChat;
    [EMClient.sharedClient.chatManager sendMessage:msg progress:nil completion:^(EMMessage *message, EMError *error) {
        if (aCompletion) {
            if (!error) {aCompletion(nil, YES); return ;}
            aCompletion(error.errorDescription, NO);
        }
    }];
}

// 申请下麦
- (void)requestOffSpeaker:(LRRoomModel *)aRoom
             completion:(void(^)(NSString *errorInfo, BOOL success))aCompletion {
    EMCmdMessageBody *body = [[EMCmdMessageBody alloc] initWithAction:@""];
    EMMessage *msg = [[EMMessage alloc] initWithConversationID:aRoom.owner
                                                          from:kCurrentUsername
                                                            to:aRoom.owner
                                                          body:body
                                                           ext:@{kRequestKey:kRequestToBe_Audience}];
    
    msg.chatType = EMChatTypeChat;
    [EMClient.sharedClient.chatManager sendMessage:msg progress:nil completion:^(EMMessage *message, EMError *error) {
        if (aCompletion) {
            if (!error) {aCompletion(nil, YES); return ;}
            aCompletion(error.errorDescription, NO);
        }
    }];
}

// 是否静音自己
- (void)muteMyself:(BOOL)isMute {
    [_delegates receiveSpeakerMute:kCurrentUsername mute:isMute];
    [EMClient.sharedClient.conferenceManager updateConference:self.conference isMute:isMute];
}

#pragma mark - argument mic
// 抢麦
- (void)argumentMic:(NSString *)aRoomId
         completion:(void(^)(NSString *errorInfo, BOOL success))aComplstion {
    NSString *url = [NSString stringWithFormat:@"http://turn2.easemob.com:8082/app/mic/%@/%@", aRoomId,kCurrentUsername];;
    __block BOOL success = NO;
    [LRRequestManager.sharedInstance requestWithMethod:@"GET"
                                             urlString:url
                                            parameters:nil
                                                 token:nil
                                            completion:^(NSDictionary * _Nonnull result, NSError * _Nonnull error)
     {
         success = [result[@"status"] boolValue];
         if (aComplstion) {
             dispatch_async(dispatch_get_main_queue(), ^{
                 if (!error) {
                     aComplstion(nil, success);
                 }else {
                     aComplstion(nil, success);
                 }
             });
         }
     }];
}

// 释放麦
- (void)unArgumentMic:(NSString *)aRoomId
           completion:(void(^)(NSString *errorInfo, BOOL success))aComplstion {
    NSString *url = [NSString stringWithFormat:@"http://turn2.easemob.com:8082/app/discardmic/%@/%@", aRoomId,kCurrentUsername];;
    [LRRequestManager.sharedInstance requestWithMethod:@"DELETE"
                                             urlString:url
                                            parameters:nil
                                                 token:nil
                                            completion:^(NSDictionary * _Nonnull result, NSError * _Nonnull error)
     {
         dispatch_async(dispatch_get_main_queue(), ^{
             if (!error) {
                 if (aComplstion) {
                     aComplstion(nil, YES);
                 }
             }else {
                 if (aComplstion) {
                     aComplstion(nil, NO);
                 }
             }
         });
     }];
}

#pragma mark - Monopoly Timer
- (void)updateMonopolyTimer {
    _time--;
    if (_time == 0) {
        [self stopMonopolyTimer];
        // 只有自己持有麦的时候才能释放麦
        if ([_currentMonopolyTalker isEqualToString:kCurrentUsername]) {
            [self setupSpeakerMicOff:kCurrentUsername];
        }
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:LR_Remain_Speaking_timer_Notification object:@{@"currentSpeakingUsername":_currentMonopolyTalker,@"remainSpeakingTime":[NSNumber numberWithInt:_time]}];
}

// 启动倒计时
- (void)startMonopolyTimer {
    [self stopMonopolyTimer];
    _time = kKeepHandleTime;
    _monopolyTimer = [NSTimer timerWithTimeInterval:1
                                             target:self
                                           selector:@selector(updateMonopolyTimer)
                                           userInfo:nil
                                            repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:_monopolyTimer forMode:NSRunLoopCommonModes];
    [_monopolyTimer fire];
}

- (void)stopMonopolyTimer {
    if (_monopolyTimer) {
        [_monopolyTimer invalidate];
        _monopolyTimer = nil;
        NSLog(@"_currentMonopolyTalker----%@", _currentMonopolyTalker);
        [[NSNotificationCenter defaultCenter] postNotificationName:LR_Un_Argument_Speaker_Notification object:_currentMonopolyTalker];
    }
}


#pragma mark - EMConferenceManagerDelegate

// 收到新的流发布，直接关注
- (void)streamDidUpdate:(EMCallConference *)aConference
              addStream:(EMCallStream *)aStream {
    // 判断是否是当前的Conference
    if (![aConference.confId isEqualToString:self.conference.confId]) {
        return;
    }
    
    [EMClient.sharedClient.conferenceManager subscribeConference:aConference
                                                        streamId:aStream.streamId
                                                 remoteVideoView:nil
                                                      completion:^(EMError *aError) {
                                                          
                                                      }];
    
    [_delegates receiveSomeoneOnSpeaker:aStream.userName
                               streamId:aStream.streamId
                                   mute:!aStream.enableVoice];
}

// 收到流被移除，取消关注
- (void)streamDidUpdate:(EMCallConference *)aConference
           removeStream:(EMCallStream *)aStream {
    
    // 判断是否是当前的Conference
    if (![aConference.confId isEqualToString:aConference.confId]) {
        return;
    }
    
    [EMClient.sharedClient.conferenceManager unsubscribeConference:aConference
                                                          streamId:aStream.streamId
                                                        completion:nil];
    
    [_delegates receiveSomeoneOffSpeaker:aStream.userName];
}

// 收到流数据更新（这个项目里只有mute的操作），上报到上层
- (void)streamDidUpdate:(EMCallConference *)aConference stream:(EMCallStream *)aStream {
    // 判断是否是当前的Conference
    if (![aConference.confId isEqualToString:aConference.confId]) {
        return;
    }
    [_delegates receiveSpeakerMute:aStream.userName mute:!aStream.enableVoice];
}

// 管理员允许你上麦后会收到该回调
- (void)roleDidChanged:(EMCallConference *)aConference {
    if (aConference.role == EMConferenceRoleSpeaker) // 被设置为主播
    {
        [self setupMySelfToSpeaker];
        [NSNotificationCenter.defaultCenter postNotificationName:LR_UI_ChangeRoleToSpeaker_Notification
                                                          object:nil];
    }
    else if (aConference.role == EMConferenceRoleAudience) // 被设置为观众
    {
        [self setupMySelfToAudiance];
        [NSNotificationCenter.defaultCenter postNotificationName:LR_UI_ChangeRoleToAudience_Notification
                                                          object:nil];
        if ([_currentMonopolyTalker isEqualToString:kCurrentUsername]) {
            [self unArgumentMic:self.roomModel.roomId
                     completion:^(NSString * _Nonnull errorInfo, BOOL success)
             {
                 [self setupSpeakerMicOff:kCurrentUsername];
             }];
        }
    }
}

// 监听用户说话
- (void)conferenceSpeakerDidChange:(EMCallConference *)aConference
                 speakingStreamIds:(NSArray *)aStreamIds {
    [NSNotificationCenter.defaultCenter postNotificationName:LR_Stream_Did_Speaking_Notification
                                                      object:aStreamIds];
    NSLog(@"aStreamIds------%@", aStreamIds);
}

- (void)conferenceAttributesChanged:(EMCallConference *)aConference attributeAction:(EMConferenceAttributeAction)aAction
                       attributeKey:(NSString *)attrKey
                     attributeValue:(NSString *)attrValue {
    if ([attrKey isEqualToString:@"type"]) {
        if ([attrValue isEqualToString:@"communication"]) {
            self.roomModel.roomType = LRRoomType_Communication;
        }
        if ([attrValue isEqualToString:@"host"]) {
            self.roomModel.roomType = LRRoomType_Host;
        }
        if ([attrValue isEqualToString:@"monopoly"]) {
            self.roomModel.roomType = LRRoomType_Monopoly;
        }
        
        [_delegates roomTypeDidChange:self.roomModel.roomType];
    }
    
    if ([attrKey isEqualToString:@"talker"]) {
        if (self.roomModel.roomType == LRRoomType_Host) {
            [_delegates currentHostTypeSpeakerChanged:attrValue];
        }
        
        if (self.roomModel.roomType == LRRoomType_Monopoly) {
            _currentMonopolyTalker = attrValue;
            if ([attrValue isEqualToString:@""]) {
                [self stopMonopolyTimer];
            }else {
                [self startMonopolyTimer];
            }
            [_delegates currentMonopolyTypeSpeakerChanged:attrValue];
        }
    }
}

// 自动同意下麦申请
- (void)agreedToBeAudience:(NSNotification *)aNoti  {
    NSString *username = aNoti.object;
    if (username && [username isKindOfClass:[NSString class]]) {
        [self setupUserToAudiance:username];
    }
}

#pragma mark - getter
- (NSString *)adminId {
    return self.conference.adminIds.firstObject;
}

@end
