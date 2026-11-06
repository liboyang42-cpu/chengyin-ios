"""Fail-closed source evidence extraction, not Swift parsing/typechecking or UI execution.
Only explicitly recognized straight-line shutdown statements and rendered catalog routes are accepted.
Never mutates source text, unittest assertions, catalog bytes or the application's behavior.
"""
import re

def require(condition, message):
    if not condition:
        raise AssertionError(message)

def uncomment(source):
    # Preserve quoted string contents. Reject unterminated lexical constructs rather than inventing evidence.
    pattern = re.compile(r'"(?:\\.|[^"\\])*"|//[^\n]*|/\*.*?\*/', re.S)
    return pattern.sub(lambda m: m.group(0) if m.group(0).startswith('"') else ' ', source)

def body(source, declaration):
    source = uncomment(source)
    require(source.count(declaration) == 1, 'Ambiguous or missing declaration: ' + declaration)
    start = source.index('{', source.index(declaration)) + 1
    depth = 1; quoted = False; escaped = False
    for i in range(start, len(source)):
        c = source[i]
        if quoted:
            if escaped: escaped = False
            elif c == '\\': escaped = True
            elif c == '"': quoted = False
            continue
        if c == '"': quoted = True
        elif c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0: return source[start:i]
    raise AssertionError('Unterminated body: ' + declaration)

def shutdown_operations(host):
    driver = body(host, 'final class PersonalLocationShareCoreLocationDriver:')
    stop = body(driver, 'func stop()')
    # No nested branch, deferred closure, Task, return, await or expression may masquerade as straight-line cleanup.
    statements = [re.sub(r'\s*=\s*', ' = ', re.sub(r'\s+', ' ', x.strip())) for x in re.split(r';|\n', stop) if x.strip()]
    required = ['manager.stopUpdatingLocation()', 'manager.allowsBackgroundLocationUpdates = false',
                'manager.showsBackgroundLocationIndicator = false', 'manager.delegate = nil',
                'onLocation = nil', 'onAuthorization = nil', 'onFailure = nil']
    require(statements == required, 'Shutdown must be the exact synchronous stop/reset/retirement sequence')
    provider = body(host, 'final class PersonalLocationShareCoreLocationProvider:')
    finish = body(provider, 'private func finish(_ result:')
    require(finish.index('driver?.stop(); driver = nil') < finish.index('reply?.resume(with: result)'),
            'Driver shutdown must precede continuation resume')
    # Normalized evidence consists of the two ACTUAL parsed statements, not inserted Swift source.
    return '; '.join(x for x in statements if x in [required[0], required[3]])

def literal_keys(source):
    return set(re.findall(r'"(personalLocationShare\.[^"\n]+)"', uncomment(source)))

def rendered_catalog(view, coordinator, host, catalog):
    strings = catalog['strings']
    view_code = uncomment(view); core = uncomment(coordinator); host_code = uncomment(host)
    localized = body(view_code, 'private func localized(')
    require('table: "PersonalLocationShare", locale: locale' in localized, 'Wrong/missing dedicated catalog or locale')
    display = body(view_code, 'private var statusMessage:')
    for marker in ['coordinator.messageParts.map { part in', 'guard let key = part.key else { return part.fallback }',
                   'let format = localized(key)', 'part.arguments.map { $0 as CVarArg }']:
        require(marker in display, 'Broken structured status renderer: ' + marker)
    require('Text(statusMessage)' in view_code, 'Structured status is not displayed')
    require('Self.presentation(for: message)' in body(core, 'public var messageParts:'), 'Message projection is disconnected')
    presentation = body(core, 'public static func presentation(for message:')
    require('default: key = nil' in presentation and
            'return [.init(key: nil, arguments: [], fallback: base)] + trailing' in presentation,
            'Unknown future status must remain fallback, never a fake success')
    require('if let key { return [.init(key: key, arguments: [], fallback: base)] + trailing }' in presentation,
            'Known status mapping is disconnected from MessagePart output')
    # Recognize only actual mapping positions: switch key assignments, suffix tuple keys and parameterized output.
    mapped = set(re.findall(r'\bkey\s*=\s*"(personalLocationShare\.[^"]+)"', presentation))
    mapped |= set(re.findall(r'\(\s*"(?:\\.|[^"\\])*"\s*,\s*"(personalLocationShare\.[^"]+)"\s*\)', presentation))
    mapped |= set(re.findall(r'\.init\(key:\s*"(personalLocationShare\.[^"]+)"', presentation))
    require('base.hasSuffix($0.0)' in presentation and 'trailing.insert(.init(key: suffix.1' in presentation,
            'Suffix mapping is disconnected')
    require('if Int(status) != nil' in presentation and 'arguments: [status]' in presentation,
            'Parameterized rejection is disconnected')
    # Direct View keys include title/switch projections that flow through the local localized() helper.
    direct = literal_keys(view_code) & strings.keys()
    unavailable = body(host_code, 'private struct PersonalLocationShareUnavailableView:')
    host_keys = set(re.findall(r'Text\("(personalLocationShare\.[^"]+)",\s*tableName:\s*"PersonalLocationShare"\)', unavailable))
    require('PersonalLocationShareUnavailableView()' in host_code, 'Unavailable destination has no entry')
    rendered = direct | mapped | host_keys
    require(rendered <= strings.keys(), 'Rendered key is missing from catalog: ' + str(rendered - strings.keys()))
    values = []
    for key in sorted(rendered):
        for language in ['en', 'zh-Hans']:
            unit = strings[key].get('localizations', {}).get(language, {}).get('stringUnit', {})
            require(unit.get('state') == 'translated' and isinstance(unit.get('value'), str) and unit['value'].strip(),
                    'Missing translated content: ' + key + '/' + language)
            values.append(unit['value'])
    for key in ['personalLocationShare.disclosure.summary', 'personalLocationShare.confirmationSummary', 'personalLocationShare.coarse']:
        require(key in direct, 'Disclosure/precision key is no longer referenced by View: ' + key)
    for key, phrase in [('personalLocationShare.disclosure.summary', '设备最新位置会上传服务端'),
                        ('personalLocationShare.confirmationSummary', '设备最新位置会上传服务端'),
                        ('personalLocationShare.coarse', '服务端投影')]:
        require(phrase in strings[key]['localizations']['zh-Hans']['stringUnit']['value'],
                'Required disclosure removed from its actual surface: ' + key)
    return rendered, '\n'.join(values)
