#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

#pragma mark - Forward Declarations
@interface WKConversationVC : UIViewController
@end

#pragma mark - 1. 运行时方法扫描器 (Runtime Scanner)

static void dumpMethodsForClass(Class cls, BOOL isClassMethod) {
    if (!cls) return;
    unsigned int count = 0;
    Method *methods = class_copyMethodList(isClassMethod ? object_getClass(cls) : cls, &count);
    NSMutableString *logStr = [NSMutableString stringWithFormat:@"\n[%@] 真实%@方法列表 (%d个):\n",
        NSStringFromClass(cls), isClassMethod ? @"类(+)" : @"实例(-)", count];
    for (int i = 0; i < count; i++) {
        SEL sel = method_getName(methods[i]);
        [logStr appendFormat:@"  %@ %s\n", isClassMethod ? @"+" : @"-", sel_getName(sel)];
    }
    free(methods);
    NSLog(@"%@", logStr);
}

#pragma mark - 2. 核心发送引擎 (全链路运行时自检)

static void verifyAndSendVoice(NSData *amrData, NSInteger duration, id channel) {
    if (!amrData || !channel) {
        NSLog(@"[UUUVoiceFun] ❌ 拦截：amrData 或 channel 为空");
        return;
    }
    NSLog(@"[UUUVoiceFun] Channel 真实类型: %@", NSStringFromClass([channel class]));

    NSMutableData *dummyWaveform = [NSMutableData dataWithCapacity:100];
    for (int i = 0; i < 100; i++) {
        uint8_t val = (uint8_t)(sin(i * 0.2) * 20 + 30 + arc4random_uniform(10));
        [dummyWaveform appendBytes:&val length:1];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            // === 验证 1: WKVoiceContent ===
            Class voiceContentCls = NSClassFromString(@"WKVoiceContent");
            if (!voiceContentCls) {
                NSLog(@"[UUUVoiceFun] ❌ 找不到 WKVoiceContent 类");
                return;
            }

            SEL initSel = NSSelectorFromString(@"initWithData:second:waveform:");
            id voiceContent = nil;

            if ([voiceContentCls respondsToSelector:initSel]) {
                NSLog(@"[UUUVoiceFun] ✅ +[WKVoiceContent initWithData:second:waveform:] 存在");
                // 类方法：用 NSInvocation 正确处理 NSInteger 参数
                NSMethodSignature *sig = [voiceContentCls methodSignatureForSelector:initSel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:voiceContentCls];
                [inv setSelector:initSel];
                [inv setArgument:&amrData atIndex:2];
                [inv setArgument:&duration atIndex:3];
                [inv setArgument:&dummyWaveform atIndex:4];
                [inv invoke];
                __unsafe_unretained id ret = nil;
                [inv getReturnValue:&ret];
                voiceContent = ret;
            } else if ([voiceContentCls instancesRespondToSelector:initSel]) {
                NSLog(@"[UUUVoiceFun] ✅ -[WKVoiceContent initWithData:second:waveform:] 存在");
                id instance = [voiceContentCls alloc];
                NSMethodSignature *sig = [instance methodSignatureForSelector:initSel];
                NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                [inv setTarget:instance];
                [inv setSelector:initSel];
                [inv setArgument:&amrData atIndex:2];
                [inv setArgument:&duration atIndex:3];
                [inv setArgument:&dummyWaveform atIndex:4];
                [inv invoke];
                __unsafe_unretained id ret = nil;
                [inv getReturnValue:&ret];
                voiceContent = ret;
            } else {
                NSLog(@"[UUUVoiceFun] ❌ initWithData:second:waveform: 不存在！扫描全量方法...");
                dumpMethodsForClass(voiceContentCls, YES);
                dumpMethodsForClass(voiceContentCls, NO);
                return;
            }

            if (!voiceContent) {
                NSLog(@"[UUUVoiceFun] ❌ voiceContent 实例化失败");
                return;
            }
            NSLog(@"[UUUVoiceFun] ✅ voiceContent 创建成功，类型: %@", NSStringFromClass([voiceContent class]));

            // === 验证 2: WKSDK -> chatManager ===
            Class sdkClass = NSClassFromString(@"WKSDK");
            if (![sdkClass respondsToSelector:@selector(shared)]) {
                NSLog(@"[UUUVoiceFun] ❌ WKSDK 没有 shared 方法");
                return;
            }
            id sharedSDK = [sdkClass performSelector:@selector(shared)];
            if (![sharedSDK respondsToSelector:@selector(chatManager)]) {
                NSLog(@"[UUUVoiceFun] ❌ sharedSDK 没有 chatManager 方法");
                return;
            }
            id chatManager = [sharedSDK performSelector:@selector(chatManager)];
            NSLog(@"[UUUVoiceFun] ✅ chatManager 获取成功，类型: %@", NSStringFromClass([chatManager class]));

            // === 验证 3: sendMessage:channel: ===
            SEL sendSel = NSSelectorFromString(@"sendMessage:channel:");
            if (![chatManager respondsToSelector:sendSel]) {
                NSLog(@"[UUUVoiceFun] ❌ chatManager 没有 sendMessage:channel:！扫描全量方法...");
                dumpMethodsForClass([chatManager class], NO);
                return;
            }

            NSLog(@"[UUUVoiceFun] ✅ 全链路验证通过，准备发送");
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [chatManager performSelector:sendSel withObject:voiceContent withObject:channel];
            #pragma clang diagnostic pop
            NSLog(@"[UUUVoiceFun] 🚀 发送指令已安全投递！");

        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] ❌ 异常拦截: %@", e);
        }
    });
}

