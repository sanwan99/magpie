import SwiftUI

/// 极轻量代码高亮器 — 用纯 NSRegularExpression 把源码切成 keyword / function /
/// number / string / comment 五类 token，回传 `AttributedString` 给 SwiftUI `Text` 直接渲染。
///
/// **不要把它当通用 highlighter 用**：
/// - 不处理嵌套字符串、模板字符串、HEREDOC、字符串内插。
/// - 不感知作用域 / 类型推导。
/// - 优先级简单：comment > string > number > keyword > function；正则按这个顺序前缀
///   匹配，先击中先归类。
///
/// 这是 v0.3 预览框 redesign 的**视觉层补丁**，原型规格里 code 块需要彩色 token。等
/// 哪天真的要做 IDE 级渲染再换 tree-sitter / Splash。
enum SyntaxHighlighter {

    /// 五种 token 颜色。light / dark 各一份，跟原型 CSS `--t-kw / --t-str / --t-num / --t-com / --t-fn` 一一对应。
    struct Palette {
        let keyword: Color
        let string: Color
        let number: Color
        let comment: Color
        let function: Color
        let plain: Color

        static func mono(_ scheme: ColorScheme) -> Palette {
            scheme == .dark
                ? Palette(
                    keyword:  Color(red: 0.79, green: 0.54, blue: 1.00),  // #c98aff
                    string:   Color(red: 0.88, green: 0.64, blue: 0.42),  // #e0a36b
                    number:   Color(red: 0.52, green: 0.78, blue: 0.64),  // #84c8a3
                    comment:  Color(red: 0.95, green: 0.95, blue: 0.96).opacity(0.36),
                    function: Color(red: 0.51, green: 0.71, blue: 1.00),  // #82b6ff
                    plain:    Color(red: 0.95, green: 0.95, blue: 0.96)
                )
                : Palette(
                    keyword:  Color(red: 0.54, green: 0.25, blue: 0.80),  // #8a3ffc
                    string:   Color(red: 0.72, green: 0.46, blue: 0.18),  // #b8762f
                    number:   Color(red: 0.16, green: 0.44, blue: 0.23),  // #2a6f3a
                    comment:  Color(red: 0.11, green: 0.11, blue: 0.12).opacity(0.40),
                    function: Color(red: 0.10, green: 0.29, blue: 0.55),  // #1a4a8c
                    plain:    Color(red: 0.11, green: 0.11, blue: 0.12)
                )
        }
    }

    /// 把源码渲染成带颜色和等宽字体的 `AttributedString`。
    /// - Parameters:
    ///   - source: 完整源码（带换行）。
    ///   - language: 语言提示，影响关键字集合；nil / 未识别时退回 "common"。
    ///   - palette: 颜色面板（调用方按 `colorScheme` 选）。
    ///   - fontSize: 字号。
    static func highlight(
        _ source: String,
        language: String?,
        palette: Palette,
        fontSize: CGFloat = 12
    ) -> AttributedString {
        var attr = AttributedString(source)
        let baseFont = Font.system(size: fontSize, design: .monospaced)
        attr.font = baseFont
        attr.foregroundColor = palette.plain

        // ⚠️ 用 NSRange 跑正则，再 mapping 回 AttributedString.Index。
        let nsSource = source as NSString
        let fullRange = NSRange(location: 0, length: nsSource.length)

        // 标记位图：避免高优先级 token（comment/string）被低优先级（keyword/number）覆盖。
        var consumed = [Bool](repeating: false, count: nsSource.length)

        // 1. 注释（最高优先级）
        for pattern in commentPatterns {
            apply(
                pattern: pattern,
                in: nsSource,
                range: fullRange,
                consumed: &consumed,
                attr: &attr,
                color: palette.comment,
                italic: true,
                fontSize: fontSize
            )
        }

        // 2. 字符串
        for pattern in stringPatterns {
            apply(
                pattern: pattern,
                in: nsSource,
                range: fullRange,
                consumed: &consumed,
                attr: &attr,
                color: palette.string,
                italic: false,
                fontSize: fontSize
            )
        }

        // 3. 数字
        apply(
            pattern: numberPattern,
            in: nsSource,
            range: fullRange,
            consumed: &consumed,
            attr: &attr,
            color: palette.number,
            italic: false,
            fontSize: fontSize
        )

        // 4. 关键字
        let keywords = keywordSet(for: language)
        if !keywords.isEmpty {
            let kwPattern = "\\b(" + keywords.joined(separator: "|") + ")\\b"
            apply(
                pattern: kwPattern,
                in: nsSource,
                range: fullRange,
                consumed: &consumed,
                attr: &attr,
                color: palette.keyword,
                italic: false,
                fontSize: fontSize,
                bold: true
            )
        }

        // 5. 函数名（标识符 + 紧跟 `(`）
        apply(
            pattern: functionPattern,
            in: nsSource,
            range: fullRange,
            consumed: &consumed,
            attr: &attr,
            color: palette.function,
            italic: false,
            fontSize: fontSize,
            captureGroup: 1
        )

        return attr
    }

    // MARK: - Patterns

    /// 行注释 `// ... \n` / `# ... \n` 与块注释 `/* ... */`（非贪婪）。
    private static let commentPatterns: [String] = [
        "//[^\\n]*",
        "#[^\\n]*",
        "/\\*[\\s\\S]*?\\*/"
    ]

