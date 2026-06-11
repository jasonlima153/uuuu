#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MobileCoreServices/MobileCoreServices.h>

#pragma mark - Forward Declarations
@interface WKConversationInputPanel : UIView
@end

#pragma mark - 1. 核心发送引擎 (C函数指针硬编码，绝对防闪退)

static void sendAMRVoiceData(NSData *amrData, NSInteger duration, id channel) {
    if (!amrData || !channel) {
        NSLog(@"[UUUVoiceFun] 错误：音频数据或频道对象为空");
        return;
    }

    NSMutableData *dummyWaveform = [NSMutableData dataWithCapacity:100];
    for (int i = 0; i < 100; i++) {
        uint8_t val = (uint8_t)(sin(i * 0.2) * 20 + 30 + arc4random_uniform(10));
        [dummyWaveform appendBytes:&val length:1];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        @try {
            Class voiceContentClass = NSClassFromString(@"WKVoiceContent");
            SEL initSel = NSSelectorFromString(@"initWithData:second:waveform:");

            if (voiceContentClass && [voiceContentClass respondsToSelector:initSel]) {
                typedef id (*InitFunc)(id, SEL, id, NSInteger, id);
                InitFunc initFunc = (InitFunc)[voiceContentClass methodForSelector:initSel];
                id voiceContent = initFunc(voiceContentClass, initSel, amrData, duration, dummyWaveform);

                if (voiceContent) {
                    Class sdkClass = NSClassFromString(@"WKSDK");
                    id sharedSDK = [sdkClass performSelector:NSSelectorFromString(@"shared")];
                    id chatManager = [sharedSDK performSelector:NSSelectorFromString(@"chatManager")];

                    if (chatManager) {
                        typedef void (*SendFunc)(id, SEL, id, id);
                        SendFunc sendFunc = (SendFunc)[chatManager methodForSelector:NSSelectorFromString(@"sendMessage:channel:")];
                        sendFunc(chatManager, NSSelectorFromString(@"sendMessage:channel:"), voiceContent, channel);
                        NSLog(@"[UUUVoiceFun] 趣味语音发送成功！");
                    }
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] 发送崩溃拦截: %@", e);
        }
    });
}

#pragma mark - 2. Plist 详情合集列表页 (带发送按钮)

@interface UUUVoiceFunDetailViewController : UITableViewController
@property (nonatomic, strong) NSArray *voiceList;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunDetailViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 返回" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
}

- (void)close {
    [self.navigationController popViewControllerAnimated:YES];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.voiceList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"DetailCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"DetailCell"];

        UIButton *sendBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [sendBtn setTitle:@"发送" forState:UIControlStateNormal];
        sendBtn.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
        [sendBtn setTitleColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
        sendBtn.titleLabel.font = [UIFont systemFontOfSize:14];
        sendBtn.layer.cornerRadius = 4;
        sendBtn.frame = CGRectMake(0, 0, 50, 30);
        [sendBtn addTarget:self action:@selector(sendButtonClicked:) forControlEvents:UIControlEventTouchUpInside];
        cell.accessoryView = sendBtn;
    }

    NSDictionary *voiceDict = self.voiceList[indexPath.row];
    cell.textLabel.text = voiceDict[@"name"] ?: [NSString stringWithFormat:@"语音 %ld", (long)indexPath.row + 1];
    cell.textLabel.font = [UIFont systemFontOfSize:15];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ 秒", voiceDict[@"duration"] ?: @"?"];

    UIButton *btn = (UIButton *)cell.accessoryView;
    btn.tag = indexPath.row;

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)sendButtonClicked:(UIButton *)sender {
    NSInteger row = sender.tag;
    if (row >= self.voiceList.count) return;

    NSDictionary *voiceDict = self.voiceList[row];
    NSData *audioData = voiceDict[@"audioData"];
    NSInteger duration = [voiceDict[@"duration"] integerValue] ?: 1;

    if (audioData) {
        sendAMRVoiceData(audioData, duration, self.currentChannel);

        UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:@"发送成功" preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:alert animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                [self dismissViewControllerAnimated:YES completion:nil];
            }];
        });
    } else {
        NSLog(@"[UUUVoiceFun] 无法读取音频数据！");
    }
}
@end

#pragma mark - 3. 万能解析主面板

@interface UUUVoiceFunViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSString *basePath;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"趣味语音";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 关闭" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入语音" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, self.view.bounds.size.width - 30, 80)];
    footerLabel.numberOfLines = 0;
    footerLabel.font = [UIFont systemFontOfSize:12];
    footerLabel.textColor = [UIColor grayColor];
    footerLabel.text = @"温馨提示：沙盒路径/Documents/趣味语音包/，可以通过[导入语音]来添加 mp3 或 plist。";
    self.tableView.tableFooterView = footerLabel;

    [self loadVoicePacks];
}

