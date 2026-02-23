import Carbon
import Foundation

/// 承载输入法列表页面的数据结构
struct InputSourceItem: Hashable {
    let id: String
    let name: String
}

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
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// 通过 TISInputSource 获取其唯一 ID
    static func sourceID(of source: TISInputSource) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// 根据 ID 获取指定的 TISInputSource
    static func getInputSource(byID id: String) -> TISInputSource? {
        let properties = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else {
            return nil
        }
        return source
    }

    /// 切换到指定 ID 的输入法
    static func selectInputSource(byID id: String) {
        if let source = getInputSource(byID: id) {
            selectInputSource(source)
        }
    }

    /// 获取系统中所有启用的键盘类输入法
    static func getAllEnabledInputSources() -> [InputSourceItem] {
        let properties = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        // 传入 false 会获取全部已启用的输入源
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        
        var result: [InputSourceItem] = []
        for source in list {
            // 过滤掉不可选的输入属性
            guard let isSelectablePtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { continue }
            let isSelectable = Unmanaged<CFBoolean>.fromOpaque(isSelectablePtr).takeUnretainedValue()
            guard CFBooleanGetValue(isSelectable) else { continue }
            
            if let id = sourceID(of: source) {
                let name = localizedName(of: source)
                result.append(InputSourceItem(id: id, name: name))
            }
        }
        // 去重和清理一些奇怪的空ID
        var uniqueResult: [InputSourceItem] = []
        var seenIDs = Set<String>()
        for item in result {
            if !seenIDs.contains(item.id) && !item.id.isEmpty {
                seenIDs.insert(item.id)
                uniqueResult.append(item)
            }
        }
        return uniqueResult
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
