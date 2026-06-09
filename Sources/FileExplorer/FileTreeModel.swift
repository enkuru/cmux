import Foundation
import SwiftUI

// MARK: - FileTreeNode

@MainActor
final class FileTreeNode: Identifiable, ObservableObject {
    let id = UUID()
    let name: String
    let path: String
    let depth: Int
    @Published var isExpanded: Bool = false
    @Published var children: [FileTreeNode]?  // nil = not yet loaded, [] = empty

    var isLoaded: Bool { children != nil }

    init(name: String, path: String, depth: Int) {
        self.name = name
        self.path = path
        self.depth = depth
    }
}

// MARK: - Git helpers

struct GitInfo: Equatable {
    let branch: String
    let changedFiles: [GitChangedFile]

    static func query(for path: String) -> GitInfo? {
        let branchResult = Self.runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: path)
        guard let branch = branchResult?.trimmingCharacters(in: .whitespacesAndNewlines),
              !branch.isEmpty else { return nil }

        let diffResult = Self.runGit(["diff", "--name-status", "HEAD"], in: path) ?? ""
        let untrackedResult = Self.runGit(["ls-files", "--others", "--exclude-standard"], in: path) ?? ""

        var files: [GitChangedFile] = []
        for line in diffResult.split(separator: "\n") where !line.isEmpty {
            let parts = line.split(separator: "\t", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let status: GitFileStatus
            switch parts[0].first {
            case "M": status = .modified
            case "A": status = .added
            case "D": status = .deleted
            case "R": status = .renamed
            default: status = .modified
            }
            files.append(GitChangedFile(name: String(parts[1]), status: status))
        }
        for line in untrackedResult.split(separator: "\n") where !line.isEmpty {
            files.append(GitChangedFile(name: String(line), status: .untracked))
        }

        return GitInfo(branch: branch, changedFiles: files)
    }

    /// Returns the unified diff for a single file, or the full file content for untracked files.
    static func fileDiff(for fileName: String, status: GitFileStatus, in directory: String) -> String {
        if status == .untracked {
            let fullPath = (directory as NSString).appendingPathComponent(fileName)
            return (try? String(contentsOfFile: fullPath, encoding: .utf8)) ?? ""
        }
        return runGit(["diff", "HEAD", "--", fileName], in: directory) ?? ""
    }

    /// Generates a self-contained HTML diff viewer with unified/split toggle,
    /// inline comments, per-hunk stage/revert, and auto-refresh.
    static func diffHTML(for fileName: String, status: GitFileStatus, in directory: String) -> String {
        let rawDiff = fileDiff(for: fileName, status: status, in: directory)
        let esc = { (s: String) -> String in
            s.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "'", with: "&#39;")
        }
        let escapedFileName = esc(fileName)
        let escapedDir = esc(directory)
        let statusLabel = status.symbol

        // Build JSON line data for JS to render both views
        var jsonLines: [[String: Any]] = []
        // Track raw diff lines per hunk for patch reconstruction
        var hunkIndex = -1
        var hunkRawLines: [[String]] = []

        if status == .untracked {
            let fileLines = rawDiff.split(separator: "\n", omittingEmptySubsequences: false)
            for (i, line) in fileLines.enumerated() {
                jsonLines.append(["type": "add", "content": String(line), "newNum": i + 1, "hunk": 0])
            }
            hunkRawLines.append(fileLines.map { "+\($0)" })
        } else {
            var oldNum = 0, newNum = 0
            var currentHunkHeader = ""
            for line in rawDiff.split(separator: "\n", omittingEmptySubsequences: false) {
                let s = String(line)
                if s.hasPrefix("@@") {
                    let parts = s.split(separator: " ")
                    if parts.count >= 3 {
                        let oldPart = String(parts[1]).dropFirst()
                        let newPart = String(parts[2]).dropFirst()
                        oldNum = Int(oldPart.split(separator: ",").first ?? "") ?? 0
                        newNum = Int(newPart.split(separator: ",").first ?? "") ?? 0
                    }
                    hunkIndex += 1
                    currentHunkHeader = s
                    hunkRawLines.append([s])
                    jsonLines.append(["type": "hunk", "content": s, "hunk": hunkIndex])
                } else if s.hasPrefix("---") || s.hasPrefix("+++") || s.hasPrefix("diff ") || s.hasPrefix("index ") {
                    continue
                } else if s.hasPrefix("+") {
                    jsonLines.append(["type": "add", "content": String(s.dropFirst()), "newNum": newNum, "hunk": hunkIndex])
                    if hunkIndex >= 0 { hunkRawLines[hunkIndex].append(s) }
                    newNum += 1
                } else if s.hasPrefix("-") {
                    jsonLines.append(["type": "del", "content": String(s.dropFirst()), "oldNum": oldNum, "hunk": hunkIndex])
                    if hunkIndex >= 0 { hunkRawLines[hunkIndex].append(s) }
                    oldNum += 1
                } else {
                    let content = s.hasPrefix(" ") ? String(s.dropFirst()) : s
                    jsonLines.append(["type": "ctx", "content": content, "oldNum": oldNum, "newNum": newNum, "hunk": hunkIndex])
                    if hunkIndex >= 0 { hunkRawLines[hunkIndex].append(s) }
                    oldNum += 1
                    newNum += 1
                }
            }
        }

