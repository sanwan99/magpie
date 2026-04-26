// Mock clipboard data + helpers.
// Realistic developer-flavored entries: code, JSON, links, terminal commands,
// hex colors, file paths, images. Times are minutes-ago integers; the renderer
// formats them into "12m" / "3h" / "Yesterday" etc.

const NOW = Date.now();

const APPS = {
  vscode:    { name: 'Visual Studio Code', tint: '#3b8eea' },
  chrome:    { name: 'Google Chrome',      tint: '#4285f4' },
  terminal:  { name: 'Terminal',           tint: '#1f1f1f' },
  figma:     { name: 'Figma',              tint: '#f24e1e' },
  slack:     { name: 'Slack',              tint: '#611f69' },
  notes:     { name: 'Notes',              tint: '#f8bd2e' },
  finder:    { name: 'Finder',             tint: '#1f7af0' },
  notion:    { name: 'Notion',             tint: '#191919' },
  linear:    { name: 'Linear',             tint: '#5e6ad2' },
  preview:   { name: 'Preview',            tint: '#7d7d7d' },
  safari:    { name: 'Safari',             tint: '#0fb5ee' },
  xcode:     { name: 'Xcode',              tint: '#147efb' },
};

// Each item: { id, type, app, ago (min), pinned, tags, ... type-specific fields }
const CLIPS = [
  {
    id: 'c01', type: 'code', lang: 'tsx', app: 'vscode', ago: 1, pinned: true,
    tags: ['react', 'snippet'],
    title: 'useDebounce hook',
    body:
`export function useDebounce<T>(value: T, delay = 200): T {
  const [v, setV] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setV(value), delay);
    return () => clearTimeout(id);
  }, [value, delay]);
  return v;
}`,
  },
  {
    id: 'c02', type: 'url', app: 'chrome', ago: 4, pinned: false,
    tags: ['docs'],
    url: 'https://developer.mozilla.org/en-US/docs/Web/CSS/backdrop-filter',
    title: 'backdrop-filter — CSS | MDN',
    host: 'developer.mozilla.org',
    desc: 'The backdrop-filter CSS property lets you apply graphical effects such as blurring or color shifting to the area behind an element.',
  },
  {
    id: 'c03', type: 'folder', app: 'finder', ago: 7, pinned: true,
    tags: ['project'],
    title: 'magpie',
    path: '~/Code/magpie',
    items: 124, kind: 'Folder',
  },
  {
    id: 'c04', type: 'text', app: 'terminal', ago: 12, pinned: false,
    tags: ['shell'],
    title: 'git log oneline',
    body: 'git log --oneline --graph --decorate --all -n 20',
  },
  {
    id: 'c05', type: 'code', lang: 'json', app: 'vscode', ago: 18, pinned: false,
    tags: ['config'],
    title: 'package.json fragment',
    body:
`{
  "name": "deck",
  "version": "0.4.2",
  "private": true,
  "scripts": {
    "dev": "vite",
    "build": "vite build",
    "lint": "eslint . --ext .ts,.tsx"
  }
}`,
  },
  {
    id: 'c06', type: 'image', app: 'preview', ago: 24, pinned: false,
    tags: ['screenshot'],
    title: 'Screenshot 2026-04-25 at 14.02.png',
    w: 2880, h: 1800, sizeKB: 412,
    // colored placeholder, drawn by renderer
    placeholder: 'noise-warm',
  },
  {
    id: 'c07', type: 'file', app: 'finder', ago: 35, pinned: false,
    tags: [],
    title: 'Q2-roadmap.pdf',
    path: '~/Documents/Work/Q2-roadmap.pdf',
    sizeKB: 1840, kind: 'PDF Document',
  },
  {
    id: 'c08', type: 'text', app: 'slack', ago: 52, pinned: true,
    tags: ['standup'],
    title: 'Standup template',
    body:
`*Yesterday*
— shipped clipboard search refactor
— reviewed 2 PRs

*Today*
— land queue mode
— start work on snippets

*Blockers*
— none`,
  },
  {
    id: 'c09', type: 'url', app: 'safari', ago: 70, pinned: false,
    tags: ['inspiration'],
    url: 'https://www.are.na/block/27384921',
    title: 'Are.na — type specimen',
    host: 'are.na',
    desc: 'Reference for type specimen layout — tight tracking, mixed weights.',
  },
  {
    id: 'c10', type: 'code', lang: 'sh', app: 'terminal', ago: 88, pinned: false,
    tags: ['ffmpeg'],
    title: 'ffmpeg → mp4 → gif',
    body:
`ffmpeg -i input.mp4 -vf "fps=24,scale=720:-1:flags=lanczos" \\
  -c:v pam -f image2pipe - | \\
  convert -delay 4 - -loop 0 -layers optimize out.gif`,
  },
  {
    id: 'c11', type: 'text', app: 'terminal', ago: 110, pinned: false,
    tags: ['git'],
    title: 'commit hash',
    body: 'a3f1c08e2b7d49c1f0aa6e3b8e1d52f4c9e0d7a2',
  },
  {
    id: 'c12', type: 'folder', app: 'terminal', ago: 145, pinned: false,
    tags: ['design'],
    title: 'Brand Assets',
    path: '/Volumes/Work/Brand-Assets-2026',
    items: 38, kind: 'Folder',
  },
  {
    id: 'c13', type: 'code', lang: 'css', app: 'vscode', ago: 200, pinned: false,
    tags: ['css'],
    title: 'macOS vibrancy panel',
    body:
`.panel {
  background: rgba(28, 28, 30, 0.62);
  backdrop-filter: blur(36px) saturate(180%);
  border: 0.5px solid rgba(255, 255, 255, 0.08);
  border-radius: 14px;
  box-shadow:
    0 1px 0 rgba(255, 255, 255, 0.06) inset,
    0 24px 60px rgba(0, 0, 0, 0.45);
}`,
  },
  {
    id: 'c14', type: 'text', app: 'notes', ago: 320, pinned: false,
    tags: ['quote'],
    title: '',
    body:
`"Make it work, make it right, make it fast — in that order. The hardest part is knowing which step you are on."`,
  },
  {
    id: 'c15', type: 'image', app: 'figma', ago: 460, pinned: false,
    tags: ['mockup'],
    title: 'Frame 412 — onboarding hero',
    w: 1440, h: 900, sizeKB: 188, placeholder: 'noise-cool',
  },
  {
    id: 'c16', type: 'url', app: 'linear', ago: 540, pinned: false,
    tags: ['ticket'],
    url: 'https://linear.app/deck/issue/DEK-218',
    title: 'DEK-218 · Queue mode keyboard regressions',
    host: 'linear.app',
    desc: 'After landing the new search, ⌥+↓ no longer cycles through the queue when results are filtered.',
  },
  {
    id: 'c17', type: 'file', app: 'finder', ago: 720, pinned: false,
    tags: [],
    title: 'logo-mark@3x.png',
    path: '~/Design/Brand/logo-mark@3x.png',
    sizeKB: 64, kind: 'PNG Image',
  },
  {
    id: 'c19', type: 'folder', app: 'finder', ago: 28, pinned: false,
    tags: [],
    title: 'Downloads',
    path: '~/Downloads',
    items: 412, kind: 'Folder',
  },
  {
    id: 'c20', type: 'folder', app: 'terminal', ago: 240, pinned: false,
    tags: ['dotfiles'],
    title: '.config',
    path: '~/.config/nvim',
    items: 17, kind: 'Folder',
  },
  {
    id: 'c18', type: 'code', lang: 'swift', app: 'xcode', ago: 1100, pinned: false,
    tags: ['swift'],
    title: 'NSPasteboard listener',
    body:
`final class ClipboardWatcher {
  private var lastChange: Int = NSPasteboard.general.changeCount
  private var timer: Timer?
  func start() {
    timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
      self?.tick()
    }
  }
  private func tick() {
    let pb = NSPasteboard.general
    guard pb.changeCount != lastChange else { return }
    lastChange = pb.changeCount
    NotificationCenter.default.post(name: .clipboardChanged, object: nil)
  }
}`,
  },
];

