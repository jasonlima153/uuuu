#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

#pragma mark - 前向声明
@interface WKConversationVC : UIViewController
@end

#pragma mark - 1. 核心接口协议声明 (严格匹配 App 底层)

@protocol UUUTalkCoreProtocols <NSObject>
+ (int)EncodeWavToAmr:(NSString *)wavPath amrSavePath:(NSString *)amrPath sampleRateType:(int)type;
+ (instancetype)initWithData:(NSData *)data second:(NSInteger)second waveform:(NSData *)waveform;
+ (id)shared;
- (id)chatManager;
- (void)sendMessage:(id)msg channel:(id)channel;
@end

#pragma mark - 3. C语言手写标准 WAV 头部 (干掉所有转码炸膛问题)

static BOOL createStandardWav(NSData *pcmData, NSString *savePath) {
    if (!pcmData || pcmData.length == 0) return NO;
    uint32_t dataSize = (uint32_t)pcmData.length;
    NSMutableData *wavData = [NSMutableData data];
    [wavData appendBytes:"RIFF" length:4];
    uint32_t chunkSize = dataSize + 36;
    [wavData appendBytes:&chunkSize length:4];
    [wavData appendBytes:"WAVEfmt " length:8];
    uint32_t subchunk1Size = 16;
    [wavData appendBytes:&subchunk1Size length:4];
    uint16_t audioFormat = 1;
    [wavData appendBytes:&audioFormat length:2];
    uint16_t numChannels = 1;
    [wavData appendBytes:&numChannels length:2];
    uint32_t sampleRate = 8000;
    [wavData appendBytes:&sampleRate length:4];
    uint32_t byteRate = 8000 * 2;
    [wavData appendBytes:&byteRate length:4];
    uint16_t blockAlign = 2;
    [wavData appendBytes:&blockAlign length:2];
    uint16_t bitsPerSample = 16;
    [wavData appendBytes:&bitsPerSample length:2];
    [wavData appendBytes:"data" length:4];
    [wavData appendBytes:&dataSize length:4];
    [wavData appendData:pcmData];
    return [wavData writeToFile:savePath atomically:YES];
}

#pragma mark - 4. 安全投递引擎

static void sendAMRVoiceData(NSData *amrData, NSInteger duration, id channel) {
    if (!amrData || !channel) return;

    // 生成安全防波形崩溃的 NSData
    NSMutableData *dummyWaveform = [NSMutableData dataWithCapacity:100];
    for (int i = 0; i < 60; i++) {
        uint8_t val = (uint8_t)(sin(i * 0.3) * 20 + 30);
        [dummyWaveform appendBytes:&val length:1];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class voiceContentClass = NSClassFromString(@"WKVoiceContent");
            if (voiceContentClass) {
                id<UUUTalkCoreProtocols> voiceContent = [(id<UUUTalkCoreProtocols>)voiceContentClass initWithData:amrData second:duration waveform:dummyWaveform];
                Class sdkClass = NSClassFromString(@"WKSDK");
                id<UUUTalkCoreProtocols> chatManager = [[(id<UUUTalkCoreProtocols>)sdkClass shared] chatManager];

                if (chatManager && voiceContent) {
                    [chatManager sendMessage:voiceContent channel:channel];
                    NSLog(@"[UUUVoiceFun] 🚀 AMR 语音完美转换并发送成功！");
                }
            } else {
                NSLog(@"[UUUVoiceFun] 找不到 WKVoiceContent 类");
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] ❌ 发送异常: %@", e);
        }
    });
}

#pragma mark - 5. 插件主面板 (内置全自动转换引擎)

