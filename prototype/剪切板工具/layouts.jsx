// Three layout modes for the clipboard panel: stripe / stack / grid.
// Each takes the same props { clips, focusId, setFocusId, onPin } and renders
// the items list. Selection visuals + keyboard handling live in app.jsx.

const { ClipPreview, ClipTitle, MetaRow, Icon } = window;

// ── STRIPE: horizontal scrolling cards (Dock-like) ────────────────────────

function StripeLayout({ clips, focusId, setFocusId, onPin }) {
  const ref = React.useRef(null);

  // Keep the focused card in view as it changes.
  React.useEffect(() => {
    if (!ref.current) return;
    const el = ref.current.querySelector(`[data-id="${focusId}"]`);
    if (!el) return;
    const r = el.getBoundingClientRect();
    const pr = ref.current.getBoundingClientRect();
    if (r.left < pr.left + 24 || r.right > pr.right - 24) {
      el.scrollIntoView({ behavior: 'smooth', inline: 'center', block: 'nearest' });
    }
  }, [focusId]);

  return (
    <div className="stripe" ref={ref}>
      {clips.map((c) => (
        <button
          key={c.id} data-id={c.id}
          className={`stripe-card type-${c.type} ${c.id === focusId ? 'is-focus' : ''} ${c.pinned ? 'is-pinned' : ''}`}
          onClick={() => setFocusId(c.id)}
          onDoubleClick={() => window.dispatchEvent(new CustomEvent('clip-paste', { detail: c.id }))}
        >
          {c.pinned && <i className="pin-corner"><Icon name="pinned" size={9} /></i>}
          <div className="card-body">
            <ClipPreview clip={c} dense />
          </div>
          <div className="card-foot">
            <ClipTitle clip={c} />
            <div className="card-foot-meta">
              <span className="app-tint" style={{ background: window.APPS[c.app]?.tint }} />
              <span className="ago">{window.fmtAgo(c.ago)}</span>
            </div>
          </div>
        </button>
      ))}
      {clips.length === 0 && <Empty />}
    </div>
  );
}

// ── STACK: centered list with side preview pane ──────────────────────────

function StackLayout({ clips, focusId, setFocusId, onPin }) {
  return (
    <div className="stack">
      <div className="stack-list">
        {clips.map((c, i) => (
          <button
            key={c.id} data-id={c.id}
            className={`stack-row type-${c.type} ${c.id === focusId ? 'is-focus' : ''}`}
            onClick={() => setFocusId(c.id)}
            onDoubleClick={() => window.dispatchEvent(new CustomEvent('clip-paste', { detail: c.id }))}
          >
            <div className="stack-num">{i < 9 ? `⌘${i + 1}` : ''}</div>
            <div className="stack-icon"><Icon name={c.type === 'url' ? 'link' : c.type} size={13} /></div>
            <div className="stack-main">
              <div className="stack-title">
                {c.pinned && <Icon name="pinned" size={9} />}
                <ClipTitle clip={c} />
              </div>
              <div className="stack-sub">
                <span style={{ color: window.APPS[c.app]?.tint }}>●</span>
                <span>{window.APPS[c.app]?.name}</span>
                <span className="dot-sep">·</span>
                <span>{window.fmtAgo(c.ago)}</span>
                {c.tags?.length > 0 && (
                  <>
                    <span className="dot-sep">·</span>
                    {c.tags.slice(0, 2).map((t) => <span key={t} className="tag">#{t}</span>)}
                  </>
                )}
              </div>
            </div>
            <div className="stack-prev">
              <ClipPreview clip={c} dense />
            </div>
          </button>
        ))}
        {clips.length === 0 && <Empty />}
      </div>
    </div>
  );
}

// ── GRID: dense tile grid ────────────────────────────────────────────────

function GridLayout({ clips, focusId, setFocusId, onPin }) {
  return (
    <div className="grid">
      {clips.map((c) => (
        <button
          key={c.id} data-id={c.id}
          className={`grid-tile type-${c.type} ${c.id === focusId ? 'is-focus' : ''}`}
          onClick={() => setFocusId(c.id)}
          onDoubleClick={() => window.dispatchEvent(new CustomEvent('clip-paste', { detail: c.id }))}
        >
          {c.pinned && <i className="pin-corner"><Icon name="pinned" size={9} /></i>}
          <div className="tile-body"><ClipPreview clip={c} dense /></div>
          <div className="tile-foot">
            <span className="tile-type"><Icon name={c.type === 'url' ? 'link' : c.type} size={9} /></span>
            <ClipTitle clip={c} />
            <span className="ago">{window.fmtAgo(c.ago)}</span>
          </div>
        </button>
      ))}
      {clips.length === 0 && <Empty />}
    </div>
  );
}

function Empty() {
  return (
    <div className="empty">
      <div className="empty-icon"><Icon name="search" size={20} /></div>
      <div className="empty-title">No matches</div>
      <div className="empty-sub">Try a different search, or clear filters with <kbd>Esc</kbd>.</div>
    </div>
  );
}

Object.assign(window, { StripeLayout, StackLayout, GridLayout });
