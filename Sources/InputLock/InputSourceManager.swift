import Carbon
import Foundation

/// 封装 Carbon TISInputSource API，提供获取和切换输入法的接口
enum InputSourceManager {

    /// 获取当前输入法的本地化显示名称
    static func currentInputSourceName() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return "未知输入法"
        }
        return localizedName(of: source)
    }

    /// 获取当前输入法的 TISInputSource 引用（已 retain，调用方负责释放）
    static func currentInputSourceRef() -> TISInputSource? {
        return TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    /// 将系统输入法切换到指定的 TISInputSource
    static func selectInputSource(_ source: TISInputSource) {
        TISSelectInputSource(source)
    }

    /// 通过 TISInputSource 获取其本地化名称
    static func localizedName(of source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else {
            return "未知输入法"
        }
        // kTISPropertyLocalizedName 返回的是 CFString
        return (Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String)
    }

    /// 获取系统自带的英文（ABC）输入法的 TISInputSource 引用
    static func getEnglishInputSource() -> TISInputSource? {
        let properties = [kTISPropertyInputSourceID: "com.apple.keylayout.ABC"] as CFDictionary
        guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
              let englishSource = list.first else {
            return nil
        }
        return englishSource
    }
}
