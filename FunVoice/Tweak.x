#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreServices/CoreServices.h>

#pragma mark - 1. 绝对安全的动态调用引擎 (全类型支持)

static id safeInvoke(id target, SEL selector, NSArray *arguments) {
    if (!target || !selector || ![target respondsToSelector:selector]) return nil;

    NSMethodSignature *sig = [target methodSignatureForSelector:selector];
    if (!sig) return nil;

    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:target];
    [inv setSelector:selector];

    for (NSUInteger i = 0; i < arguments.count; i++) {
        id arg = arguments[i];
        if ([arg isKindOfClass:[NSNull class]]) continue;

        const char *type = [sig getArgumentTypeAtIndex:i + 2];
        if (strcmp(type, @encode(id)) == 0 || strcmp(type, @encode(Class)) == 0) {
            [inv setArgument:&arg atIndex:i + 2];
        } else if (strcmp(type, @encode(NSInteger)) == 0 || strcmp(type, @encode(int)) == 0) {
            NSInteger val = [arg integerValue];
            [inv setArgument:&val atIndex:i + 2];
        } else if (strcmp(type, @encode(BOOL)) == 0 || strcmp(type, @encode(char)) == 0) {
            BOOL val = [arg boolValue];
            [inv setArgument:&val atIndex:i + 2];
        } else if (strcmp(type, @encode(float)) == 0) {
            float val = [arg floatValue];
            [inv setArgument:&val atIndex:i + 2];
        } else if (strcmp(type, @encode(double)) == 0) {
            double val = [arg doubleValue];
            [inv setArgument:&val atIndex:i + 2];
        }
    }

    [inv invoke];

    if (strcmp(sig.methodReturnType, @encode(id)) == 0) {
        __unsafe_unretained id ret = nil;
        [inv getReturnValue:&ret];
        return ret;
    }
    return nil;
}

#pragma mark - Forward Declarations

@interface WKConversationViewController : UIViewController
@end

#pragma mark - 2. 趣味语音主界面与核心处理逻辑

@interface UUUVoiceFunViewController : UIViewController <UITableViewDelegate, UITableViewDataSource, UIDocumentPickerDelegate>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) UISwitch *autoReturnSwitch;
@property (nonatomic, strong) NSMutableArray *dataSource;
@property (nonatomic, strong) NSString *basePath;
@property (nonatomic, strong) id currentChannel;
@end

@implementation UUUVoiceFunViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"趣味语音";
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];

    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"< 返回" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"导入语音" style:UIBarButtonItemStylePlain target:self action:@selector(importVoice)];

    self.basePath = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent:@"趣味语音包"];
    [[NSFileManager defaultManager] createDirectoryAtPath:self.basePath withIntermediateDirectories:YES attributes:nil error:nil];

    [self setupUI];
    [self loadVoicePacks];
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, self.view.bounds.size.width - 30, 80)];
    footerLabel.numberOfLines = 0;
    footerLabel.font = [UIFont systemFontOfSize:12];
    footerLabel.textColor = [UIColor grayColor];
    footerLabel.text = @"温馨提示：该语音功能仅供娱乐，请谨慎使用！\n语音文件位置: 沙盒路径/Documents/趣味语音包/，可以通过[导入语音]来添加 mp3 或 plist。";
    self.tableView.tableFooterView = footerLabel;
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

#pragma mark - 导入文件
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

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导入成功" message:@"已保存至趣味语音包目录" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - TableView 代理
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : self.dataSource.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"开启后选择语音发送后会自动返回到聊天界面" : @"语音专区列表";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"Cell"];

    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"自动返回";
            self.autoReturnSwitch = [[UISwitch alloc] init];
            self.autoReturnSwitch.on = YES;
            cell.accessoryView = self.autoReturnSwitch;
        } else {
            cell.textLabel.text = @"语音消息时长(秒)";
            cell.detailTextLabel.text = @"自动识别 >";
        }
    } else {
        cell.textLabel.text = self.dataSource[indexPath.row];
        cell.imageView.image = [UIImage systemImageNamed:@"folder"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 1) {
        NSString *fileName = self.dataSource[indexPath.row];
        NSString *fullPath = [self.basePath stringByAppendingPathComponent:fileName];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self parseAndProcessVoice:fullPath];
        });
    }
}

