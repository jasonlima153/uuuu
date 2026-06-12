#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// ==========================================
// 1. 核心接口协议声明
// ==========================================
@protocol UUUTalkCoreProtocols <NSObject>
+ (int)EncodeWavToAmr:(NSString *)wavPath amrSavePath:(NSString *)amrPath sampleRateType:(int)type;
+ (int)DecodeAmrToWav:(NSString *)amrPath wavSavePath:(NSString *)wavPath sampleRateType:(int)type;
+ (instancetype)initWithData:(NSData *)data second:(NSInteger)second waveform:(NSData *)waveform;
+ (id)shared;
- (id)chatManager;
- (void)sendMessage:(id)msg channel:(id)channel;
@end

#pragma mark - 2. C语言手工提纯 WAV 头部
static BOOL createPureWav(NSData *pcmData, NSString *savePath) {
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

#pragma mark - 3. 安全直发引擎 (0 计算，直接抛给服务器)

static void sendAMRVoiceData(NSData *amrData, NSInteger duration, id channel) {
    if (!amrData || !channel) return;

    // 生成假波形防止 UI 崩溃
    NSMutableData *dummyWaveform = [NSMutableData dataWithCapacity:100];
    for (int i = 0; i < 100; i++) {
        uint8_t val = (uint8_t)(sin(i * 0.2) * 20 + 30 + arc4random_uniform(10));
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
                    NSLog(@"[UUUVoiceFun] 🚀 语音安全投递成功！");
                }
            }
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] ❌ 发送异常: %@", e); }
    });
}

#pragma mark - 4. 插件主面板 (内置前置转码与 AMR 直导)

@interface UUUVoiceFunViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSString *basePath;
@property (nonatomic, strong) id currentChannel;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@end

@implementation UUUVoiceFunViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"趣味语音包 (AMR 专版)";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入(MP3/AMR)" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 60;
    [self.view addSubview:self.tableView];

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        // 现在列表里只会有 AMR 文件，绝对纯粹！
        if ([file.lowercaseString hasSuffix:@".amr"]) {
            [self.dataSource addObject:file];
        }
    }
    [self.tableView reloadData];
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

- (void)importVoice {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.audio", @"public.item"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
#pragma clang diagnostic pop
}

// ======================================================================
// 【核心功能 1】：前置转码引擎！导入瞬间进行转码提纯，不留后患
// ======================================================================
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *fileURL = urls.firstObject;
    if (!fileURL) return;

    BOOL accessed = [fileURL startAccessingSecurityScopedResource];
    NSString *ext = fileURL.pathExtension.lowercaseString;
    NSString *fileName = [[fileURL lastPathComponent] stringByDeletingPathExtension];

    if ([ext isEqualToString:@"mp3"]) {
        // 如果是 MP3，立刻进行后台静默转码，存为 AMR
        UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"正在转换" message:@"正在将 MP3 净化并转换为 AMR 格式..." preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:loading animated:YES completion:nil];

        // 避开系统沙盒封锁，先把文件拷到缓存
        NSString *tmpMp3 = [NSTemporaryDirectory() stringByAppendingPathComponent:fileURL.lastPathComponent];
        [[NSFileManager defaultManager] removeItemAtPath:tmpMp3 error:nil];
        [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:tmpMp3] error:nil];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            BOOL success = [self convertMP3toAMR:tmpMp3 targetName:fileName];
            dispatch_async(dispatch_get_main_queue(), ^{
                [loading dismissViewControllerAnimated:YES completion:^{
                    [self loadVoicePacks];
                    if (!success) {
                        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"转换失败" message:@"MP3 内部受损，无法转码为 AMR" preferredStyle:UIAlertControllerStyleAlert];
                        [err addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
                        [self presentViewController:err animated:YES completion:nil];
                    }
                }];
            });
        });

    } else if ([ext isEqualToString:@"amr"]) {
        // 如果用户直接导入的就是 AMR，免转码，直接存入沙盒
        NSString *destPath = [self.basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.amr", fileName]];
        [[NSFileManager defaultManager] removeItemAtPath:destPath error:nil];
        [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:destPath] error:nil];
        [self loadVoicePacks];
    } else {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"格式不支持" message:@"请导入 MP3 或 AMR 格式的文件" preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
    }

    if (accessed) [fileURL stopAccessingSecurityScopedResource];
}

