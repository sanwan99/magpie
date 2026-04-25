// Main app — composes filter rail, search bar, layout, preview pane, settings.
// Owns global state: focused clip, search query, type filter, pinned set,
// queue mode, layout mode, settings + snippets visibility.

const { useTweaks, TweaksPanel, TweakSection, TweakRadio, TweakSlider, TweakToggle } = window;
const { StripeLayout, StackLayout, GridLayout } = window;
const { ClipDetail, Settings, SnippetsRail, Icon, MetaRow, ClipPreview, AppDot } = window;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "dark": true,
  "layout": "stripe",
  "blur": 36,
  "accent": "mono",
  "density": "regular",
  "showPreview": true
}/*EDITMODE-END*/;

const TYPE_FILTERS = [
  { id: 'all',    label: 'All',    icon: 'all'    },
  { id: 'text',   label: 'Text',   icon: 'text'   },
  { id: 'code',   label: 'Code',   icon: 'code'   },
  { id: 'url',    label: 'Link',   icon: 'link'   },
  { id: 'image',  label: 'Image',  icon: 'image'  },
  { id: 'file',   label: 'File',   icon: 'file'   },
  { id: 'folder', label: 'Folder', icon: 'folder' },
];

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);

  const [clips, setClips]       = React.useState(window.CLIPS);
  const [focusId, setFocusId]   = React.useState(window.CLIPS[0].id);
  const [query, setQuery]       = React.useState('');
  const [filter, setFilter]     = React.useState('all');
  const [showPinned, setShowPinned] = React.useState(false);
  const [queue, setQueue]       = React.useState(false);
  const [settingsOpen, setSettingsOpen] = React.useState(false);
  const [snippetsOpen, setSnippetsOpen] = React.useState(false);
  const [pasteFlash, setPasteFlash]     = React.useState(null);
  const [panelVisible, setPanelVisible] = React.useState(true);

  const inputRef = React.useRef(null);

  // ── derived list ────────────────────────────────────────────────────────
  const filtered = React.useMemo(() => {
    let arr = [...clips];
    arr.sort((a, b) => (b.pinned - a.pinned) || (a.ago - b.ago));
    if (filter !== 'all') arr = arr.filter((c) => c.type === filter);
    if (showPinned)       arr = arr.filter((c) => c.pinned);
    return window.searchClips(arr, query);
  }, [clips, query, filter, showPinned]);

  // Keep focus valid as the list changes.
  React.useEffect(() => {
    if (filtered.length === 0) return;
    if (!filtered.find((c) => c.id === focusId)) setFocusId(filtered[0].id);
  }, [filtered, focusId]);

  const focused = filtered.find((c) => c.id === focusId) || filtered[0];

  // ── actions ─────────────────────────────────────────────────────────────
  const togglePin = React.useCallback((id) => {
    setClips((cs) => cs.map((c) => c.id === id ? { ...c, pinned: !c.pinned } : c));
  }, []);

  const move = React.useCallback((delta) => {
    if (!filtered.length) return;
    const i = Math.max(0, filtered.findIndex((c) => c.id === focusId));
    const j = Math.min(filtered.length - 1, Math.max(0, i + delta));
    setFocusId(filtered[j].id);
  }, [filtered, focusId]);

  const doPaste = React.useCallback((id) => {
    const target = id || focusId;
    if (!target) return;
    setPasteFlash(target);
    setTimeout(() => setPasteFlash(null), 700);
    if (queue) {
      // queue mode: paste the next item, then advance focus
      move(1);
    }
  }, [focusId, queue, move]);

  // ── keyboard ────────────────────────────────────────────────────────────
  React.useEffect(() => {
    const onKey = (e) => {
      // Cmd+P toggles panel visibility
      if ((e.metaKey || e.ctrlKey) && e.key === 'p') {
        e.preventDefault();
        setPanelVisible((v) => !v);
        return;
      }
      if (!panelVisible) return;
      if (settingsOpen && e.key !== 'Escape') return;

      if (e.key === 'Escape') {
        if (settingsOpen) setSettingsOpen(false);
        else if (snippetsOpen) setSnippetsOpen(false);
        else if (query) setQuery('');
        else if (filter !== 'all') setFilter('all');
        return;
      }
      if (e.key === 'ArrowRight' || e.key === 'ArrowDown') { e.preventDefault(); move(1); return; }
      if (e.key === 'ArrowLeft'  || e.key === 'ArrowUp')   { e.preventDefault(); move(-1); return; }
      if (e.key === 'Enter') { e.preventDefault(); doPaste(); return; }
      if ((e.metaKey || e.ctrlKey) && e.key === 'd') {
        e.preventDefault(); if (focused) togglePin(focused.id); return;
      }
      if ((e.metaKey || e.ctrlKey) && e.key === 'q') {
        e.preventDefault(); setQueue((q) => !q); return;
      }
      if ((e.metaKey || e.ctrlKey) && e.key === '\\') {
        e.preventDefault();
        const order = ['stripe', 'stack', 'grid'];
        setTweak('layout', order[(order.indexOf(t.layout) + 1) % 3]);
        return;
      }
      if ((e.metaKey || e.ctrlKey) && e.key === ',') {
        e.preventDefault(); setSettingsOpen(true); return;
      }
      // Cmd+1..9 quick paste
      if ((e.metaKey || e.ctrlKey) && /^[1-9]$/.test(e.key)) {
        e.preventDefault();
        const idx = +e.key - 1;
        if (filtered[idx]) { setFocusId(filtered[idx].id); doPaste(filtered[idx].id); }
        return;
      }
      // Slash to focus search
      if (e.key === '/' && document.activeElement !== inputRef.current) {
        e.preventDefault();
        inputRef.current?.focus();
      }
    };

    const onPasteEvt = (e) => doPaste(e.detail);
    window.addEventListener('keydown', onKey);
    window.addEventListener('clip-paste', onPasteEvt);
    return () => {
      window.removeEventListener('keydown', onKey);
      window.removeEventListener('clip-paste', onPasteEvt);
    };
  }, [move, doPaste, togglePin, focused, filtered, panelVisible, settingsOpen,
      snippetsOpen, query, filter, t.layout, setTweak]);

  // ── apply theme ─────────────────────────────────────────────────────────
  React.useEffect(() => {
    document.documentElement.dataset.theme  = t.dark ? 'dark' : 'light';
    document.documentElement.dataset.accent = t.accent;
    document.documentElement.style.setProperty('--blur', `${t.blur}px`);
  }, [t.dark, t.accent, t.blur]);

  const Layout = { stripe: StripeLayout, stack: StackLayout, grid: GridLayout }[t.layout];

  return (
    <>
      <Desktop />

      <DockHint visible={!panelVisible} onActivate={() => setPanelVisible(true)} />

      <div className={`panel-stage ${panelVisible ? 'is-up' : 'is-down'}`}>
        <div className={`panel layout-${t.layout}`}>
          <PanelChrome
            inputRef={inputRef}
            query={query} setQuery={setQuery}
            filter={filter} setFilter={setFilter}
            showPinned={showPinned} setShowPinned={setShowPinned}
            queue={queue} setQueue={setQueue}
            layout={t.layout} setLayout={(v) => setTweak('layout', v)}
            onSettings={() => setSettingsOpen(true)}
            onSnippets={() => setSnippetsOpen((v) => !v)}
            count={filtered.length}
          />

          <div className="panel-body">
            <Layout
              clips={filtered}
              focusId={focusId}
              setFocusId={setFocusId}
              onPin={togglePin}
            />
            {t.showPreview && focused && t.layout !== 'stack' && (
              <aside className="preview-pane">
                <ClipDetail clip={focused}
                            onPin={() => togglePin(focused.id)}
                            onPaste={() => doPaste(focused.id)} />
              </aside>
            )}
            {t.layout === 'stack' && focused && (
              <aside className="preview-pane preview-pane-wide">
                <ClipDetail clip={focused}
                            onPin={() => togglePin(focused.id)}
                            onPaste={() => doPaste(focused.id)} />
              </aside>
            )}
          </div>

          <PanelFoot focused={focused} queue={queue} count={filtered.length} />
        </div>

        <SnippetsRail
          open={snippetsOpen}
          onClose={() => setSnippetsOpen(false)}
          onPick={(s) => { setQuery(s.shortcut); setSnippetsOpen(false); }}
        />

        {pasteFlash && <PasteFlash />}
      </div>

      <Settings open={settingsOpen} onClose={() => setSettingsOpen(false)}
                t={t} setTweak={setTweak} />

      <TweaksPanel title="Tweaks">
        <TweakSection label="Layout" />
        <TweakRadio label="Mode" value={t.layout}
                    options={[
                      { value: 'stripe', label: 'Stripe' },
                      { value: 'stack',  label: 'Stack'  },
                      { value: 'grid',   label: 'Grid'   },
                    ]}
                    onChange={(v) => setTweak('layout', v)} />
        <TweakToggle label="Preview pane" value={t.showPreview}
                     onChange={(v) => setTweak('showPreview', v)} />
        <TweakSection label="Theme" />
        <TweakToggle label="Dark mode" value={t.dark}
                     onChange={(v) => setTweak('dark', v)} />
        <TweakRadio label="Accent" value={t.accent}
                    options={[
                      { value: 'mono', label: 'Mono' },
                      { value: 'graphite', label: 'Graph' },
                      { value: 'blue', label: 'Blue' },
                      { value: 'olive', label: 'Olive' },
                    ]}
                    onChange={(v) => setTweak('accent', v)} />
        <TweakSlider label="Vibrancy" value={t.blur} min={0} max={60} step={2} unit="px"
                     onChange={(v) => setTweak('blur', v)} />
      </TweaksPanel>
    </>
  );
}

