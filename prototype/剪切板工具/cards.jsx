// Card renderers — type-aware previews used by all three layout modes.
// Two surfaces: <ClipPreview> (compact, used in lists/strips/grids)
//               <ClipDetail>  (large, used in the focused preview pane)

const { Icon } = window;

// Tiny noise/gradient placeholder for fake images. Returns a CSS background.
function placeholderBG(kind) {
  if (kind === 'noise-warm')
    return 'linear-gradient(135deg,#dccfb8,#ada08b)';
  if (kind === 'noise-cool')
    return 'linear-gradient(135deg,#bcc6cf,#7e8a96)';
  return 'linear-gradient(135deg,#cfcfcf,#9a9a9a)';
}

// ── shared bits ────────────────────────────────────────────────────────────

function AppDot({ app }) {
  const a = window.APPS[app];
  if (!a) return null;
  return (
    <div className="app-dot" title={a.name}>
      <span style={{ background: a.tint }} />
      <em>{a.name}</em>
    </div>
  );
}

function MetaRow({ clip, showTags = true }) {
  return (
    <div className="meta">
      <AppDot app={clip.app} />
      <span className="dot-sep">·</span>
      <span className="ago">{window.fmtAgo(clip.ago)}</span>
      {showTags && clip.tags && clip.tags.length > 0 && (
        <>
          <span className="dot-sep">·</span>
          <span className="tags">
            {clip.tags.map((t) => <span key={t} className="tag">#{t}</span>)}
          </span>
        </>
      )}
    </div>
  );
}

// ── code block (syntax-tinted) ─────────────────────────────────────────────

function CodeBlock({ src, lang, lineNumbers = false, maxLines }) {
  const lines = src.split('\n');
  const shown = maxLines ? lines.slice(0, maxLines) : lines;
  const truncated = maxLines && lines.length > maxLines;
  return (
    <pre className={`code lang-${lang || 'txt'}`}>
      <code>
        {shown.map((line, i) => {
          const tokens = window.tintCode(line, lang);
          return (
            <div className="ln" key={i}>
              {lineNumbers && <span className="lno">{i + 1}</span>}
              <span className="lc">
                {tokens.map((tk, j) => (
                  <span key={j} className={tk.k ? `t-${tk.k}` : ''}>{tk.t}</span>
                ))}
                {line.length === 0 && '\u00A0'}
              </span>
            </div>
          );
        })}
        {truncated && <div className="ln more">…</div>}
      </code>
    </pre>
  );
}

// ── compact preview (for cards in stripe/stack/grid) ───────────────────────

function ClipPreview({ clip, dense = false }) {
  switch (clip.type) {
    case 'code': {
      const max = dense ? 5 : 8;
      return (
        <div className="prev prev-code">
          <CodeBlock src={clip.body} lang={clip.lang} maxLines={max} />
        </div>
      );
    }
    case 'text':
      return (
        <div className="prev prev-text">
          <p>{clip.body}</p>
        </div>
      );
    case 'url':
      return (
        <div className="prev prev-url">
          <div className="url-host">
            <i className="favicon" />
            <span>{clip.host}</span>
          </div>
          <div className="url-title">{clip.title}</div>
          {!dense && clip.desc && <div className="url-desc">{clip.desc}</div>}
        </div>
      );
    case 'folder':
      return (
        <div className="prev prev-folder">
          <div className="folder-icon"><Icon name="folder" size={22} /></div>
          <div className="folder-meta">
            <div className="fname">{clip.title}</div>
            {!dense && <div className="fpath">{clip.path}</div>}
            {!dense && <div className="fkind">{clip.items} items</div>}
          </div>
        </div>
      );
    case 'image':
      return (
        <div className="prev prev-image">
          <div className="thumb" style={{ background: placeholderBG(clip.placeholder) }}>
            <span className="dim">{clip.w} × {clip.h}</span>
          </div>
        </div>
      );
    case 'file':
      return (
        <div className="prev prev-file">
          <div className="file-icon"><Icon name="file" size={20} /></div>
          <div className="file-meta">
            <div className="fname">{clip.title}</div>
            {!dense && <div className="fpath">{clip.path}</div>}
          </div>
        </div>
      );
    default:
      return null;
  }
}

// ── card title (used by stripe + grid) ─────────────────────────────────────

function ClipTitle({ clip }) {
  // For text/code with no explicit title, fall back to a body excerpt.
  let label = clip.title;
  if (!label && clip.body)
    label = clip.body.split('\n')[0].slice(0, 64);
  if (!label && clip.url)
    label = clip.url;
  return <div className="ctitle" title={label}>{label}</div>;
}

// ── full detail (used by the focused preview pane) ─────────────────────────

function ClipDetail({ clip, onPin, onPaste }) {
  return (
    <div className="detail">
      <div className="detail-head">
        <div className="detail-type">
          <Icon name={clip.type === 'url' ? 'link' : clip.type} size={11} />
          <span>{window.typeLabel(clip.type)}</span>
          {clip.lang && <span className="lang-pill">{clip.lang}</span>}
        </div>
        <button className={`pin-btn ${clip.pinned ? 'is-on' : ''}`}
                onClick={onPin} title={clip.pinned ? 'Unpin' : 'Pin'}>
          <Icon name={clip.pinned ? 'pinned' : 'pin'} size={13} />
        </button>
      </div>

      <h3 className="detail-title">
        {clip.title || (clip.body && clip.body.split('\n')[0]) || clip.url || 'Untitled'}
      </h3>

      <MetaRow clip={clip} />

      <div className="detail-body">
        {clip.type === 'code' && <CodeBlock src={clip.body} lang={clip.lang} lineNumbers />}
        {clip.type === 'text' && <pre className="text-body">{clip.body}</pre>}
        {clip.type === 'url'  && (
          <div className="url-card">
            <div className="url-thumb" />
            <div className="url-host"><i className="favicon" /><span>{clip.host}</span></div>
            <div className="url-title">{clip.title}</div>
            <div className="url-desc">{clip.desc}</div>
            <div className="url-link">{clip.url}</div>
          </div>
        )}
        {clip.type === 'folder' && (
          <div className="file-card">
            <div className="big-file"><Icon name="folder" size={44} /></div>
            <dl className="kv">
              <dt>Name</dt><dd>{clip.title}</dd>
              <dt>Path</dt><dd className="mono">{clip.path}</dd>
              <dt>Kind</dt><dd>{clip.kind}</dd>
              <dt>Items</dt><dd>{clip.items}</dd>
            </dl>
            <div className="copy-path-hint">
              <Icon name="check" size={11} />
              <span>Press <kbd className="kbd">↵</kbd> to copy path</span>
            </div>
          </div>
        )}
        {clip.type === 'image' && (
          <div className="image-card">
            <div className="big-thumb" style={{ background: placeholderBG(clip.placeholder) }} />
            <dl className="kv">
              <dt>Name</dt><dd>{clip.title}</dd>
              <dt>Size</dt><dd>{clip.w} × {clip.h} · {(clip.sizeKB / 1024).toFixed(2)} MB</dd>
            </dl>
          </div>
        )}
        {clip.type === 'file' && (
          <div className="file-card">
            <div className="big-file"><Icon name="file" size={36} /></div>
            <dl className="kv">
              <dt>Name</dt><dd>{clip.title}</dd>
              <dt>Path</dt><dd className="mono">{clip.path}</dd>
              <dt>Kind</dt><dd>{clip.kind}</dd>
              <dt>Size</dt><dd>{(clip.sizeKB / 1024).toFixed(2)} MB</dd>
            </dl>
          </div>
        )}
      </div>

      <div className="detail-foot">
        <button className="paste-btn" onClick={onPaste}>
          <span>Paste</span>
          <kbd className="kbd">↵</kbd>
        </button>
        <button className="ghost-btn">Paste plain</button>
      </div>
    </div>
  );
}

Object.assign(window, { ClipPreview, ClipTitle, ClipDetail, MetaRow, CodeBlock, AppDot });