    /// 单/双/反引号包裹，含转义字符。HEREDOC 和模板字符串内插不处理。
    private static let stringPatterns: [String] = [
        "\"(?:\\\\.|[^\"\\\\])*\"",
        "'(?:\\\\.|[^'\\\\])*'",
        "`(?:\\\\.|[^`\\\\])*`"
    ]

    private static let numberPattern = "\\b\\d+(?:\\.\\d+)?\\b"
    /// 标识符紧跟左括号 — 简化的"函数调用 / 函数声明"判断。
    private static let functionPattern = "\\b([A-Za-z_][A-Za-z0-9_]*)(?=\\()"

    // MARK: - Keyword sets

    private static func keywordSet(for language: String?) -> [String] {
        let lang = (language ?? "").lowercased()
        switch lang {
        case "swift":
            return swiftKeywords
        case "js", "javascript", "ts", "typescript", "tsx", "jsx":
            return jsKeywords
        case "py", "python":
            return pythonKeywords
        case "sql":
            return sqlKeywords
        case "sh", "bash", "zsh", "shell":
            return bashKeywords
        case "":
            return commonKeywords
        default:
            return commonKeywords
        }
    }

    private static let swiftKeywords = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
        "func", "import", "init", "inout", "internal", "let", "open", "operator",
        "private", "protocol", "public", "rethrows", "static", "struct",
        "subscript", "typealias", "var", "break", "case", "continue", "default",
        "defer", "do", "else", "fallthrough", "for", "guard", "if", "in",
        "repeat", "return", "switch", "where", "while", "as", "Any", "catch",
        "false", "is", "nil", "self", "Self", "super", "throw", "throws", "true",
        "try", "some", "async", "await", "actor"
    ]

    private static let jsKeywords = [
        "abstract", "async", "await", "break", "case", "catch", "class", "const",
        "continue", "debugger", "default", "delete", "do", "else", "enum",
        "export", "extends", "false", "finally", "for", "from", "function", "if",
        "implements", "import", "in", "instanceof", "interface", "let", "new",
        "null", "of", "private", "protected", "public", "return", "static",
        "super", "switch", "this", "throw", "true", "try", "type", "typeof",
        "undefined", "var", "void", "while", "with", "yield", "as", "readonly"
    ]

    private static let pythonKeywords = [
        "False", "None", "True", "and", "as", "assert", "async", "await", "break",
        "class", "continue", "def", "del", "elif", "else", "except", "finally",
        "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal",
        "not", "or", "pass", "raise", "return", "try", "while", "with", "yield"
    ]

    private static let sqlKeywords = [
        "SELECT", "FROM", "WHERE", "GROUP", "BY", "ORDER", "HAVING", "LIMIT",
        "OFFSET", "JOIN", "LEFT", "RIGHT", "INNER", "OUTER", "ON", "AS", "AND",
        "OR", "NOT", "IN", "IS", "NULL", "INSERT", "INTO", "VALUES", "UPDATE",
        "SET", "DELETE", "CREATE", "TABLE", "DROP", "ALTER", "INDEX", "PRIMARY",
        "KEY", "FOREIGN", "REFERENCES", "DEFAULT", "UNIQUE", "WITH",
        "select", "from", "where", "group", "by", "order", "having", "limit",
        "offset", "join", "left", "right", "inner", "outer", "on", "as", "and",
        "or", "not", "in", "is", "null", "insert", "into", "values", "update",
        "set", "delete", "create", "table", "drop", "alter", "index", "primary",
        "key", "foreign", "references", "default", "unique", "with"
    ]

    private static let bashKeywords = [
        "if", "then", "else", "elif", "fi", "for", "do", "done", "while", "until",
        "case", "esac", "in", "function", "return", "break", "continue", "exit",
        "export", "local", "readonly", "set", "unset", "declare", "echo"
    ]

    /// 多语言通用关键字 — 不知道语言时用，命中率高过空集合。
    private static let commonKeywords = Array(
        Set(swiftKeywords + jsKeywords + pythonKeywords + bashKeywords)
    )

    // MARK: - Apply helper

    /// 跑一条正则 → 给所有匹配段染色。`consumed` 标记位图避免重复染色。
    private static func apply(
        pattern: String,
        in source: NSString,
        range: NSRange,
        consumed: inout [Bool],
        attr: inout AttributedString,
        color: Color,
        italic: Bool,
        fontSize: CGFloat,
        bold: Bool = false,
        captureGroup: Int = 0
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return }
        let matches = regex.matches(in: source as String, options: [], range: range)
        for match in matches {
            let r = match.range(at: captureGroup)
            guard r.location != NSNotFound, r.length > 0 else { continue }
            // 检查是否已被高优先级 token 占用
            var alreadyConsumed = false
            for i in r.location..<min(r.location + r.length, consumed.count) where consumed[i] {
                alreadyConsumed = true; break
            }
            if alreadyConsumed { continue }
            for i in r.location..<min(r.location + r.length, consumed.count) {
                consumed[i] = true
            }
            // NSRange → AttributedString.Index
            guard let swiftRange = Range(r, in: source as String) else { continue }
            guard let attrRange = Range(swiftRange, in: attr) else { continue }
            attr[attrRange].foregroundColor = color
            var f = Font.system(size: fontSize, design: .monospaced)
            if bold { f = f.weight(.semibold) }
            if italic { f = f.italic() }
            attr[attrRange].font = f
        }
    }
}