#pragma mark - 3. 趣味语音主面板 (自检版)

@interface UUUVoiceFunViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSString *basePath;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"趣味语音 (自检版)";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入MP3" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 55;
    [self.view addSubview:self.tableView];

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        if ([file hasSuffix:@".mp3"] || [file hasSuffix:@".amr"]) {
            [self.dataSource addObject:file];
        }
    }
    [self.tableView reloadData];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)importVoice {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio"] inMode:UIDocumentPickerModeImport];
    #pragma clang diagnostic pop
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    if (!urls.firstObject) return;
    NSString *destPath = [self.basePath stringByAppendingPathComponent:urls.firstObject.lastPathComponent];
    [[NSFileManager defaultManager] copyItemAtURL:urls.firstObject toURL:[NSURL fileURLWithPath:destPath] error:nil];
    [self loadVoicePacks];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.dataSource.count; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MainCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"MainCell"];
        UIButton *sendBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [sendBtn setTitle:@"发送" forState:UIControlStateNormal];
        sendBtn.backgroundColor = [UIColor colorWithRed:0.24 green:0.52 blue:0.98 alpha:1.0];
        [sendBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        sendBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        sendBtn.layer.cornerRadius = 14;
        sendBtn.frame = CGRectMake(0, 0, 56, 28);
        [sendBtn addTarget:self action:@selector(mp3SendButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = sendBtn;
    }

    cell.textLabel.text = self.dataSource[indexPath.row];
    cell.imageView.image = [UIImage systemImageNamed:@"music.note"];
    ((UIButton *)cell.accessoryView).tag = indexPath.row;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)mp3SendButtonClicked:(UIButton *)sender {
    if (sender.tag >= self.dataSource.count) return;
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:self.dataSource[sender.tag]];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self safeConvertAndSendAudio:fullPath];
    });
}