@interface UUUVoiceFunViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSString *basePath;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"趣味语音 (全自动版)";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入MP3" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 60;
    [self.view addSubview:self.tableView];

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        if ([file.lowercaseString hasSuffix:@".mp3"] || [file.lowercaseString hasSuffix:@".amr"]) {
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
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
#pragma clang diagnostic pop
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *fileURL = urls.firstObject;
    if (!fileURL) return;

    // 【终极防沙盒读写失败】：内存先抽干再落地，脱离 iOS 文件安全锁
    BOOL accessed = [fileURL startAccessingSecurityScopedResource];
    NSData *fileData = [NSData dataWithContentsOfURL:fileURL];
    if (accessed) [fileURL stopAccessingSecurityScopedResource];

    if (fileData && fileData.length > 0) {
        NSString *destPath = [self.basePath stringByAppendingPathComponent:fileURL.lastPathComponent];
        [fileData writeToFile:destPath atomically:YES];
        [self loadVoicePacks];
    } else {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"导入失败" message:@"由于 iOS 文件安全限制，无法读取该音频内容。" preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath { return YES; }
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        [[NSFileManager defaultManager] removeItemAtPath:[self.basePath stringByAppendingPathComponent:self.dataSource[indexPath.row]] error:nil];
        [self.dataSource removeObjectAtIndex:indexPath.row];
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
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
        [sendBtn addTarget:self action:@selector(processAndSendAudioButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
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

// ======================================================================
// 【核心大作】：内置 MP3 -> AMR 全自动转码引擎 (4096帧切片防丢帧)
// ======================================================================
- (void)processAndSendAudioButtonClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.dataSource.count) return;

    NSString *fileName = self.dataSource[row];
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:fileName];

    // UI 加载提示
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"处理中"
        message:@"正在提取并转码发送语音..."
        preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        __block NSData *finalAmrData = nil;
        __block NSInteger audioDuration = 1;

        if ([fileName.lowercaseString hasSuffix:@".mp3"]) {
            @try {
                @autoreleasepool {
                    NSURL *inURL = [NSURL fileURLWithPath:fullPath];
                    AVAudioFile *inFile = [[AVAudioFile alloc] initForReading:inURL error:nil];

                    if (inFile && inFile.fileFormat.sampleRate > 0) {
                        AVAudioFormat *outFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];
                        AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inFile.processingFormat toFormat:outFormat];

                        // 【4096帧切片循环转换】防止 AVAudioConverter 内存超载丢帧（花栗鼠快进声）
                        NSMutableData *fullPcmData = [NSMutableData data];
                        AVAudioFrameCount chunkSize = 4096;
                        AVAudioPCMBuffer *inBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inFile.processingFormat frameCapacity:chunkSize];
                        AVAudioPCMBuffer *outBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outFormat frameCapacity:chunkSize];

                        while (inFile.framePosition < inFile.length && (inFile.framePosition / inFile.fileFormat.sampleRate) < 60.0) {
                            NSError *err = nil;
                            [inFile readIntoBuffer:inBuf frameCount:chunkSize error:&err];
                            if (err || inBuf.frameLength == 0) break;

                            __block BOOL consumed = NO;
                            [converter convertToBuffer:outBuf error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount p, AVAudioConverterInputStatus *outStatus) {
                                if (consumed) { *outStatus = AVAudioConverterInputStatus_EndOfStream; return nil; }
                                consumed = YES;
                                *outStatus = AVAudioConverterInputStatus_HaveData;
                                return inBuf;
                            }];

                            if (outBuf.frameLength > 0) {
                                [fullPcmData appendBytes:outBuf.int16ChannelData[0] length:outBuf.frameLength * 2];
                            }
                        }

                        audioDuration = MAX(1, MIN((NSInteger)(inFile.length / inFile.fileFormat.sampleRate), 60));

                        NSString *tmpWavPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"inner_convert.wav"];
                        NSString *tmpAmrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"inner_convert.amr"];
                        [[NSFileManager defaultManager] removeItemAtPath:tmpWavPath error:nil];
                        [[NSFileManager defaultManager] removeItemAtPath:tmpAmrPath error:nil];

                        // 挂载手写的标准 44 字节头部
                        BOOL wavSuccess = createStandardWav(fullPcmData, tmpWavPath);
                        if (wavSuccess) {
                            Class converterCls = NSClassFromString(@"VoiceConverter");
                            if (converterCls) {
                                [(id<UUUTalkCoreProtocols>)converterCls EncodeWavToAmr:tmpWavPath amrSavePath:tmpAmrPath sampleRateType:0];
                                finalAmrData = [NSData dataWithContentsOfFile:tmpAmrPath];
                            }
                        }

                        [[NSFileManager defaultManager] removeItemAtPath:tmpWavPath error:nil];
                        [[NSFileManager defaultManager] removeItemAtPath:tmpAmrPath error:nil];
                    }
                }
            } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] MP3内置转码异常: %@", e); }
        } else {
            // 原生 AMR 直接读
            finalAmrData = [NSData dataWithContentsOfFile:fullPath];
            audioDuration = MAX(1, MIN(finalAmrData.length / 1600, 60));
        }

        // 切回主线程处理 UI 和发送
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingAlert dismissViewControllerAnimated:YES completion:^{
                // 转出的 AMR 只有几十字节说明转码失败，拦截防止看门狗死机
                if (finalAmrData && finalAmrData.length > 50) {
                    sendAMRVoiceData(finalAmrData, audioDuration, self.currentChannel);
                    [self close];
                } else {
                    UIAlertController *err = [UIAlertController alertControllerWithTitle:@"转码失败"
                        message:@"该 MP3 内部格式受损，内置转码器无法完成转换！"
                        preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
                    [self presentViewController:err animated:YES completion:nil];
                }
            }];
        });
    });
}
@end

#pragma mark - 6. 悬浮窗安全挂载层

%group UUUVoiceFunHooks

%hook WKConversationVC

- (void)viewDidLoad {
    %orig;
    if ([self.view viewWithTag:888999]) return; // 按钮去重

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
    if ([self respondsToSelector:channelSel]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id channel = [self performSelector:channelSel];
        #pragma clang diagnostic pop
        if (channel) {
            UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
            vc.currentChannel = channel;
            UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
            nav.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:nav animated:YES completion:nil];
        }
    }
}

%end

%end

#pragma mark - 7. 模块初始化

%ctor {
    if (NSClassFromString(@"WKConversationVC")) {
        %init(UUUVoiceFunHooks);
    }
}