#pragma mark - 音频解析与发送核心引擎
- (void)parseAndProcessVoice:(NSString *)filePath {
    if (!self.currentChannel) return;

    __block NSData *amrData = nil;
    __block NSInteger duration = 1;

    // 1. Plist 解析
    if ([filePath hasSuffix:@".plist"]) {
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:filePath];
        if (dict && dict[@"audioData"]) {
            amrData = dict[@"audioData"];
            duration = [dict[@"duration"] integerValue] ?: 1;
        } else {
            NSArray *arr = [NSArray arrayWithContentsOfFile:filePath];
            if (arr.count > 0 && [arr[0] isKindOfClass:[NSDictionary class]]) {
                amrData = arr[0][@"audioData"];
            }
        }
    }
    // 2. MP3 全链路转码 (MP3 -> WAV -> AMR)
    else if ([filePath hasSuffix:@".mp3"]) {
        NSString *wavPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmp_fun.wav"];
        NSString *amrPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tmp_fun.amr"];
        [[NSFileManager defaultManager] removeItemAtPath:wavPath error:nil];
        [[NSFileManager defaultManager] removeItemAtPath:amrPath error:nil];

        NSError *error = nil;
        AVAudioFile *inputFile = [[AVAudioFile alloc] initForReading:[NSURL fileURLWithPath:filePath] error:&error];

        if (!error && inputFile) {
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

            duration = MAX(1, MIN((NSInteger)(inputFile.length / inputFile.fileFormat.sampleRate), 60));

            Class converterCls = NSClassFromString(@"VoiceConverter");
            if (converterCls) {
                safeInvoke(converterCls, NSSelectorFromString(@"EncodeWavToAmr:amrSavePath:sampleRateType:"), @[wavPath, amrPath, @(0)]);
                amrData = [NSData dataWithContentsOfFile:amrPath];
            }
        }
    }
    // 3. 原生 AMR
    else if ([filePath hasSuffix:@".amr"]) {
        amrData = [NSData dataWithContentsOfFile:filePath];
    }

    if (!amrData) {
        NSLog(@"[UUUVoiceFun] 音频数据解析失败！");
        return;
    }

    NSMutableData *smoothWaveform = [NSMutableData dataWithCapacity:100];
    for (int i = 0; i < 100; i++) {
        uint8_t val = (uint8_t)(sin(i * 0.2) * 20 + 30 + arc4random_uniform(10));
        [smoothWaveform appendBytes:&val length:1];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        Class voiceContentClass = NSClassFromString(@"WKVoiceContent");
        id voiceContent = safeInvoke(voiceContentClass, NSSelectorFromString(@"initWithData:second:waveform:"), @[amrData, @(duration), smoothWaveform]);

        if (voiceContent) {
            Class sdkClass = NSClassFromString(@"WKSDK");
            id sharedSDK = safeInvoke(sdkClass, NSSelectorFromString(@"shared"), @[]);
            id chatManager = safeInvoke(sharedSDK, NSSelectorFromString(@"chatManager"), @[]);

            if (chatManager) {
                safeInvoke(chatManager, NSSelectorFromString(@"sendMessage:channel:"), @[voiceContent, self.currentChannel]);

                NSLog(@"[UUUVoiceFun] 趣味语音发送成功！");
                if (self.autoReturnSwitch.isOn) {
                    [self close];
                }
            }
        }
    });
}

@end

#pragma mark - 3. 全局可移动悬浮窗

@interface UUUFloatingVoiceButton : UIButton
@property (nonatomic, weak) UIViewController *currentChatVC;
@end

@implementation UUUFloatingVoiceButton

+ (instancetype)sharedButton {
    static UUUFloatingVoiceButton *btn = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        btn = [UUUFloatingVoiceButton buttonWithType:UIButtonTypeCustom];
        btn.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 70, 300, 50, 50);
        btn.backgroundColor = [[UIColor systemBlueColor] colorWithAlphaComponent:0.8];
        btn.layer.cornerRadius = 25;
        btn.layer.shadowColor = [UIColor blackColor].CGColor;
        btn.layer.shadowOpacity = 0.3;
        btn.layer.shadowOffset = CGSizeMake(0, 2);
        [btn setTitle:@"\U0001F3B5" forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:24];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:btn action:@selector(handlePan:)];
        [btn addGestureRecognizer:pan];

        [btn addTarget:btn action:@selector(btnClicked) forControlEvents:UIControlEventTouchUpInside];
    });
    return btn;
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint translation = [pan translationInView:self.superview];
    CGPoint newCenter = CGPointMake(self.center.x + translation.x, self.center.y + translation.y);
    newCenter.x = MAX(25, MIN(newCenter.x, [UIScreen mainScreen].bounds.size.width - 25));
    newCenter.y = MAX(100, MIN(newCenter.y, [UIScreen mainScreen].bounds.size.height - 100));
    self.center = newCenter;
    [pan setTranslation:CGPointZero inView:self.superview];
}

- (void)btnClicked {
    if (!self.currentChatVC) return;
    id channel = [self.currentChatVC valueForKey:@"channel"];
    if (channel) {
        UUUVoiceFunViewController *vc = [[UUUVoiceFunViewController alloc] init];
        vc.currentChannel = channel;
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationFullScreen;
        [self.currentChatVC presentViewController:nav animated:YES completion:nil];
    }
}

@end

#pragma mark - 4. 生命周期 Hook (改绑绝对可靠的输入面板)

%group UUUVoiceFunHooks

%hook WKConversationInputPanel

- (void)didMoveToWindow {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.window) {
            UIViewController *chatVC = nil;
            UIResponder *responder = self;
            while ((responder = [responder nextResponder])) {
                if ([responder isKindOfClass:[UIViewController class]]) {
                    chatVC = (UIViewController *)responder;
                    break;
                }
            }

            if (chatVC) {
                UUUFloatingVoiceButton *btn = [UUUFloatingVoiceButton sharedButton];
                btn.currentChatVC = chatVC;

                [self.window addSubview:btn];
                [self.window bringSubviewToFront:btn];
                btn.hidden = NO;
            }
        } else {
            [UUUFloatingVoiceButton sharedButton].hidden = YES;
        }
    });
}

%end

%end

#pragma mark - 5. 模块静态初始化封装

static void initVoiceFunModule_once() {
    static BOOL initialized = NO;
    if (initialized) return;

    if (NSClassFromString(@"WKConversationInputPanel")) {
        NSLog(@"[UUUVoiceFun] 动态激活趣味语音独立悬浮系统...");
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
