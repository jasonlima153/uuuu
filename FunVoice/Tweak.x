#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// ==========================================
// 1. 核心接口协议声明 (对齐分析报告，全部采用原生调用)
// ==========================================
@protocol UUUTalkCoreProtocols <NSObject>
+ (int)DecodeAmrToWav:(NSString *)amrPath wavSavePath:(NSString *)wavPath sampleRateType:(int)type;
+ (instancetype)initWithData:(NSData *)data second:(NSInteger)second waveform:(NSData *)waveform;
+ (id)shared;
- (id)chatManager;
- (void)sendMessage:(id)msg channel:(id)channel;
@end

#pragma mark - 2. 纯净发送引擎 (0转码，0计算，直接投递)

static void sendAMRVoiceData(NSData *amrData, NSInteger duration, id channel) {
    if (!amrData || !channel) return;

    // 生成标准的假波形 NSData，避开 JSON 序列化崩溃
    NSMutableData *dummyWaveform = [NSMutableData dataWithCapacity:100];
    for (int i = 0; i < 100; i++) {
        uint8_t val = (uint8_t)(sin(i * 0.2) * 20 + 30 + arc4random_uniform(10));
        [dummyWaveform appendBytes:&val length:1];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class voiceContentClass = NSClassFromString(@"WKVoiceContent");
            if (voiceContentClass) {
                id<UUUTalkCoreProtocols> voiceContent = [(id<UUUTalkCoreProtocols>)[voiceContentClass class] initWithData:amrData second:duration waveform:dummyWaveform];

                Class sdkClass = NSClassFromString(@"WKSDK");
                id<UUUTalkCoreProtocols> chatManager = [[(id<UUUTalkCoreProtocols>)[sdkClass class] shared] chatManager];

                if (chatManager && voiceContent) {
                    [chatManager sendMessage:voiceContent channel:channel];
                    NSLog(@"[UUUVoiceFun] 🚀 AMR 语音安全直发成功！");
                }
            }
        } @catch (NSException *e) { NSLog(@"[UUUVoiceFun] ❌ 发送异常: %@", e); }
    });
}

#pragma mark - 3. 插件主面板 (专为高稳定 AMR 打造)

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
    self.title = @"趣味语音 (AMR纯净版)";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入AMR" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.rowHeight = 60;
    [self.view addSubview:self.tableView];

    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback error:nil];
    [[AVAudioSession sharedInstance] setActive:YES error:nil];

    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, self.view.bounds.size.width - 30, 80)];
    footerLabel.numberOfLines = 0;
    footerLabel.font = [UIFont systemFontOfSize:12];
    footerLabel.textColor = [UIColor darkGrayColor];
    footerLabel.text = @"⚠️ 告别闪退：本版本已彻底移除导致声音损坏的 MP3 转换器。请在网页将音频转换为 .amr 格式后再导入使用。";
    self.tableView.tableFooterView = footerLabel;

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
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
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.item", @"public.audio"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
#pragma clang diagnostic pop
}

// ======================================================================
// 【核心绝杀】：沙盒穿透内存直读！彻底解决导入 AMR 说"损坏/0字节"的玄学问题
// ======================================================================
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *fileURL = urls.firstObject;
    if (!fileURL) return;

    // 打开 iOS 安全锁
    BOOL accessed = [fileURL startAccessingSecurityScopedResource];

    // 【最关键的一步】：不用容易失败的 copyItem，直接在权限范围内把文件吸入内存 (NSData)！
    NSData *fileData = [NSData dataWithContentsOfURL:fileURL];

    // 关闭安全锁
    if (accessed) [fileURL stopAccessingSecurityScopedResource];

    if (!fileData || fileData.length < 50) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"导入失败" message:@"由于 iOS 沙盒权限或文件为空，无法读取该文件。" preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    // 强制验证 AMR 文件底层头部标识 #!AMR
    NSString *header = [[NSString alloc] initWithData:[fileData subdataWithRange:NSMakeRange(0, 5)] encoding:NSASCIIStringEncoding];
    if (![header isEqualToString:@"#!AMR"]) {
        UIAlertController *err = [UIAlertController alertControllerWithTitle:@"格式警告" message:@"这不是一个真正的 AMR 文件！\n它可能是直接把后缀改成了 .amr，发出去会报错。\n\n请使用网页转换工具生成标准的 AMR。" preferredStyle:UIAlertControllerStyleAlert];
        [err addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
        [self presentViewController:err animated:YES completion:nil];
        return;
    }

    // 一切完美，直接把内存里的数据写入沙盒，绝不产生 0 字节文件！
    NSString *fileName = [[fileURL lastPathComponent] stringByDeletingPathExtension];
    NSString *destPath = [self.basePath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.amr", fileName]];
    [fileData writeToFile:destPath atomically:YES];

    [self loadVoicePacks];

    UIAlertController *succ = [UIAlertController alertControllerWithTitle:@"导入成功" message:@"AMR 语音导入成功，可点击该行试听或直接发送！" preferredStyle:UIAlertControllerStyleAlert];
    [succ addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:succ animated:YES completion:nil];
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
    cell.detailTextLabel.text = @"点击此行试听  |  点击右侧发送";
    cell.detailTextLabel.textColor = [UIColor grayColor];
    cell.imageView.image = [UIImage systemImageNamed:@"music.mic"];

    ((UIButton *)cell.accessoryView).tag = indexPath.row;
    return cell;
}

// 本地安全试听
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:self.dataSource[indexPath.row]];

    NSString *tmpWav = [NSTemporaryDirectory() stringByAppendingPathComponent:@"debug_play.wav"];
    [[NSFileManager defaultManager] removeItemAtPath:tmpWav error:nil];

    Class converterCls = NSClassFromString(@"VoiceConverter");
    if (converterCls && [converterCls respondsToSelector:NSSelectorFromString(@"DecodeAmrToWav:wavSavePath:sampleRateType:")]) {
        [(id<UUUTalkCoreProtocols>)converterCls DecodeAmrToWav:fullPath wavSavePath:tmpWav sampleRateType:0];
        NSData *wavData = [NSData dataWithContentsOfFile:tmpWav];
        if (wavData && wavData.length > 0) {
            self.audioPlayer = [[AVAudioPlayer alloc] initWithData:wavData error:nil];
            [self.audioPlayer play];
        } else {
            UIAlertController *err = [UIAlertController alertControllerWithTitle:@"无法试听" message:@"虽然文件已安全导入，但由于底层解码库极度老旧，无法在本地解码该 AMR 试听。\n\n但这不影响发送！您可以直接发送给朋友测试。" preferredStyle:UIAlertControllerStyleAlert];
            [err addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:err animated:YES completion:nil];
        }
    }
}

// 一键光速发送
- (void)sendAMRButtonClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.dataSource.count) return;

    NSString *fullPath = [self.basePath stringByAppendingPathComponent:self.dataSource[row]];
    NSData *amrData = [NSData dataWithContentsOfFile:fullPath];

    if (amrData && amrData.length > 50) {
        // AMR 的平均码率：1 秒 ≈ 1600 字节，据此估算语音在界面的气泡显示长度
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