// ── Desktop background (so the vibrancy looks real) ─────────────────────────

function Desktop() {
  return (
    <div className="desktop">
      <div className="menubar">
        <div className="menubar-l">
          <span className="apple"></span>
          <span className="mb-app">Magpie</span>
          <span className="mb-item">File</span>
          <span className="mb-item">Edit</span>
          <span className="mb-item">View</span>
          <span className="mb-item">Window</span>
          <span className="mb-item">Help</span>
        </div>
        <div className="menubar-r">
          <span>⌘P</span>
          <span>{new Date().toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' })}</span>
          <span>{new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</span>
        </div>
      </div>

      <div className="wallpaper">
        <div className="wp-orb wp-orb-1" />
        <div className="wp-orb wp-orb-2" />
        <div className="wp-orb wp-orb-3" />
        <div className="wp-grid" />
      </div>

      {/* faux open windows so vibrancy has something to work against */}
      <div className="faux-window faux-1">
        <div className="fw-tl"><i /><i /><i /></div>
        <div className="fw-side">
          {['Inbox', 'Drafts', 'Sent', 'Archive', 'Trash', 'Junk'].map((x) => (
            <div className="fw-row" key={x}>{x}</div>
          ))}
        </div>
        <div className="fw-main">
          {Array.from({ length: 8 }).map((_, i) => (
            <div className="fw-line" key={i} style={{ width: `${30 + (i * 11) % 60}%` }} />
          ))}
        </div>
      </div>
    </div>
  );
}

// ── Dock hint while panel is hidden ─────────────────────────────────────────

function DockHint({ visible, onActivate }) {
  if (!visible) return null;
  return (
    <button className="dock-hint" onClick={onActivate}>
      <Icon name="kbd" size={11} />
      <span>Press</span>
      <kbd className="kbd">⌘</kbd><kbd className="kbd">P</kbd>
      <span>to open Deck</span>
    </button>
  );
}

// ── Panel chrome: search + filter rail + actions ───────────────────────────

function PanelChrome({ inputRef, query, setQuery, filter, setFilter,
                       showPinned, setShowPinned, queue, setQueue,
                       layout, setLayout, onSettings, onSnippets, count }) {
  return (
    <div className="panel-head">
      <div className="search">
        <Icon name="search" size={13} />
        <input
          ref={inputRef}
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search clips, type / for filters…  e.g. type:code react"
          spellCheck={false}
          autoFocus
        />
        {query && (
          <button className="clear" onClick={() => setQuery('')}>
            <Icon name="close" size={10} />
          </button>
        )}
        <span className="result-count">{count}</span>
      </div>

      <div className="filter-rail">
        {TYPE_FILTERS.map((f) => (
          <button
            key={f.id}
            className={`fchip ${filter === f.id ? 'is-on' : ''}`}
            onClick={() => setFilter(f.id)}
            title={f.label}>
            <Icon name={f.icon} size={11} />
            <span>{f.label}</span>
          </button>
        ))}
        <span className="rail-divider" />
        <button className={`fchip ${showPinned ? 'is-on' : ''}`}
                onClick={() => setShowPinned((v) => !v)} title="Pinned">
          <Icon name={showPinned ? 'pinned' : 'pin'} size={11} />
          <span>Pinned</span>
        </button>
        <button className={`fchip ${queue ? 'is-on' : ''}`}
                onClick={() => setQueue((v) => !v)} title="Queue mode">
          <Icon name="queue" size={11} />
          <span>Queue</span>
        </button>
      </div>

      <div className="actions">
        <div className="layout-seg">
          {['stripe', 'stack', 'grid'].map((m) => (
            <button key={m} className={layout === m ? 'on' : ''}
                    onClick={() => setLayout(m)} title={m}>
              <LayoutIcon mode={m} />
            </button>
          ))}
        </div>
        <button className="ic-btn" onClick={onSnippets} title="Snippets">
          <Icon name="snippet" size={13} />
        </button>
        <button className="ic-btn" onClick={onSettings} title="Settings">
          <Icon name="settings" size={13} />
        </button>
      </div>
    </div>
  );
}

function LayoutIcon({ mode }) {
  if (mode === 'stripe') return (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4">
      <rect x="1.5" y="5" width="3.5" height="6" rx="1" />
      <rect x="6.25" y="5" width="3.5" height="6" rx="1" />
      <rect x="11" y="5" width="3.5" height="6" rx="1" />
    </svg>
  );
  if (mode === 'stack') return (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4">
      <rect x="2" y="3" width="12" height="3" rx="1" />
      <rect x="2" y="6.5" width="12" height="3" rx="1" />
      <rect x="2" y="10" width="12" height="3" rx="1" />
    </svg>
  );
  return (
    <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.4">
      <rect x="2" y="2.5" width="5" height="5" rx="1" />
      <rect x="9" y="2.5" width="5" height="5" rx="1" />
      <rect x="2" y="9" width="5" height="5" rx="1" />
      <rect x="9" y="9" width="5" height="5" rx="1" />
    </svg>
  );
}

// ── Panel footer ─────────────────────────────────────────────────────────

function PanelFoot({ focused, queue, count }) {
  return (
    <div className="panel-foot">
      <div className="foot-l">
        {focused && (
          <>
            <span className="ft-type">{window.typeLabel(focused.type)}</span>
            <span className="dot-sep">·</span>
            <AppDot app={focused.app} />
            <span className="dot-sep">·</span>
            <span>{window.fmtAgo(focused.ago)} ago</span>
          </>
        )}
      </div>
      <div className="foot-r">
        {queue && <span className="queue-pill">Queue mode</span>}
        <span><kbd className="kbd">↑</kbd><kbd className="kbd">↓</kbd> Navigate</span>
        <span><kbd className="kbd">↵</kbd> Paste</span>
        <span><kbd className="kbd">⌘</kbd><kbd className="kbd">D</kbd> Pin</span>
        <span><kbd className="kbd">Esc</kbd> Close</span>
      </div>
    </div>
  );
}

function PasteFlash() {
  return <div className="paste-flash"><Icon name="check" size={16} /><span>Pasted</span></div>;
}

ReactDOM.createRoot(document.getElementById('root')).render(<App />);