// Snippets: user-defined templates. Distinct from CLIPS — these are saved.
const SNIPPETS = [
  { id: 's01', shortcut: ';sig',    title: 'Email signature',
    body: '— Yu\nProduct & Design · gmail.com' },
  { id: 's02', shortcut: ';meet',   title: 'Meeting block',
    body: 'Agenda\n— item\n\nNotes\n—\n\nActions\n— [ ] ' },
  { id: 's03', shortcut: ';review', title: 'PR review checklist',
    body: '✓ tests pass\n✓ types are tight\n✓ no console.log\n✓ accessible' },
  { id: 's04', shortcut: ';date',   title: 'ISO date',
    body: '2026-04-25' },
];

// ── helpers ────────────────────────────────────────────────────────────────

function fmtAgo(min) {
  if (min < 1)   return 'Just now';
  if (min < 60)  return `${min}m`;
  if (min < 60 * 24) return `${Math.round(min / 60)}h`;
  const d = Math.round(min / 60 / 24);
  if (d === 1)   return 'Yesterday';
  if (d < 7)     return `${d}d`;
  return `${Math.round(d / 7)}w`;
}

function typeLabel(t) {
  return ({ code: 'Code', url: 'Link', text: 'Text',
            folder: 'Folder', image: 'Image', file: 'File' })[t] || t;
}