- (void)safeConvertAndSendAudio:(NSString *)filePath {
    __block NSData *amrData = nil;
    __block NSInteger duration = 1;

    if ([filePath hasSuffix:@".mp3"]) {
        NSString *wavPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"safe_out.wav"];
        NSString *amrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"safe_out.amr"];
        [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:amrPath error:nil];

        @try {
            AVAudioFile *inFile = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:filePath] error:nil];
            if (inFile && inFile.fileFormat.sampleRate > 0) {
                AVAudioFormat *outFmt = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];
                AVAudioFile *outFile = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:wavPath] settings:outFmt.settings error:nil];

                AVAudioFrameCount fToRead = (AVAudioFrameCount)MIN(inFile.length, inFile.fileFormat.sampleRate * 60.0);
                if (fToRead > 0) {
                    AVAudioPCMBuffer *inBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inFile.processingFormat frameCapacity:fToRead];
                    [inFile readIntoBuffer:inBuf frameCount:fToRead error:nil];

                    AVAudioConverter *cv = [[AVAudioConverter alloc] initFromFormat:inBuf.format toFormat:outFmt];
                    if (cv) {
                        AVAudioFrameCount outCap = (AVAudioFrameCount)(fToRead * (8000.0 / inFile.fileFormat.sampleRate));
                        AVAudioPCMBuffer *outBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outFmt frameCapacity:MAX(100, outCap)];

                        __block BOOL given = NO;
                        [cv convertToBuffer:outBuf error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount p, AVAudioConverterInputStatus *s) {
                            if (given) { *s = AVAudioConverterInputStatus_EndOfStream; return nil; }
                            given = YES; *s = AVAudioConverterInputStatus_HaveData; return inBuf;
                        }];
                        [outFile writeFromBuffer:outBuf error:nil];
                        duration = MAX(1, MIN((NSInteger)(fToRead / inFile.fileFormat.sampleRate), 60));
                    }
                }

                inFile = nil;
                outFile = nil;

                // 验证 VoiceConverter
                Class converterCls = NSClassFromString(@"VoiceConverter");
                SEL encSel = NSSelectorFromString(@"EncodeWavToAmr:amrSavePath:sampleRateType:");
                if ([converterCls respondsToSelector:encSel]) {
                    NSLog(@"[UUUVoiceFun] ✅ +[VoiceConverter EncodeWavToAmr...] 验证通过");
                    NSMethodSignature *sig = [converterCls methodSignatureForSelector:encSel];
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:converterCls];
                    [inv setSelector:encSel];
                    [inv setArgument:&wavPath atIndex:2];
                    [inv setArgument:&amrPath atIndex:3];
                    int type = 0;
                    [inv setArgument:&type atIndex:4];
                    [inv invoke];
                    amrData = [NSData dataWithContentsOfFile:amrPath];
                } else {
                    NSLog(@"[UUUVoiceFun] ❌ EncodeWavToAmr 不存在！扫描 VoiceConverter...");
                    dumpMethodsForClass(converterCls, YES);
                }
            }
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] MP3转码异常: %@", e); }
    } else {
        amrData = [NSData dataWithContentsOfFile:filePath];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (amrData) {
            verifyAndSendVoice(amrData, duration, self.currentChannel);
            [self close];
        } else {
            NSLog(@"[UUUVoiceFun] ❌ 音频解析失败");
        }
    });
}
@end

#pragma mark - 4. Hook: WKConversationVC (带 channel 安全校验)

%group UUUVoiceFunHooks

%hook WKConversationVC

- (void)viewDidLoad {
    %orig;

    if ([self.view viewWithTag:888999]) return;

    UIButton *floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
    floatBtn.tag = 888999;
    floatBtn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 65, 260, 48, 48);
    floatBtn.backgroundColor = [UIColor colorWithRed:0.24 green:0.52 blue:0.98 alpha:0.9];
    floatBtn.layer.cornerRadius = 24;
    floatBtn.layer.shadowColor = [UIColor blackColor].CGColor;
    floatBtn.layer.shadowOpacity = 0.3;
    floatBtn.layer.shadowOffset = CGSizeMake(0, 2);
    [floatBtn setTitle:@"\U0001F3B5" forState:UIControlStateNormal];
    floatBtn.titleLabel.font = [UIFont systemFontOfSize:22];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(uuu_handlePan:)];
    [floatBtn addGestureRecognizer:pan];
    [floatBtn addTarget:self action:@selector(uuu_openVoicePanel) forControlEvents:UIControlEventTouchUpInside];

    [self.view addSubview:floatBtn];
}

- (void)viewWillLayoutSubviews {
    %orig;
    UIView *btn = [self.view viewWithTag:888999];
    if (btn) [self.view bringSubviewToFront:btn];
}

%new
- (void)uuu_handlePan:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    CGPoint translation = [pan translationInView:btn.superview];
    CGPoint newCenter = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    newCenter.x = MAX(24, MIN(newCenter.x, [UIScreen mainScreen].bounds.size.width - 24));
    newCenter.y = MAX(100, MIN(newCenter.y, [UIScreen mainScreen].bounds.size.height - 100));
    btn.center = newCenter;
    [pan setTranslation:CGPointZero inView:btn.superview];
}

%new
- (void)uuu_openVoicePanel {
    SEL channelSel = NSSelectorFromString(@"channel");
    if (![self respondsToSelector:channelSel]) {
        NSLog(@"[UUUVoiceFun] ❌ WKConversationVC 没有 channel 方法！扫描...");
        dumpMethodsForClass([self class], NO);
        return;
    }

    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id channel = [self performSelector:channelSel];
    #pragma clang diagnostic pop

    if (channel) {
        NSLog(@"[UUUVoiceFun] ✅ channel 获取成功，类型: %@", NSStringFromClass([channel class]));
        UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
        vc.currentChannel = channel;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self presentViewController:nav animated:YES completion:nil];
    } else {
        NSLog(@"[UUUVoiceFun] ❌ channel 返回 nil");
    }
}

%end

%end

#pragma mark - 5. 模块初始化

%ctor {
    if (NSClassFromString(@"WKConversationVC")) {
        %init(UUUVoiceFunHooks);
    }
}
