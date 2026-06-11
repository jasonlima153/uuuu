#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreServices/CoreServices.h>
#import <objc/message.h>

#pragma mark - Forward Declarations
@interface WKConversationInputPanel : UIView
@end

#pragma mark - 1. 核心控制器：处理文件选择与发送逻辑

@interface UUUVoiceFunManager : NSObject <UIDocumentPickerDelegate>
@property (nonatomic, weak) UIViewController *currentChatVC;
@property (nonatomic, strong) id currentChannel;
+ (instancetype)sharedManager;
- (void)presentAudioPickerFromVC:(UIViewController *)vc channel:(id)channel;
@end

@implementation UUUVoiceFunManager

+ (instancetype)sharedManager {
    static UUUVoiceFunManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[UUUVoiceFunManager alloc] init];
    });
    return instance;
}

- (void)presentAudioPickerFromVC:(UIViewController *)vc channel:(id)channel {
    self.currentChatVC = vc;
    self.currentChannel = channel;

    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[(__bridge NSString *)kUTTypeAudio] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.modalPresentationStyle = UIModalPresentationFormSheet;
    [vc presentViewController:picker animated:YES completion:nil];
}

#pragma mark - UIDocumentPickerDelegate
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *audioURL = urls.firstObject;
    if (!audioURL) return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self processAndSendAudio:audioURL];
    });
}

#pragma mark - 音频处理与发送核心
- (void)processAndSendAudio:(NSURL *)mp3URL {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *wavPath = [tmpDir stringByAppendingPathComponent:@"custom_voice_temp.wav"];
    NSString *amrPath = [tmpDir stringByAppendingPathComponent:@"custom_voice_temp.amr"];

    [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
    [[NSFileManager defaultManager] removeItemAtPath:amrPath error:nil];

    NSError *error = nil;
    AVAudioFile *inputFile = [[AVAudioFile alloc] initForReading:mp3URL error:&error];
    if (error) {
        NSLog(@"[UUUVoiceFun] MP3读取失败: %@", error);
        return;
    }

    AVAudioFormat *outputFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];
    AVAudioFile *outputFile = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:wavPath] settings:outputFormat.settings error:&error];

    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inputFile.processingFormat frameCapacity:(AVAudioFrameCount)inputFile.length];
    [inputFile readIntoBuffer:buffer error:&error];

    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inputFile.processingFormat toFormat:outputFormat];
    AVAudioPCMBuffer *outBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outputFormat frameCapacity:(AVAudioFrameCount)(buffer.frameCapacity * (8000.0 / inputFile.fileFormat.sampleRate))];

    [converter convertToBuffer:outBuffer error:nil withInputFromBlock:^AVAudioBuffer * _Nullable(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus * _Nonnull outStatus) {
        *outStatus = AVAudioConverterInputStatus_HaveData;
        return buffer;
    }];
    [outputFile writeFromBuffer:outBuffer error:&error];

    NSTimeInterval duration = inputFile.length / inputFile.fileFormat.sampleRate;
    NSInteger voiceSecond = MAX(1, MIN((NSInteger)duration, 60));

    Class voiceConverterClass = NSClassFromString(@"VoiceConverter");
    if (voiceConverterClass) {
        int (*EncodeWavToAmr)(id, SEL, NSString*, NSString*, int) = (int (*)(id, SEL, NSString*, NSString*, int))[voiceConverterClass methodForSelector:NSSelectorFromString(@"EncodeWavToAmr:amrSavePath:sampleRateType:")];
        if (EncodeWavToAmr) {
            EncodeWavToAmr(voiceConverterClass, NSSelectorFromString(@"EncodeWavToAmr:amrSavePath:sampleRateType:"), wavPath, amrPath, 0);
            NSLog(@"[UUUVoiceFun] AMR 编码成功!");
        }
    }

    NSMutableData *dummyWaveform = [NSMutableData dataWithCapacity:100];
    for (int i=0; i<100; i++) {
        uint8_t val = arc4random_uniform(50) + 10;
        [dummyWaveform appendBytes:&val length:1];
    }

    NSData *amrData = [NSData dataWithContentsOfFile:amrPath];
    if (amrData && self.currentChannel) {
        dispatch_async(dispatch_get_main_queue(), ^{
            Class voiceContentClass = NSClassFromString(@"WKVoiceContent");
            if (voiceContentClass) {
                id voiceContent = nil;
                // 使用 objc_msgSend 直接调用 initWithData:second:waveform:，避免 performSelector 参数限制
                voiceContent = ((id (*)(id, SEL, id, NSInteger, id))objc_msgSend)([voiceContentClass alloc], NSSelectorFromString(@"initWithData:second:waveform:"), amrData, voiceSecond, dummyWaveform);

                Class sdkClass = NSClassFromString(@"WKSDK");
                id sharedSDK = [sdkClass performSelector:NSSelectorFromString(@"shared")];
                id chatManager = [sharedSDK performSelector:NSSelectorFromString(@"chatManager")];

                if (chatManager && voiceContent) {
                    // 使用 objc_msgSend 直接调用，避免 performSelector 参数限制
                    ((void (*)(id, SEL, id, id))objc_msgSend)(chatManager, NSSelectorFromString(@"sendMessage:channel:"), voiceContent, self.currentChannel);

                    NSLog(@"[UUUVoiceFun] 趣味语音发送成功！时长: %ld秒", (long)voiceSecond);
                }
            }
        });
    }
}