// 极其稳定的内部转换器 (4096帧切片防丢帧)
- (BOOL)convertMP3toAMR:(NSString *)mp3Path targetName:(NSString *)targetName {
    @try {
        @autoreleasepool {
            AVAudioFile *inFile = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:mp3Path] error:nil];
            if (!inFile || inFile.fileFormat.sampleRate == 0) return NO;

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

            NSString *tmpWav = [NSTemporaryDirectory() stringByAppendingPathComponent:@"pure_tmp.wav"];
            NSString *tmpAmr = [NSTemporaryDirectory() stringByAppendingPathComponent:@"pure_tmp.amr"];
            [[NSFileManager defaultManager] removeItemAtPath:tmpWav error:nil];
            [[NSFileManager defaultManager] removeItemAtPath:tmpAmr error:nil];

            if (createPureWav(fullPcmData, tmpWav)) {
                Class converterCls = NSClassFromString(@"VoiceConverter");
                if (converterCls) {
                    [(id<UUUTalkCoreProtocols>)converterCls EncodeWavToAmr:tmpWav amrSavePath:tmpAmr sampleRateType:0];
                    NSData *amrData = [NSData dataWithContentsOfFile:tmpAmr];

                    // 核心防线：必须大于 50 字节才能被承认为成功的 AMR
                    if (amrData && amrData.length > 50) {
                        NSString *finalPath = [self.basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.amr", targetName]];
                        [amrData writeToFile:finalPath atomically:YES];
                        return YES;
                    }
                }
            }
        }
    } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] 转换异常: %@", e); }
    return NO;
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
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"MainCell"];
        UIButton *sendBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [sendBtn setTitle:@"发送" forState:UIControlStateNormal];
        sendBtn.backgroundColor = [UIColor colorWithRed:0.24 green:0.52 blue:0.98 alpha:1.0];
        [sendBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        sendBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        sendBtn.layer.cornerRadius = 14;
        sendBtn.frame = CGRectMake(0, 0, 56, 28);
        [sendBtn addTarget:self action:@selector(sendAMRButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = sendBtn;
    }

    NSString *fileName = self.dataSource[indexPath.row];
    cell.textLabel.text = [fileName stringByDeletingPathExtension];
    cell.textLabel.font = [UIFont systemFontOfSize:16];
    cell.detailTextLabel.text = @"点击这行试听  |  右侧直接发送";
    cell.detailTextLabel.textColor = [UIColor grayColor];
    cell.imageView.image = [UIImage systemImageNamed:@"music.mic"];

    ((UIButton *)cell.accessoryView).tag = indexPath.row;
    return cell;
}

// ======================================================================
// 【核心功能 2】：本地完美验毒试听！
// ======================================================================
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *fullPath = [self.basePath stringByAppendingPathComponent:self.dataSource[indexPath.row]];

    NSString *tmpWav = [NSTemporaryDirectory() stringByAppendingPathComponent:@"debug_play.wav"];
    [[NSFileManager defaultManager] removeItemAtPath:tmpWav error:nil];

    // 利用底层的 C++ 库，把 AMR 逆向解成 WAV 播放。如果放不出声音，说明这个 AMR 废了。
    Class converterCls = NSClassFromString(@"VoiceConverter");
    if (converterCls) {
        [(id<UUUTalkCoreProtocols>)converterCls DecodeAmrToWav:fullPath wavSavePath:tmpWav sampleRateType:0];
        NSData *wavData = [NSData dataWithContentsOfFile:tmpWav];
        if (wavData && wavData.length > 0) {
            self.audioPlayer = [[AVAudioPlayer alloc] initWithData:wavData error:nil];
            [self.audioPlayer play];
        } else {
            UIAlertController *err = [UIAlertController alertControllerWithTitle:@"文件损坏" message:@"无法播放。这个 AMR 文件损坏或内容为空，请左滑删除。" preferredStyle:UIAlertControllerStyleAlert];
            [err addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:err animated:YES completion:nil];
        }
    }
}

// ======================================================================
// 【核心功能 3】：零延迟极速发送
// ======================================================================
- (void)sendAMRButtonClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.dataSource.count) return;

    NSString *fullPath = [self.basePath stringByAppendingPathComponent:self.dataSource[row]];
    NSData *amrData = [NSData dataWithContentsOfFile:fullPath];

    if (amrData && amrData.length > 50) {
        // AMR-NB 的码率约 1.6KB/s，通过文件大小粗略估算显示时长，绝不闪退
        NSInteger duration = MAX(1, MIN(amrData.length / 1600, 60));
        sendAMRVoiceData(amrData, duration, self.currentChannel);
        [self close];
    }
}
@end

#pragma mark - 5. 悬浮窗安全挂载

@interface WKConversationVC : UIViewController
@end

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

#pragma mark - 6. 模块初始化

%ctor {
    if (NSClassFromString(@"WKConversationVC")) {
        %init(UUUVoiceFunHooks);
    }
}
