#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// 前向声明
@interface WKConversationVC : UIViewController
@end

@interface VoiceConverter : NSObject
@end

@interface UUUVoiceFunViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSString *basePath;
@property (nonatomic, strong) AVAudioPlayer *audioPlayer;
@end

// ==========================================
// 1. 全局弹药库 (保存你选中的语音文件路径)
// ==========================================
@interface UUUVoiceManager : NSObject
@property (nonatomic, strong) NSString *readyWavPath;
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
// 2. 核心绝杀：底层 WAV 文件掉包拦截！
// ==========================================
%group UUUVoiceFunHooks

%hook VoiceConverter

+ (int)EncodeWavToAmr:(NSString *)wavPath amrSavePath:(NSString *)amrPath sampleRateType:(int)type {
    NSString *targetWav = [UUUVoiceManager shared].readyWavPath;

    if (targetWav && [[NSFileManager defaultManager] fileExistsAtPath:targetWav]) {
        [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
        [[NSFileManager defaultManager] copyItemAtPath:targetWav toPath:wavPath error:nil];

        NSLog(@"[UUUVoiceFun] 狸猫换太子！原生录音文件已被替换为: %@", targetWav);
        [UUUVoiceManager shared].readyWavPath = nil;
    }

    return %orig(wavPath, amrPath, type);
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
// 4. 控制面板 (支持 MP3/AMR 统一提纯)
// ==========================================

@implementation UUUVoiceFunViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"趣味语音 (掉包狙击版)";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入MP3/AMR" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"UUUWavPacks"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 65;
    [self.view addSubview:self.tableView];

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, self.view.bounds.size.width - 30, 80)];
    footerLabel.numberOfLines = 0;
    footerLabel.font = [UIFont systemFontOfSize:13];
    footerLabel.textColor = [UIColor darkGrayColor];
    footerLabel.text = @"【使用秘籍】\n1. 点击右侧【装备】将语音上膛。\n2. 去聊天框按住原生【按住说话】录制 1 秒松手。\n3. 原生录音将被瞬间替换为你的音频发送！0 卡死！";
    self.tableView.tableFooterView = footerLabel;

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        if ([file.lowercaseString hasSuffix:@".wav"]) [self.dataSource addObject:file];
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

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *fileURL = urls.firstObject;
    if (!fileURL) return;

    BOOL accessed = [fileURL startAccessingSecurityScopedResource];
    NSString *ext = fileURL.pathExtension.lowercaseString;
    NSString *fileName = [[fileURL lastPathComponent] stringByDeletingPathExtension];
    NSString *finalWavPath = [self.basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.wav", fileName]];

    UIAlertController *loading = [UIAlertController alertControllerWithTitle:@"正在提纯" message:@"正在转换为完美的 WAV 标准格式..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loading animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        BOOL success = NO;
        if ([ext isEqualToString:@"mp3"]) {
            @try {
                @autoreleasepool {
                    AVAudioFile *inFile = [[AVAudioFile alloc] initForReading:fileURL error:nil];
                    if (inFile && inFile.fileFormat.sampleRate > 0) {
                        AVAudioFormat *outFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];

                        // 4096帧切片循环转换
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
                            [converter convertToBuffer:outBuf error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount p, AVAudioConverterInputStatus *s) {
                                if (consumed) { *s = AVAudioConverterInputStatus_EndOfStream; return nil; }
                                consumed = YES; *s = AVAudioConverterInputStatus_HaveData; return inBuf;
                            }];

                            if (outBuf.frameLength > 0) {
                                [fullPcmData appendBytes:outBuf.int16ChannelData[0] length:outBuf.frameLength * 2];
                            }
                        }

                        success = [self createPureWav:fullPcmData savePath:finalWavPath];
                    }
                }
            } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] MP3转换异常: %@", e); }

        } else if ([ext isEqualToString:@"amr"]) {
            NSData *fileData = [NSData dataWithContentsOfURL:fileURL];
            if (fileData.length > 50) {
                NSString *tmpAmr = [NSTemporaryDirectory() stringByAppendingPathComponent:fileURL.lastPathComponent];
                [fileData writeToFile:tmpAmr atomically:YES];

                Class converterCls = NSClassFromString(@"VoiceConverter");
                if (converterCls) {
                    SEL decodeSel = NSSelectorFromString(@"DecodeAmrToWav:wavSavePath:sampleRateType:");
                    if ([converterCls respondsToSelector:decodeSel]) {
                        int (*DecodeFunc)(id, SEL, NSString*, NSString*, int) = (int (*)(id, SEL, NSString*, NSString*, int))[converterCls methodForSelector:decodeSel];
                        DecodeFunc(converterCls, decodeSel, tmpAmr, finalWavPath, 0);
                        success = [[NSFileManager defaultManager] fileExistsAtPath:finalWavPath];
                    }
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [loading dismissViewControllerAnimated:YES completion:^{
                [self loadVoicePacks];
                if (!success) {
                    UIAlertController *err = [UIAlertController alertControllerWithTitle:@"失败" message:@"文件损坏或格式不支持" preferredStyle:UIAlertControllerStyleAlert];
                    [err addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
                    [self presentViewController:err animated:YES completion:nil];
                }
            }];
        });
    });

    if (accessed) [fileURL stopAccessingSecurityScopedResource];
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
    cell.detailTextLabel.text = @"点击此行完美试听";
    cell.detailTextLabel.textColor = [UIColor darkGrayColor];
    cell.imageView.image = [UIImage systemImageNamed:@"speaker.wave.3.fill"];

    ((UIButton *)cell.accessoryView).tag = indexPath.row;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:self.dataSource[indexPath.row]];
    self.audioPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:[NSURL fileURLWithPath:fullPath] error:nil];
    [self.audioPlayer play];
}

- (void)equipVoiceClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.dataSource.count) return;
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:self.dataSource[row]];

    [UUUVoiceManager shared].readyWavPath = fullPath;

    UIAlertController *succ = [UIAlertController alertControllerWithTitle:@"🎯 装备成功！"
        message:@"已上膛！\n\n请关闭面板，在聊天界面按住 App 原生的【按住说话】按钮，录制 1 秒钟松手，即可将原生录音偷天换日！"
        preferredStyle:UIAlertControllerStyleAlert];
    [succ addAction:[UIAlertAction actionWithTitle:@"去发送" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self close];
    }]];
    [self presentViewController:succ animated:YES completion:nil];
}
@end

// ==========================================
// 5. 初始化
// ==========================================

%ctor {
    if (NSClassFromString(@"VoiceConverter")) {
        %init(UUUVoiceFunHooks);
    }
}