// Tiny syntax tinter — not real highlighting, just enough visual variety to
// look like an editor without pulling in a big library.
function tintCode(src, lang) {
  if (!src) return [{ t: '' }];
  const tokens = [];
  const push = (t, k) => t && tokens.push({ t, k });

  const KW = {
    tsx:   /\b(import|export|from|const|let|var|function|return|if|else|async|await|interface|type|class|extends|implements|new|this|static|public|private|true|false|null|undefined)\b/g,
    swift: /\b(import|class|struct|final|func|var|let|guard|else|return|self|init|private|public|internal|nil|true|false|if|while|for|in|switch|case|default|extension|where|weak|strong|throws|try|do|catch)\b/g,
    sh:    /\b(if|then|else|fi|for|while|do|done|in|case|esac|return|export|local|function)\b/g,
    css:   /\b(important)\b/g,
    json:  /\b(true|false|null)\b/g,
  };
  const STR  = /(["'`])(?:\\.|(?!\1).)*\1/g;
  const COM  = /(\/\/[^\n]*|#[^\n]*|\/\*[\s\S]*?\*\/)/g;
  const NUM  = /\b\d+(?:\.\d+)?\b/g;
  const PROP = /^([\s]*)([\w-]+)(\s*:)/gm;   // css/json key
  const FN   = /\b([A-Za-z_][\w]*)(?=\()/g;

  // We'll do a simple line-by-line approach: split into lines, then apply
  // regex-by-regex with placeholders. Good enough for a mock.
  const ranges = [];
  const mark = (re, kind) => {
    src.replace(re, (m, ...args) => {
      const offset = args[args.length - 2];
      ranges.push({ s: offset, e: offset + m.length, kind, txt: m });
      return m;
    });
  };
  if (lang === 'css' || lang === 'json') mark(PROP, 'prop');
  mark(COM, 'com');
  mark(STR, 'str');
  if (KW[lang]) mark(KW[lang], 'kw');
  mark(NUM, 'num');
  if (lang === 'tsx' || lang === 'swift') mark(FN, 'fn');

  // Resolve overlaps: keep earliest, drop overlapping later ones (comments win
  // because they're applied after PROP but before STR/KW — close enough).
  ranges.sort((a, b) => a.s - b.s || b.e - a.e);
  const final = [];
  let cursor = -1;
  for (const r of ranges) {
    if (r.s < cursor) continue;
    final.push(r);
    cursor = r.e;
  }

  let out = [];
  let i = 0;
  for (const r of final) {
    if (r.s > i) out.push({ t: src.slice(i, r.s) });
    out.push({ t: r.txt, k: r.kind });
    i = r.e;
  }
  if (i < src.length) out.push({ t: src.slice(i) });
  return out;
}

// Search: keyword AND match across title/body/host/url/tags. Type filters via
// "type:code"-style hints, app filters via "app:vscode". Lightweight but real.
function searchClips(items, q) {
  if (!q.trim()) return items;
  const tokens = q.trim().split(/\s+/);
  const filters = { type: [], app: [], tag: [] };
  const words = [];
  for (const t of tokens) {
    const m = /^(type|app|tag):(.+)$/i.exec(t);
    if (m) filters[m[1].toLowerCase()].push(m[2].toLowerCase());
    else words.push(t.toLowerCase());
  }
  return items.filter((it) => {
    if (filters.type.length && !filters.type.includes(it.type)) return false;
    if (filters.app.length  && !filters.app.includes(it.app)) return false;
    if (filters.tag.length  && !filters.tag.some((t) => (it.tags || []).includes(t))) return false;
    if (!words.length) return true;
    const hay = [
      it.title, it.body, it.url, it.host, it.desc, it.path,
      ...(it.tags || []),
    ].filter(Boolean).join(' ').toLowerCase();
    return words.every((w) => hay.includes(w));
  });
}

Object.assign(window, { CLIPS, SNIPPETS, APPS, NOW, fmtAgo, typeLabel, tintCode, searchClips });
