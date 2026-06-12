#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// 前向声明 + 协议前置，避免编译错误
@interface WKConversationVC : UIViewController
@end

@interface WKVoiceContent : NSObject
@end

@protocol UUUTalkCoreProtocols <NSObject>
+ (int)EncodeWavToAmr:(NSString *)wavPath amrSavePath:(NSString *)amrPath sampleRateType:(int)type;
+ (int)DecodeAmrToWav:(NSString *)amrPath wavSavePath:(NSString *)wavPath sampleRateType:(int)type;
+ (instancetype)initWithData:(NSData *)data second:(NSInteger)second waveform:(NSData *)waveform;
+ (id)shared;
- (id)chatManager;
- (void)sendMessage:(id)msg channel:(id)channel;
@end

// ==========================================
// 1. 全局弹药库 (保存你选中的语音)
// ==========================================
@interface UUUVoiceManager : NSObject
@property (nonatomic, strong) NSData *readyAMRData;
@property (nonatomic, assign) NSInteger readyDuration;
+ (instancetype)shared;
@end

@implementation UUUVoiceManager
+ (instancetype)shared {
    static UUUVoiceManager *inst = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ inst = [[UUUVoiceManager alloc] init]; });
    return inst;
}
@end

// ==========================================
// 2. 核心拦截引擎：狸猫换太子！
// ==========================================
%group UUUVoiceFunHooks

%hook WKVoiceContent

+ (instancetype)initWithData:(NSData *)data second:(NSInteger)second waveform:(id)waveform {
    UUUVoiceManager *mgr = [UUUVoiceManager shared];

    if (mgr.readyAMRData && mgr.readyAMRData.length > 50) {
        NSData *fakeData = mgr.readyAMRData;
        NSInteger fakeSecond = mgr.readyDuration;

        mgr.readyAMRData = nil;
        mgr.readyDuration = 0;

        NSLog(@"[UUUVoiceFun] 狸猫换太子！替换 %ld秒 为 %ld秒", (long)second, (long)fakeSecond);
        return %orig(fakeData, fakeSecond, waveform);
    }

    return %orig(data, second, waveform);
}

%end

// ==========================================
// 3. 悬浮窗 UI 挂载
// ==========================================
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
    UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:nav animated:YES completion:nil];
}

%end

%end

// ==========================================
// 4. 控制面板 (管理与装备语音)
// ==========================================

@interface UUUVoiceFunViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSString *basePath;
@end

@implementation UUUVoiceFunViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"趣味语音包 (狙击版)";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入MP3/AMR" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 65;
    [self.view addSubview:self.tableView];

    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, self.view.bounds.size.width - 30, 80)];
    footerLabel.numberOfLines = 0;
    footerLabel.font = [UIFont systemFontOfSize:13];
    footerLabel.textColor = [UIColor darkGrayColor];
    footerLabel.text = @"【使用秘籍】：\n1. 点击右侧【装备】按钮将语音上膛。\n2. 关闭面板，去聊天框按住原生【按住说话】录制 1 秒松手，语音将被自动替换发送！";
    self.tableView.tableFooterView = footerLabel;

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        if ([file.lowercaseString hasSuffix:@".amr"]) [self.dataSource addObject:file];
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

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *fileURL = urls.firstObject;
    if (!fileURL) return;

    BOOL accessed = [fileURL startAccessingSecurityScopedResource];
    NSString *ext = fileURL.pathExtension.lowercaseString;
    NSString *fileName = [[fileURL lastPathComponent] stringByDeletingPathExtension];

    if ([ext isEqualToString:@"mp3"]) {
        UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"正在转换" message:@"正在提取高质量 AMR..." preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:loading animated:YES completion:nil];

        NSString *tmpMp3 = [NSTemporaryDirectory() stringByAppendingPathComponent:fileURL.lastPathComponent];
        [[NSFileManager defaultManager] removeItemAtPath:tmpMp3 error:nil];
        [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:tmpMp3] error:nil];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            BOOL success = [self convertMP3toAMR:tmpMp3 targetName:fileName];
            dispatch_async(dispatch_get_main_queue(), ^{
                [loading dismissViewControllerAnimated:YES completion:^{
                    [self loadVoicePacks];
                    if (!success) {
                        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"转换失败" message:@"格式错误，请导入其它文件" preferredStyle:UIAlertControllerStyleAlert];
                        [err addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
                        [self presentViewController:err animated:YES completion:nil];
                    }
                }];
            });
        });
    } else if ([ext isEqualToString:@"amr"]) {
        NSData *fileData = [NSData dataWithContentsOfURL:fileURL];
        if (fileData.length > 50) {
            NSString *destPath = [self.basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.amr", fileName]];
            [fileData writeToFile:destPath atomically:YES];
            [self loadVoicePacks];
        }
    }
    if (accessed) [fileURL stopAccessingSecurityScopedResource];
}