- (void)loadVoicePacks {
    self.dataSource = [NSMutableArray array];
    NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.basePath error:nil];
    for (NSString *file in files) {
        if ([file hasSuffix:@".plist"] || [file hasSuffix:@".mp3"] || [file hasSuffix:@".amr"]) {
            [self.dataSource addObject:file];
        }
    }
    [self.tableView reloadData];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)importVoice {
    #pragma clang diagnostic push
    #pragma clang diagnostic ignored "-Wdeprecated-declarations"
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data", @"public.audio"] inMode:UIDocumentPickerModeImport];
    #pragma clang diagnostic pop
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *fileURL = urls.firstObject;
    if (!fileURL) return;
    NSString *destPath = [self.basePath stringByAppendingPathComponent:fileURL.lastPathComponent];
    [[NSFileManager defaultManager] copyItemAtURL:fileURL toURL:[NSURL fileURLWithPath:destPath] error:nil];
    [self loadVoicePacks];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.dataSource.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section { return @"语音专区列表"; }

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"Cell"];
    NSString *fileName = self.dataSource[indexPath.row];
    cell.textLabel.text = fileName;

    if ([fileName hasSuffix:@".plist"]) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder.fill"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.imageView.image = [UIImage systemImageNamed:@"music.note"];
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSString *fileName = self.dataSource[indexPath.row];
    NSString *fullPath = [self.basePath stringByAppendingPathComponent:fileName];

    if ([fileName hasSuffix:@".plist"]) {
        id plistObj = [NSArray arrayWithContentsOfFile:fullPath];
        if (!plistObj) plistObj = [NSDictionary dictionaryWithContentsOfFile:fullPath];

        NSArray *rawArray = nil;
        if ([plistObj isKindOfClass:[NSArray class]]) {
            rawArray = plistObj;
        } else if ([plistObj isKindOfClass:[NSDictionary class]]) {
            rawArray = plistObj[@"voices"] ?: plistObj[@"list"] ?: @[plistObj];
        }

        NSMutableArray *normalizedList = [NSMutableArray array];
        for (id item in rawArray) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                NSMutableDictionary *norm = [NSMutableDictionary dictionary];
                norm[@"name"] = item[@"name"] ?: item[@"title"] ?: @"未命名语音";
                norm[@"duration"] = item[@"time"] ?: item[@"duration"] ?: item[@"second"] ?: @(1);

                id audioRaw = item[@"voice"] ?: item[@"audioData"] ?: item[@"data"] ?: item[@"amr"];
                if ([audioRaw isKindOfClass:[NSString class]]) {
                    norm[@"audioData"] = [[NSData alloc] initWithBase64EncodedString:audioRaw options:0];
                } else if ([audioRaw isKindOfClass:[NSData class]]) {
                    norm[@"audioData"] = audioRaw;
                }

                if (norm[@"audioData"]) [normalizedList addObject:norm];
            }
        }

        if (normalizedList.count > 0) {
            UUUVoiceFunDetailViewController *detailVC = [[UUUVoiceFunDetailViewController alloc] init];
            detailVC.voiceList = normalizedList;
            detailVC.currentChannel = self.currentChannel;
            detailVC.title = [fileName stringByDeletingPathExtension];
            [self.navigationController pushViewController:detailVC animated:YES];
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"解析失败" message:@"不支持该 Plist 的内部格式" preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    } else if ([fileName hasSuffix:@".mp3"] || [fileName hasSuffix:@".amr"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self processAndSendSingleAudio:fullPath];
        });
    }
}

#pragma mark - 单曲转码底层安全处理
- (void)processAndSendSingleAudio:(NSString *)filePath {
    NSData *amrData = nil;
    NSInteger duration = 1;

    if ([filePath hasSuffix:@".mp3"]) {
        NSString *wavPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmp_fun.wav"];
        NSString *amrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmp_fun.amr"];
        [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:amrPath error:nil];

        @try {
            NSError *error = nil;
            AVAudioFile *inputFile = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:filePath] error:&error];
            if (inputFile) {
                AVAudioFormat *outputFormat = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:8000 channels:1 interleaved:YES];
                AVAudioFile *outputFile = [[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:wavPath] settings:outputFormat.settings error:&error];
                AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:inputFile.processingFormat frameCapacity:(AVAudioFrameCount)inputFile.length];
                [inputFile readIntoBuffer:buffer error:nil];

                AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inputFile.processingFormat toFormat:outputFormat];
                AVAudioPCMBuffer *outBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:outputFormat frameCapacity:(AVAudioFrameCount)(buffer.frameCapacity * (8000.0 / inputFile.fileFormat.sampleRate))];
                [converter convertToBuffer:outBuffer error:nil withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
                    *outStatus = AVAudioConverterInputStatus_HaveData;
                    return buffer;
                }];
                [outputFile writeFromBuffer:outBuffer error:nil];

                duration = MAX(1, MIN((NSInteger)(inputFile.length / inputFile.fileFormat.sampleRate), 60));

                Class converterCls = NSClassFromString(@"VoiceConverter");
                SEL encSel = NSSelectorFromString(@"EncodeWavToAmr:amrSavePath:sampleRateType:");
                if (converterCls && [converterCls respondsToSelector:encSel]) {
                    typedef int (*EncodeFunc)(id, SEL, NSString*, NSString*, int);
                    EncodeFunc func = (EncodeFunc)[converterCls methodForSelector:encSel];
                    func(converterCls, encSel, wavPath, amrPath, 0);
                    amrData = [NSData dataWithContentsOfFile:amrPath];
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[UUUVoiceFun] MP3转换崩溃拦截: %@", e);
        }
    } else {
        amrData = [NSData dataWithContentsOfFile:filePath];
    }

    if (amrData) {
        sendAMRVoiceData(amrData, duration, self.currentChannel);
        dispatch_async(dispatch_get_main_queue(), ^{
            [self close];
        });
    }
}
@end