@end

#pragma mark - 2. UI 注入层：在聊天底栏添加"趣味语音"按钮

%group UUUVoiceFunUI

%hook WKConversationInputPanel

- (void)layoutContentView {
    %orig;

    UIView *funcView = [self valueForKey:@"funcGroupView"];
    if (funcView) {
        if ([funcView viewWithTag:999888]) return;

        UIButton *customVoiceBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        customVoiceBtn.tag = 999888;
        customVoiceBtn.backgroundColor = [UIColor colorWithWhite:0.95 alpha:1.0];
        customVoiceBtn.layer.cornerRadius = 16;
        customVoiceBtn.clipsToBounds = YES;

        [customVoiceBtn setTitle:@" \U0001F3B5 趣味语音" forState:UIControlStateNormal];
        [customVoiceBtn setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
        customVoiceBtn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];

        customVoiceBtn.frame = CGRectMake(15, funcView.bounds.size.height - 45, 110, 32);

        [customVoiceBtn addTarget:self action:@selector(onCustomVoiceBtnClicked:) forControlEvents:UIControlEventTouchUpInside];
        [funcView addSubview:customVoiceBtn];
    }
}

%new
- (void)onCustomVoiceBtnClicked:(UIButton *)sender {
    NSLog(@"[UUUVoiceFun] 趣味语音按钮被点击");

    UIViewController *chatVC = nil;
    UIResponder *responder = sender;
    while ((responder = [responder nextResponder])) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            chatVC = (UIViewController *)responder;
            break;
        }
    }

    id channel = nil;
    @try {
        if (chatVC) {
            channel = [chatVC valueForKey:@"channel"];
        }
    } @catch (NSException *e) {
        NSLog(@"[UUUVoiceFun] 获取 channel 失败: %@", e);
    }

    if (chatVC && channel) {
        [[UUUVoiceFunManager sharedManager] presentAudioPickerFromVC:chatVC channel:channel];
    } else {
        NSLog(@"[UUUVoiceFun] 错误：无法获取聊天上下文！");
    }
}

%end

%end

#pragma mark - 3. 插件初始化

static void initVoiceFunUI_once() {
    static BOOL hasInjected = NO;
    if (hasInjected) return;

    if (NSClassFromString(@"WKConversationInputPanel")) {
        NSLog(@"[UUUVoiceFun] 动态激活趣味语音 UI 注入...");
        %init(UUUVoiceFunUI);
        hasInjected = YES;
    }
}

%ctor {
    if (NSClassFromString(@"WKConversationInputPanel")) {
        initVoiceFunUI_once();
    } else {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil
                                                          queue:nil
                                                     usingBlock:^(NSNotification *note) {
            initVoiceFunUI_once();
        }];
    }

    %init;
}
