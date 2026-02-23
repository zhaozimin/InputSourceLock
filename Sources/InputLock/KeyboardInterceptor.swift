import Foundation
import CoreGraphics
import AppKit
import Carbon

/// 键盘全局事件拦截器
/// 负责拦截特定的按键组合，比如双击 Option + Tab 切换输入法
@MainActor
final class KeyboardInterceptor: ObservableObject {
    static let shared = KeyboardInterceptor()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    /// 当用户点击 Option + Tab 时的双击超时时间
    private let doubleTapThreshold: TimeInterval = 0.4
    private var lastOptionTabTime: Date = .distantPast
    
    // 初始化并尝试启动监听
    private init() {}
    
    func start() {
        // 先检查是否有辅助设备的权限
        // 规避 Swift 6 Strict Concurrency: 直接使用底层的字符串 Key
        let promptOption = "AXTrustedCheckOptionPrompt" as CFString
        let options: NSDictionary = [promptOption: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if !accessEnabled {
            print("[KeyboardInterceptor] 未获取辅助功能权限，无法拦截全局按键。")
            // 权限弹窗已由系统弹出，我们在此只做记录，并可以选择不启动 tap，或者启动一个被动的 global monitor
            // 但如果想要真的“拦截吞噬”系统事件，必须通过 CGEvent.tapCreate 而且需要通过系统偏好设置开启权限
        }
        
        setupEventTap()
    }
    
    private func setupEventTap() {
        guard eventTap == nil else { return }
        
        // 我们需要截获 keyDown 事件
        let eventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        
        let callback: CGEventTapCallBack = { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            
            // 将 refcon 转换回 KeyboardInterceptor 类型，因为是 @MainActor 需要小心线程
            // CGEvent 拦截回调发生在独立线程/底层系统队列，为了安全我们在全局做简单的判断，异步派发到主线程执行特定逻辑
            let interceptor = Unmanaged<KeyboardInterceptor>.fromOpaque(refcon).takeUnretainedValue()
            
            if type == .keyDown {
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                
                // 判断是否是 Option 键被按下，而且不能有 Command/Control/Shift 掺杂
                let isOptionPressed = flags.contains(.maskAlternate)
                let isCommandPressed = flags.contains(.maskCommand)
                let isControlPressed = flags.contains(.maskControl)
                let isShiftPressed = flags.contains(.maskShift)
                
                // KeyCode 48 是 Tab 键
                if keyCode == 48 && isOptionPressed && !isCommandPressed && !isControlPressed && !isShiftPressed {
                    
                    // 我们拦截到了 Option + Tab!
                    let now = Date()
                    let timeSinceLast = now.timeIntervalSince(interceptor.lastOptionTabTime)
                    
                    interceptor.lastOptionTabTime = now
                    
                    if timeSinceLast < interceptor.doubleTapThreshold {
                        // 这是第二次按下！（双击成立）
                        print("[KeyboardInterceptor] 触发双击 Option + Tab，执行输入法切换！")
                        // 我们派发到主线程去切输入法
                        DispatchQueue.main.async {
                            interceptor.switchToNextInputSource()
                        }
                        // 重置时间，防连续按三下变成两次触发
                        interceptor.lastOptionTabTime = .distantPast
                        
                        // 我们依然返回 nil 吞噬这第二次点击的事件，不让其在系统中打出 tab 或是跳出其他界面
                        return nil
                    } else {
                        // 这是第一次按下，或是距离上次按很久了
                        print("[KeyboardInterceptor] 拦截了一次单机的 Option + Tab (防误触生效)")
                        // 直接吞噬该事件，不传给系统！
                        return nil
                    }
                }
            }
            
            // 如果不是我们要拦截的键，原样放行
            return Unmanaged.passUnretained(event)
        }
        
        let ptr = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: ptr
        ) else {
            print("[KeyboardInterceptor] 创建 CGEventTap 失败，请检查是否在『系统偏好设置-隐私-辅助功能』中勾选了该应用。")
            return
        }
        
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[KeyboardInterceptor] 键盘监听服务启动成功。")
    }
    
    /// 当满足双击条件时，由此处执行切换下一个输入法的行为
    private func switchToNextInputSource() {
        guard let sourceList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else { return }
        let kbSources = sourceList.filter {
            guard let typePtr = TISGetInputSourceProperty($0, kTISPropertyInputSourceType),
                  let idPtr = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
            let type = Unmanaged<CFString>.fromOpaque(typePtr).takeUnretainedValue() as String
            let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
            return (type == kTISTypeKeyboardLayout as String || type == kTISTypeKeyboardInputMode as String) && id != "com.apple.PressAndHold"
        }
        
        guard kbSources.count > 1 else { return }
        
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return }
        guard let currentIdPtr = TISGetInputSourceProperty(current, kTISPropertyInputSourceID) else { return }
        let currentId = Unmanaged<CFString>.fromOpaque(currentIdPtr).takeUnretainedValue() as String
        
        if let currentIndex = kbSources.firstIndex(where: {
            guard let ptr = TISGetInputSourceProperty($0, kTISPropertyInputSourceID) else { return false }
            return (Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String) == currentId
        }) {
            let nextIndex = (currentIndex + 1) % kbSources.count
            InputSourceManager.selectInputSource(kbSources[nextIndex])
            
            // 由于是我们**主动代码**切换的输入法，我们需要明确通知 LockService 更新其锁定的目标！
            // 此处会在系统派发 TISNotifySelectedKeyboardInputSourceChanged 通知后被 LockService 收到。
            // 只要不是系统自己偷偷切的，LockService 发现过了好久（或在短时间内接纳），就会认定这个新的就是目标。
        }
    }
}