#pragma mark - 4. Hook: 物理挂载悬浮窗到聊天页面 (绑定 WKConversationInputPanel)

%group UUUVoiceFunHooks

%hook WKConversationInputPanel

- (void)didMoveToWindow {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIResponder *responder = self;
        UIViewController *chatVC = nil;
        while ((responder = [responder nextResponder])) {
            if ([responder isKindOfClass:[UIViewController class]]) {
                chatVC = (UIViewController *)responder;
                break;
            }
        }

        if (self.window && chatVC) {
            // 防止重复添加
            if ([chatVC.view viewWithTag:888999]) return;

            UIButton *floatBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            floatBtn.tag = 888999;
            floatBtn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 70, 300, 50, 50);
            floatBtn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.8];
            floatBtn.layer.cornerRadius = 25;
            floatBtn.layer.shadowColor = [UIColor blackColor].CGColor;
            floatBtn.layer.shadowOpacity = 0.4;
            floatBtn.layer.shadowOffset = CGSizeMake(0, 2);
            [floatBtn setTitle:@"\U0001F3B5" forState:UIControlStateNormal];
            floatBtn.titleLabel.font = [UIFont systemFontOfSize:24];

            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:floatBtn action:@selector(uuu_handlePan:)];
            [floatBtn addGestureRecognizer:pan];

            [floatBtn addTarget:floatBtn action:@selector(uuu_openVoicePanel) forControlEvents:UIControlEventTouchUpInside];

            // 绑定 chatVC 引用到按钮的关联对象
            objc_setAssociatedObject(floatBtn, @"chatVC", chatVC, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

            [chatVC.view addSubview:floatBtn];
            [chatVC.view bringSubviewToFront:floatBtn];
        }
    });
}

%end

%end

#pragma mark - 5. 悬浮窗拖拽与点击 (分类扩展 UIButton)

@interface UIButton (UUUVoiceFun)
- (void)uuu_handlePan:(UIPanGestureRecognizer *)pan;
- (void)uuu_openVoicePanel;
@end

@implementation UIButton (UUUVoiceFun)

- (void)uuu_handlePan:(UIPanGestureRecognizer *)pan {
    UIView *btn = pan.view;
    CGPoint translation = [pan translationInView:btn.superview];
    CGPoint newCenter = CGPointMake(btn.center.x + translation.x, btn.center.y + translation.y);
    newCenter.x = MAX(25, MIN(newCenter.x, [UIScreen mainScreen].bounds.size.width - 25));
    newCenter.y = MAX(100, MIN(newCenter.y, [UIScreen mainScreen].bounds.size.height - 100));
    btn.center = newCenter;
    [pan setTranslation:CGPointZero inView:btn.superview];
}

- (void)uuu_openVoicePanel {
    UIViewController *chatVC = objc_getAssociatedObject(self, @"chatVC");
    if (!chatVC) return;
    id channel = [chatVC valueForKey:@"channel"];
    if (channel) {
        UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
        vc.currentChannel = channel;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [chatVC presentViewController:nav animated:YES completion:nil];
    }
}

@end

#pragma mark - 6. 模块静态初始化

static void initVoiceFunModule_once() {
    static BOOL initialized = NO;
    if (initialized) return;

    if (NSClassFromString(@"WKConversationInputPanel")) {
        NSLog(@"[UUUVoiceFun] 动态激活趣味语音悬浮系统...");
        %init(UUUVoiceFunHooks);
        initialized = YES;
    }
}

%ctor {
    if (NSClassFromString(@"WKConversationInputPanel")) {
        initVoiceFunModule_once();
    } else {
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                         object:nil
                                                          queue:nil
                                                     usingBlock:^(NSNotification *note) {
            initVoiceFunModule_once();
        }];
    }
    %init;
}