        let jsonData = (try? JSONSerialization.data(withJSONObject: jsonLines)) ?? Data()
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"

        // Build hunk patches for per-hunk stage/revert
        var hunkPatches: [String] = []
        for lines in hunkRawLines {
            let patch = "--- a/\(fileName)\n+++ b/\(fileName)\n" + lines.joined(separator: "\n") + "\n"
            hunkPatches.append(patch)
        }
        let hunkPatchData = (try? JSONSerialization.data(withJSONObject: hunkPatches)) ?? Data()
        let hunkPatchJSON = String(data: hunkPatchData, encoding: .utf8) ?? "[]"

        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8"><title>\(escapedFileName)</title>
        <style>
        *{margin:0;padding:0;box-sizing:border-box}
        body{background:#0d1117;color:#e6edf3;font-family:ui-monospace,"SF Mono",Menlo,monospace;font-size:12px}
        .toolbar{position:sticky;top:0;z-index:10;background:#161b22;border-bottom:1px solid #30363d;padding:8px 16px;display:flex;align-items:center;gap:12px}
        .toolbar .filename{font-weight:600;font-size:13px;flex:1}.toolbar .badge{font-size:10px;font-weight:700;padding:2px 8px;border-radius:4px;color:#0d1117}
        .badge-M{background:#d29922}.badge-A,.badge-\\?{background:#3fb950}.badge-D{background:#f85149}.badge-R{background:#58a6ff}
        .toggle{display:flex;background:#21262d;border-radius:6px;overflow:hidden;border:1px solid #30363d}
        .toggle button{background:none;border:none;color:#8b949e;padding:4px 12px;font-size:11px;font-family:inherit;cursor:pointer}
        .toggle button.active{background:#30363d;color:#e6edf3}.toggle button:hover:not(.active){color:#c9d1d9}
        .diff-container{overflow-x:auto}
        .unified table,.split table{width:100%;border-collapse:collapse}
        .unified td{padding:0 12px;white-space:pre;vertical-align:top}
        .unified .ln{width:1px;color:#484f58;text-align:right;padding:0 8px;user-select:none;min-width:50px;border-right:1px solid #21262d}
        .unified .ln-old{border-right:none}
        .unified tr.add td,.split tr.add td{background:rgba(63,185,80,0.10)}
        .unified tr.add .code,.split tr.add .code{color:#aff5b4}
        .unified tr.del td,.split tr.del td{background:rgba(248,81,73,0.10)}
        .unified tr.del .code,.split tr.del .code{color:#ffa198}
        .unified tr.hunk td,.split tr.hunk td{background:rgba(56,139,253,0.08);color:#58a6ff;font-weight:600}
        .unified tr.ctx td,.split tr.ctx td{color:#8b949e}
        .split{display:flex;width:100%}.split .side{flex:1;overflow-x:auto;min-width:0}.split .side-old{border-right:1px solid #30363d}
        .split td{padding:0 8px;white-space:pre;vertical-align:top}
        .split .ln{width:1px;color:#484f58;text-align:right;padding:0 6px;user-select:none;min-width:40px;border-right:1px solid #21262d}
        .split tr.empty td{background:#161b22}
        .stats{font-size:11px;color:#8b949e}.stats .ac{color:#3fb950}.stats .dc{color:#f85149}
        /* Hunk actions */
        .hunk-actions{display:inline-flex;gap:4px;margin-left:12px;vertical-align:middle}
        tr.hunk td.code{white-space:nowrap}
        .hunk-btn{background:#21262d;border:1px solid #30363d;color:#8b949e;padding:1px 8px;border-radius:4px;font-size:10px;cursor:pointer;font-family:inherit}
        .hunk-btn:hover{background:#30363d;color:#e6edf3}.hunk-btn.stage{border-color:#238636}.hunk-btn.stage:hover{background:#238636;color:#fff}
        .hunk-btn.revert{border-color:#da3633}.hunk-btn.revert:hover{background:#da3633;color:#fff}
        /* Inline comments */
        tr.comment-row td{background:#1c2128;padding:8px 12px;border-top:1px solid #30363d;border-bottom:1px solid #30363d}
        .comment-box{display:flex;gap:8px;align-items:flex-start}
        .comment-input{flex:1;background:#0d1117;border:1px solid #30363d;border-radius:6px;color:#e6edf3;padding:6px 10px;font-family:inherit;font-size:11px;resize:vertical;min-height:32px}
        .comment-input:focus{border-color:#58a6ff;outline:none}
        .comment-submit{background:#238636;border:none;color:#fff;padding:6px 12px;border-radius:6px;font-size:11px;cursor:pointer;font-family:inherit}
        .comment-submit:hover{background:#2ea043}
        .comment-cancel{background:none;border:1px solid #30363d;color:#8b949e;padding:6px 12px;border-radius:6px;font-size:11px;cursor:pointer;font-family:inherit}
        .saved-comment{background:#1c2128;border:1px solid #30363d;border-radius:6px;padding:6px 10px;margin-top:4px;font-size:11px;color:#c9d1d9}
        .saved-comment .meta{color:#484f58;font-size:10px;margin-bottom:2px}
        .comment-gutter{width:16px;text-align:center;user-select:none;cursor:pointer;opacity:0;font-size:10px;color:#58a6ff;padding:0 2px !important}
        tr:hover .comment-gutter{opacity:0.5}
        .comment-gutter:hover{opacity:1 !important}
        .comment-gutter.has{opacity:0.7;color:#d29922}
        /* Toast */
        .toast{position:fixed;bottom:20px;right:20px;background:#238636;color:#fff;padding:8px 16px;border-radius:8px;font-size:12px;opacity:0;transition:opacity .3s;z-index:100;pointer-events:none}
        .toast.show{opacity:1}
        .toast.error{background:#da3633}
        /* Live indicator */
        .live-dot{width:6px;height:6px;border-radius:50%;background:#3fb950;display:inline-block;animation:pulse 2s infinite}
        @keyframes pulse{0%,100%{opacity:1}50%{opacity:.4}}
        </style></head>
        <body>
        <div class="toolbar">
            <span class="badge badge-\(statusLabel)">\(statusLabel)</span>
            <span class="filename">\(escapedFileName)</span>
            <span class="stats" id="stats"></span>
            <span class="live-dot" title="Auto-refreshing"></span>
            <div class="toggle">
                <button id="btn-unified" class="active" onclick="setView('unified')">Unified</button>
                <button id="btn-split" onclick="setView('split')">Split</button>
            </div>
        </div>
        <div class="diff-container" id="diff"></div>
        <div class="toast" id="toast"></div>
        <script>
        const FILE='\(escapedFileName)',DIR='\(escapedDir)',STATUS='\(statusLabel)';
        const lines=\(jsonString);
        const hunkPatches=\(hunkPatchJSON);
        let currentView=localStorage.getItem('cmux-view')||'unified',comments={};
        try{comments=JSON.parse(localStorage.getItem('cmux-comments-'+FILE)||'{}');}catch(e){}

        function esc(s){return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');}
        function toast(msg,err){const t=document.getElementById('toast');t.textContent=msg;t.className='toast'+(err?' error':'')+' show';setTimeout(()=>t.className='toast',2000);}

        function msg(data){
            if(window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.cmuxDiff){
                window.webkit.messageHandlers.cmuxDiff.postMessage(data);return true;
            }return false;
        }

        function stageHunk(i){if(msg({action:'stageHunk',patch:hunkPatches[i],directory:DIR,file:FILE}))toast('Hunk staged');else toast('Bridge unavailable',true);}
        function revertHunk(i){if(msg({action:'revertHunk',patch:hunkPatches[i],directory:DIR,file:FILE}))toast('Hunk reverted');else toast('Bridge unavailable',true);}

        function addComment(lineKey){
            const existing=document.getElementById('comment-form-'+lineKey);
            if(existing){existing.remove();return;}
            const row=document.getElementById('line-'+lineKey);
            if(!row)return;
            const tr=document.createElement('tr');tr.className='comment-row';tr.id='comment-form-'+lineKey;
            const saved=comments[lineKey]||[];
            let savedHtml=saved.map(c=>'<div class="saved-comment"><div class="meta">'+esc(c.time)+'</div>'+esc(c.text)+'</div>').join('');
            tr.innerHTML='<td colspan="4"><div>'+savedHtml+'</div><div class="comment-box"><textarea class="comment-input" id="ci-'+lineKey+'" placeholder="Add a comment..." rows="1"></textarea><button class="comment-submit" onclick="saveComment(\\''+lineKey+'\\')">Comment</button><button class="comment-cancel" onclick="document.getElementById(\\'comment-form-'+lineKey+'\\').remove()">Cancel</button></div></td>';
            row.after(tr);
            document.getElementById('ci-'+lineKey).focus();
        }

        function saveComment(lineKey){
            const input=document.getElementById('ci-'+lineKey);
            if(!input||!input.value.trim())return;
            if(!comments[lineKey])comments[lineKey]=[];
            comments[lineKey].push({text:input.value.trim(),time:new Date().toLocaleTimeString()});
            localStorage.setItem('cmux-comments-'+FILE,JSON.stringify(comments));
            addComment(lineKey);addComment(lineKey);// close and reopen to refresh
        }

        function renderStats(){
            let a=lines.filter(l=>l.type==='add').length,d=lines.filter(l=>l.type==='del').length;
            document.getElementById('stats').innerHTML='<span class="ac">+'+a+'</span> / <span class="dc">-'+d+'</span>';
        }

        function commentGutter(lineKey){
            const has=comments[lineKey]&&comments[lineKey].length>0;
            return '<td class="comment-gutter'+(has?' has':'')+'" onclick="addComment(\\''+lineKey+'\\')">&#9655;</td>';
        }

        function hunkActions(i){
            if(i<0||i>=hunkPatches.length)return'';
            return '<span class="hunk-actions"><button class="hunk-btn stage" onclick="stageHunk('+i+')">Stage</button><button class="hunk-btn revert" onclick="revertHunk('+i+')">Revert</button></span>';
        }

        function renderUnified(){
            let h='<div class="unified"><table>';
            for(const l of lines){
                const lk=(l.oldNum||'')+'_'+(l.newNum||'');
                if(l.type==='hunk'){
                    h+='<tr class="hunk" id="line-h'+l.hunk+'"><td class="ln" colspan="2"></td><td colspan="2" class="code" style="padding:6px 12px">'+esc(l.content)+hunkActions(l.hunk)+'</td></tr>';
                }else if(l.type==='add'){
                    h+='<tr class="add" id="line-'+lk+'"><td class="ln ln-old"></td><td class="ln">'+(l.newNum||'')+'</td>'+commentGutter(lk)+'<td class="code">+'+esc(l.content)+'</td></tr>';
                }else if(l.type==='del'){
                    h+='<tr class="del" id="line-'+lk+'"><td class="ln ln-old">'+(l.oldNum||'')+'</td><td class="ln"></td>'+commentGutter(lk)+'<td class="code">-'+esc(l.content)+'</td></tr>';
                }else{
                    h+='<tr class="ctx" id="line-'+lk+'"><td class="ln ln-old">'+(l.oldNum||'')+'</td><td class="ln">'+(l.newNum||'')+'</td>'+commentGutter(lk)+'<td class="code"> '+esc(l.content)+'</td></tr>';
                }
            }
            h+='</table></div>';return h;
        }

        function renderSplit(){
            let pairs=[],i=0;
            while(i<lines.length){const l=lines[i];
                if(l.type==='hunk'){pairs.push({type:'hunk',content:l.content,hunk:l.hunk});i++;}
                else if(l.type==='del'){let ds=[],as=[];while(i<lines.length&&lines[i].type==='del'){ds.push(lines[i]);i++;}while(i<lines.length&&lines[i].type==='add'){as.push(lines[i]);i++;}let m=Math.max(ds.length,as.length);for(let j=0;j<m;j++)pairs.push({type:'pair',old:ds[j]||null,new:as[j]||null});}
                else if(l.type==='add'){pairs.push({type:'pair',old:null,new:l});i++;}
                else{pairs.push({type:'ctx',old:l,new:l});i++;}
            }
            let oh='<table>',nh='<table>';
            for(const p of pairs){
                if(p.type==='hunk'){
                    oh+='<tr class="hunk"><td class="ln"></td><td class="code" style="padding:4px 8px">'+esc(p.content)+hunkActions(p.hunk)+'</td></tr>';
                    nh+='<tr class="hunk"><td class="ln"></td><td class="code" style="padding:4px 8px">'+esc(p.content)+'</td></tr>';
                }else if(p.type==='ctx'){
                    oh+='<tr class="ctx"><td class="ln">'+(p.old.oldNum||'')+'</td><td class="code">'+esc(p.old.content)+'</td></tr>';
                    nh+='<tr class="ctx"><td class="ln">'+(p.new.newNum||'')+'</td><td class="code">'+esc(p.new.content)+'</td></tr>';
                }else{
                    if(p.old) oh+='<tr class="del"><td class="ln">'+(p.old.oldNum||'')+'</td><td class="code">'+esc(p.old.content)+'</td></tr>';
                    else oh+='<tr class="empty"><td class="ln"></td><td class="code"></td></tr>';
                    if(p.new) nh+='<tr class="add"><td class="ln">'+(p.new.newNum||'')+'</td><td class="code">'+esc(p.new.content)+'</td></tr>';
                    else nh+='<tr class="empty"><td class="ln"></td><td class="code"></td></tr>';
                }
            }
            oh+='</table>';nh+='</table>';
            return '<div class="split"><div class="side side-old">'+oh+'</div><div class="side side-new">'+nh+'</div></div>';
        }

        function setView(v){
            currentView=v;localStorage.setItem('cmux-view',v);
            document.getElementById('btn-unified').classList.toggle('active',v==='unified');
            document.getElementById('btn-split').classList.toggle('active',v==='split');
            document.getElementById('diff').innerHTML=v==='unified'?renderUnified():renderSplit();
            if(v==='split'){const s=document.querySelectorAll('.split .side');if(s.length===2){s[0].onscroll=()=>{s[1].scrollTop=s[0].scrollTop};s[1].onscroll=()=>{s[0].scrollTop=s[1].scrollTop};}}
        }

        renderStats();setView(currentView);

        // Live refresh: reload page every 3s to pick up file changes
        setInterval(()=>{location.reload();},3000);
        </script></body></html>
        """
    }

    private static func runGit(_ args: [String], in directory: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        task.arguments = args
        task.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}

enum GitFileStatus: Equatable {
    case modified, added, deleted, renamed, untracked

    var symbol: String {
        switch self {
        case .modified: return "M"
        case .added: return "A"
        case .deleted: return "D"
        case .renamed: return "R"
        case .untracked: return "?"
        }
    }
}

struct GitChangedFile: Equatable, Identifiable {
    let name: String
    let status: GitFileStatus
    var id: String { name }
}

// MARK: - Flat entry for ForEach rendering

enum FileTreeEntryKind: Equatable {
    case folder(isExpanded: Bool, hasChildren: Bool, sessionCount: Int, gitBranch: String?)
    case session(workspaceId: UUID, title: String, status: AgentStatus, summary: String?)
    case changedFile(file: GitChangedFile, projectPath: String)
}

struct FileTreeEntry: Identifiable, Equatable {
    let id: String  // node.path for folders, workspace UUID string for sessions
    let name: String
    let path: String
    let depth: Int
    let kind: FileTreeEntryKind
}

// MARK: - FileTreeModel

@MainActor
final class FileTreeModel: ObservableObject {
    @Published var rootPath: String
    @Published private(set) var rootNode: FileTreeNode?
    /// Paths the user explicitly collapsed — auto-expand won't override these
    var manuallyCollapsed: Set<String> = []
    /// Cached git info per directory (project root paths)
    @Published var gitInfoCache: [String: GitInfo] = [:]

    /// When non-nil, the folder tree is filtered to these paths (folders whose name
    /// matches the active query, plus their ancestor folders). nil means no active search.
    @Published private(set) var searchMatchPaths: Set<String>? = nil

    var visibleHiddenFolders: Set<String> {
        let raw = UserDefaults.standard.string(forKey: "fileExplorerVisibleHiddenFolders") ?? ""
        return Set(raw.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty })
    }

    private static let excludedDirectories: Set<String> = [
        ".git", ".build", "node_modules", ".gradle", "target",
        "__pycache__", ".idea", ".vscode", ".DS_Store", "build",
        "Pods", ".svn", ".hg", "DerivedData", ".swiftpm"
    ]

    init(rootPath: String) {
        let expanded = (rootPath as NSString).expandingTildeInPath
        self.rootPath = expanded
    }

    func loadRoot() {
        let url = URL(fileURLWithPath: rootPath)
        let name = url.lastPathComponent
        let node = FileTreeNode(name: name, path: rootPath, depth: 0)
        loadChildren(for: node)
        node.isExpanded = true
        rootNode = node
    }

    func toggleExpansion(_ node: FileTreeNode) {
        if !node.isLoaded {
            loadChildren(for: node)
        }
        node.isExpanded.toggle()
        if node.isExpanded {
            manuallyCollapsed.remove(node.path)
        } else {
            manuallyCollapsed.insert(node.path)
        }
        objectWillChange.send()
    }

    func refresh() {
        guard let root = rootNode else {
            loadRoot()
            return
        }
        refreshNode(root)
        objectWillChange.send()
    }

    /// Refresh git info for all session directories (runs git off-main via Task)
    func refreshGitInfo(for workspaces: [WorkspaceDirectoryInfo]) {
        let directories = Array(Set(workspaces.map { ($0.directory as NSString).standardizingPath }))
        Task.detached { [weak self] in
            var newCache: [String: GitInfo] = [:]
            for dir in directories {
                if let info = GitInfo.query(for: dir) {
                    newCache[dir] = info
                }
            }
            await MainActor.run {
                guard let self else { return }
                if self.gitInfoCache != newCache {
                    self.gitInfoCache = newCache
                }
            }
        }
    }


    // MARK: - Auto-expand for active sessions

    /// Expands folders that contain active sessions, unless the user manually collapsed them.
    /// Lazily loads children along the path as needed.
    func autoExpandForSessions(_ workspaces: [WorkspaceDirectoryInfo]) {
        guard let root = rootNode else { return }
        let sessionPaths = Set(workspaces.map { ($0.directory as NSString).standardizingPath })
        guard !sessionPaths.isEmpty else { return }
        var changed = false
        for sessionPath in sessionPaths {
            changed = expandPathToNode(sessionPath, from: root) || changed
        }
        if changed {
            objectWillChange.send()
        }
    }

    /// Walks from root toward `targetPath`, expanding each ancestor that isn't manually collapsed.
    /// Returns true if any node was expanded.
    private func expandPathToNode(_ targetPath: String, from node: FileTreeNode) -> Bool {
        let normalizedTarget = (targetPath as NSString).standardizingPath
        let normalizedNode = (node.path as NSString).standardizingPath

        // Check if target is at or under this node
        guard normalizedTarget == normalizedNode || normalizedTarget.hasPrefix(normalizedNode + "/") else {
            return false
        }

        // Don't auto-expand if user manually collapsed
        guard !manuallyCollapsed.contains(node.path) else { return false }

        var changed = false

        if !node.isExpanded {
            if !node.isLoaded { loadChildren(for: node) }
            node.isExpanded = true
            changed = true
        }

        // Recurse into children to expand deeper
        if normalizedTarget != normalizedNode, let children = node.children {
            for child in children {
                changed = expandPathToNode(targetPath, from: child) || changed
            }
        }

        return changed
    }

    /// Returns the number of active sessions whose directory matches this folder path.
    func sessionCount(for folderPath: String, in workspaces: [WorkspaceDirectoryInfo]) -> Int {
        let normalized = (folderPath as NSString).standardizingPath
        return workspaces.filter { ($0.directory as NSString).standardizingPath == normalized }.count
    }

    // MARK: - Flat visible nodes

    func flatVisibleEntries(workspaces: [WorkspaceDirectoryInfo], showAllSessions: Bool) -> [FileTreeEntry] {
        if let matchPaths = searchMatchPaths {
            return searchEntries(matchPaths: matchPaths)
        }
        guard let root = rootNode else { return [] }
        var entries: [FileTreeEntry] = []
        appendEntries(for: root, into: &entries, workspaces: workspaces, showAllSessions: showAllSessions)
        return entries
    }

    /// Recompute the folder filter for `query`. An empty query clears the filter. The
    /// filesystem scan runs off the main actor and is bounded for responsiveness.
    func runSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if searchMatchPaths != nil { searchMatchPaths = nil }
            return
        }
        let root = (rootPath as NSString).standardizingPath
        let needleSegments = trimmed.lowercased()
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !needleSegments.isEmpty else {
            if searchMatchPaths != nil { searchMatchPaths = nil }
            return
        }
        let hidden = visibleHiddenFolders
        let matches = await Task.detached(priority: .userInitiated) {
            FileTreeModel.scanMatchingFolders(root: root, needleSegments: needleSegments, visibleHidden: hidden)
        }.value
        if Task.isCancelled { return }
        var paths: Set<String> = [root]
        for match in matches {
            paths.insert(match)
            var parent = (match as NSString).deletingLastPathComponent
            while parent.count > root.count, parent.hasPrefix(root) {
                paths.insert(parent)
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        searchMatchPaths = paths
    }

    /// Bounded recursive scan for folders matching `needleSegments` (case-insensitive,
    /// path-aware), honoring the same exclusions as the tree. Runs off-main.
    nonisolated private static func scanMatchingFolders(
        root: String,
        needleSegments: [String],
        visibleHidden: Set<String>,
        maxDepth: Int = 8,
        maxResults: Int = 500,
        maxVisited: Int = 15000
    ) -> Set<String> {
        guard !needleSegments.isEmpty else { return [] }
        let fm = FileManager.default
        var results: Set<String> = []
        // Breadth-first (FIFO via a head index) so shallow folders — e.g. project dirs a
        // couple levels under the root — are reached before the visit budget is spent
        // diving deep into one large subtree (e.g. ~/Library).
        var queue: [(path: String, components: [String], depth: Int)] = [(root, [], 0)]
        var head = 0
        while head < queue.count {
            if results.count >= maxResults || head >= maxVisited { break }
            let (dir, components, depth) = queue[head]
            head += 1
            guard depth < maxDepth else { continue }
            guard let contents = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: dir),
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            ) else { continue }
            for url in contents {
                let name = url.lastPathComponent
                if excludedDirectories.contains(name) { continue }
                if name.hasPrefix(".") && !visibleHidden.contains(name) { continue }
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDirectory else { continue }
                let childComponents = components + [name.lowercased()]
                if pathMatches(components: childComponents, needleSegments: needleSegments) {
                    results.insert(url.path)
                }
                queue.append((url.path, childComponents, depth + 1))
            }
        }
        return results
    }

    /// Matches when each needle segment is a substring of a distinct path component in
    /// order, and the final segment matches the folder's own name. So "wamo/pos" matches a
    /// folder named "*pos*" living under an ancestor named "*wamo*"; a single "pos" matches
    /// any folder named "*pos*". Components are expected pre-lowercased.
    nonisolated private static func pathMatches(components: [String], needleSegments: [String]) -> Bool {
        guard let lastSegment = needleSegments.last, let lastComponent = components.last else {
            return false
        }
        guard lastComponent.contains(lastSegment) else { return false }
        let priorSegments = needleSegments.dropLast()
        if priorSegments.isEmpty { return true }
        var index = 0
        let ancestors = components.dropLast()
        for segment in priorSegments {
            var found = false
            while index < ancestors.count {
                let component = ancestors[index]
                index += 1
                if component.contains(segment) {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }

    private func searchEntries(matchPaths: Set<String>) -> [FileTreeEntry] {
        let root = (rootPath as NSString).standardizingPath
        let parents = Set(matchPaths.map { ($0 as NSString).deletingLastPathComponent })
        var entries: [FileTreeEntry] = []
        for path in matchPaths.sorted() {
            let depth: Int
            if path == root {
                depth = 0
            } else if path.hasPrefix(root + "/") {
                depth = String(path.dropFirst(root.count + 1)).split(separator: "/").count
            } else {
                depth = (path as NSString).pathComponents.count
            }
            let name = (path as NSString).lastPathComponent
            let normalized = (path as NSString).standardizingPath
            entries.append(FileTreeEntry(
                id: path,
                name: name.isEmpty ? path : name,
                path: path,
                depth: depth,
                kind: .folder(
                    isExpanded: true,
                    hasChildren: parents.contains(path),
                    sessionCount: 0,
                    gitBranch: gitInfoCache[normalized]?.branch
                )
            ))
        }
        return entries
    }

    // MARK: - Private

    private func appendEntries(
        for node: FileTreeNode,
        into entries: inout [FileTreeEntry],
        workspaces: [WorkspaceDirectoryInfo],
        showAllSessions: Bool
    ) {
        let hasChildren = node.children?.isEmpty == false
        let count = sessionCount(for: node.path, in: workspaces)
        let normalizedPath = (node.path as NSString).standardizingPath
        let gitBranch = gitInfoCache[normalizedPath]?.branch

        entries.append(FileTreeEntry(
            id: node.path,
            name: node.name,
            path: node.path,
            depth: node.depth,
            kind: .folder(isExpanded: node.isExpanded, hasChildren: hasChildren, sessionCount: count, gitBranch: gitBranch)
        ))

        guard node.isExpanded else { return }

        // Show matching sessions under this folder
        if showAllSessions || node.isExpanded {
            let matching = workspaces.filter { normalizedPathMatch($0.directory, node.path) }
            for ws in matching {
                let wsNormalized = (ws.directory as NSString).standardizingPath
                // Enrich summary with changed file count from git cache
                let wsNorm = (ws.directory as NSString).standardizingPath
                let gitFileCount = gitInfoCache[wsNorm]?.changedFiles.count
                var enriched = ws
                if let count = gitFileCount, count > 0, ws.changedFileCount == nil {
                    enriched = WorkspaceDirectoryInfo(
                        id: ws.id, title: ws.title, directory: ws.directory,
                        hasUnread: ws.hasUnread, isSelected: ws.isSelected,
                        shellState: ws.shellState,
                        latestNotificationBody: ws.latestNotificationBody,
                        changedFileCount: count
                    )
                }

                entries.append(FileTreeEntry(
                    id: ws.id.uuidString,
                    name: ws.title,
                    path: node.path,
                    depth: node.depth + 1,
                    kind: .session(workspaceId: ws.id, title: ws.title, status: enriched.agentStatus, summary: enriched.statusSummary)
                ))
            }
        }

        // Recurse into children
        if let children = node.children {
            for child in children {
                appendEntries(for: child, into: &entries, workspaces: workspaces, showAllSessions: showAllSessions)
            }
        }
    }

    private func loadChildren(for node: FileTreeNode) {
        let url = URL(fileURLWithPath: node.path)
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: []
            )
            let directories = contents
                .filter { url in
                    let name = url.lastPathComponent
                    guard !Self.excludedDirectories.contains(name) else { return false }
                    if name.hasPrefix(".") && !visibleHiddenFolders.contains(name) {
                        return false
                    }
                    let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                    return values?.isDirectory == true
                }
                .sorted { a, b in
                    let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                    return dateA > dateB
                }
                .map { FileTreeNode(name: $0.lastPathComponent, path: $0.path, depth: node.depth + 1) }
            node.children = directories
        } catch {
            node.children = []
        }
    }

    func refreshTree() {
        guard let root = rootNode else { return }
        refreshNode(root)
        objectWillChange.send()
    }

    private func refreshNode(_ node: FileTreeNode) {
        guard node.isLoaded else { return }
        let oldExpanded = Set((node.children ?? []).filter { $0.isExpanded }.map { $0.path })
        loadChildren(for: node)
        // Restore expansion state
        for child in node.children ?? [] {
            if oldExpanded.contains(child.path) {
                child.isExpanded = true
                refreshNode(child)
            }
        }
    }

    private func normalizedPathMatch(_ directory: String, _ folderPath: String) -> Bool {
        let norm1 = (directory as NSString).standardizingPath
        let norm2 = (folderPath as NSString).standardizingPath
        return norm1 == norm2
    }
}

// MARK: - Agent status

enum AgentStatus: Equatable {
    case idle                    // Shell prompt, no command running
    case running                 // Command is executing
    case needsAttention          // Has unread notification (bell/OSC)
    case completed               // Agent finished (detected via title/output patterns)
    case errored                 // Agent errored (detected via title/output patterns)

    var label: String {
        switch self {
        case .idle: return String(localized: "agent.status.idle", defaultValue: "Idle")
        case .running: return String(localized: "agent.status.running", defaultValue: "Running")
        case .needsAttention: return String(localized: "agent.status.attention", defaultValue: "Needs Attention")
        case .completed: return String(localized: "agent.status.completed", defaultValue: "Completed")
        case .errored: return String(localized: "agent.status.errored", defaultValue: "Errored")
        }
    }

    var iconName: String {
        switch self {
        case .idle: return "circle"
        case .running: return "circle.dotted.circle"
        case .needsAttention: return "exclamationmark.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .errored: return "xmark.circle.fill"
        }
    }
}

// MARK: - Lightweight workspace info (avoids coupling to Workspace directly in model)

struct WorkspaceDirectoryInfo: Equatable {
    let id: UUID
    let title: String
    let directory: String
    let hasUnread: Bool
    let isSelected: Bool
    let shellState: String  // "idle", "running", or "unknown"
    let latestNotificationBody: String?
    let changedFileCount: Int?

    var agentStatus: AgentStatus {
        // Priority 1: unread notifications (only if not currently looking at it)
        if hasUnread && !isSelected { return .needsAttention }

        // Priority 2: real shell state from Ghostty/OSC 133
        switch shellState {
        case "running": return .running
        case "idle": return .idle
        default: break  // "unknown" — fall through to heuristics
        }

        // Priority 3: title-based heuristics (fallback for shells without integration)
        let lower = title.lowercased()
        if lower.contains("error") || lower.contains("failed") || lower.contains("panic") {
            return .errored
        }
        if lower.contains("completed") || lower.contains("done") || lower.contains("finished") {
            return .completed
        }
        let agentPatterns = ["claude", "codex", "aider", "cursor", "copilot"]
        if agentPatterns.contains(where: { lower.contains($0) }) {
            return .running
        }
        return .idle
    }

    /// Summary line for display in sidebar
    var statusSummary: String? {
        if let body = latestNotificationBody, !body.isEmpty {
            return body
        }
        if let count = changedFileCount, count > 0 {
            return count == 1 ? "1 file changed" : "\(count) files changed"
        }
        return nil
    }
}