- (BOOL)createPureWav:(NSData *)pcmData savePath:(NSString *)savePath {
    if (!pcmData) return NO;
    uint32_t dataSize = (uint32_t)pcmData.length;
    NSMutableData *wavData = [NSMutableData data];
    [wavData appendBytes:"RIFF" length:4];
    uint32_t chunkSize = dataSize + 36;
    [wavData appendBytes:&chunkSize length:4];
    [wavData appendBytes:"WAVEfmt " length:8];
    uint32_t subchunk1Size = 16;
    [wavData appendBytes:&subchunk1Size length:4];
    uint16_t audioFormat = 1; [wavData appendBytes:&audioFormat length:2];
    uint16_t numChannels = 1; [wavData appendBytes:&numChannels length:2];
    uint32_t sampleRate = 8000; [wavData appendBytes:&sampleRate length:4];
    uint32_t byteRate = 8000 * 2; [wavData appendBytes:&byteRate length:4];
    uint16_t blockAlign = 2; [wavData appendBytes:&blockAlign length:2];
    uint16_t bitsPerSample = 16; [wavData appendBytes:&bitsPerSample length:2];
    [wavData appendBytes:"data" length:4]; [wavData appendBytes:&dataSize length:4];
    [wavData appendData:pcmData];
    return [wavData writeToFile:savePath atomically:YES];
}

- (BOOL)convertMP3toAMR:(NSString *)mp3Path targetName:(NSString *)targetName {
    @try {
        @autoreleasepool {
            AVAudioFile *inFile = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:mp3Path] error:nil];
            if (!inFile) return NO;
            AVAudioFormat *outFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];

            // 4096帧切片循环转换，防止长音频丢帧
            NSMutableData *fullPcmData = [NSMutableData data];
            AVAudioFrameCount chunkSize = 4096;
            AVAudioPCMBuffer *inBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inFile.processingFormat frameCapacity:chunkSize];
            AVAudioPCMBuffer *outBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outFormat frameCapacity:chunkSize];
            AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inFile.processingFormat toFormat:outFormat];

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

            if ([self createPureWav:fullPcmData savePath:tmpWav]) {
                Class converterCls = NSClassFromString(@"VoiceConverter");
                if (converterCls) {
                    [(id<UUUTalkCoreProtocols>)converterCls EncodeWavToAmr:tmpWav amrSavePath:tmpAmr sampleRateType:0];
                    NSData *amrData = [NSData dataWithContentsOfFile:tmpAmr];
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
        UIButton *equipBtn = [UIButton buttonWithType:UIButtonTypeCustom];
        [equipBtn setTitle:@"装备" forState:UIControlStateNormal];
        equipBtn.backgroundColor = [UIColor colorWithRed:1.0 green:0.38 blue:0.28 alpha:1.0];
        [equipBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        equipBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
        equipBtn.layer.cornerRadius = 14;
        equipBtn.frame = CGRectMake(0, 0, 60, 28);
        [equipBtn addTarget:self action:@selector(equipVoiceClicked:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = equipBtn;
    }

    NSString *fileName = self.dataSource[indexPath.row];
    cell.textLabel.text = [fileName stringByDeletingPathExtension];
    cell.textLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    cell.detailTextLabel.text = @"点击右侧装备，然后在聊天框正常发一段语音";
    cell.detailTextLabel.textColor = [UIColor darkGrayColor];
    cell.imageView.image = [UIImage systemImageNamed:@"speaker.wave.3.fill"];

    ((UIButton *)cell.accessoryView).tag = indexPath.row;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)equipVoiceClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.dataSource.count) return;

    NSString *fullPath = [self.basePath stringByAppendingPathComponent:self.dataSource[row]];
    NSData *amrData = [NSData dataWithContentsOfFile:fullPath];

    if (amrData && amrData.length > 50) {
        NSInteger duration = MAX(1, MIN(amrData.length / 1600, 60));
        [UUUVoiceManager shared].readyAMRData = amrData;
        [UUUVoiceManager shared].readyDuration = duration;

        UIAlertController *succ = [UIAlertController alertControllerWithTitle:@"🎯 装备成功！"
            message:[NSString stringWithFormat:@"《%@》已上膛！\n\n请关闭此面板，去聊天界面按住 App 原生的语音按钮录制一秒钟松手，即可将刚才的录音替换发送！", [self.dataSource[row] stringByDeletingPathExtension]]
            preferredStyle:UIAlertControllerStyleAlert];
        [succ addAction:[UIAlertAction actionWithTitle:@"去发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self close];
        }]];
        [self presentViewController:succ animated:YES completion:nil];
    }
}
@end

// ==========================================
// 5. 初始化
// ==========================================

%ctor {
    if (NSClassFromString(@"WKConversationVC")) {
        %init(UUUVoiceFunHooks);
    }
}
