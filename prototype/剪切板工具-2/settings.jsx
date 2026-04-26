// Settings panel + Snippets sidebar.
// Settings opens as a centered modal sheet. Snippets is a collapsible sidebar.

const { Icon } = window;

function Settings({ open, onClose, t, setTweak }) {
  if (!open) return null;
  const sections = [
    { id: 'general',   label: 'General',   icon: 'settings' },
    { id: 'shortcuts', label: 'Shortcuts', icon: 'kbd' },
    { id: 'history',   label: 'History',   icon: 'history' },
    { id: 'privacy',   label: 'Privacy',   icon: 'pinned' },
  ];
  const [active, setActive] = React.useState('general');

  return (
    <div className="settings-scrim" onClick={onClose}>
      <div className="settings" onClick={(e) => e.stopPropagation()}>
        <div className="settings-tl">
          <span className="tl tl-r" onClick={onClose} />
          <span className="tl tl-y" />
          <span className="tl tl-g" />
          <h4>Settings</h4>
        </div>
        <div className="settings-body">
          <aside className="settings-side">
            {sections.map((s) => (
              <button key={s.id}
                      className={active === s.id ? 'is-on' : ''}
                      onClick={() => setActive(s.id)}>
                <Icon name={s.icon} size={13} /> <span>{s.label}</span>
              </button>
            ))}
          </aside>
          <main className="settings-main">
            {active === 'general' && <GeneralPane t={t} setTweak={setTweak} />}
            {active === 'shortcuts' && <ShortcutsPane />}
            {active === 'history'   && <HistoryPane />}
            {active === 'privacy'   && <PrivacyPane />}
          </main>
        </div>
      </div>
    </div>
  );
}

function Field({ label, hint, children, inline = true }) {
  return (
    <div className={`field ${inline ? 'inline' : ''}`}>
      <div className="field-l">
        <div className="flabel">{label}</div>
        {hint && <div className="fhint">{hint}</div>}
      </div>
      <div className="field-r">{children}</div>
    </div>
  );
}

function Switch({ value, onChange }) {
  return (
    <button className={`sw ${value ? 'on' : ''}`} onClick={() => onChange(!value)}>
      <i />
    </button>
  );
}

function GeneralPane({ t, setTweak }) {
  return (
    <div className="pane">
      <h5 className="pane-h">Appearance</h5>
      <Field label="Theme" hint="Light, dark, or follow system.">
        <Seg value={t.dark ? 'dark' : 'light'}
             options={[
               { value: 'light', label: 'Light' },
               { value: 'dark',  label: 'Dark'  },
             ]}
             onChange={(v) => setTweak('dark', v === 'dark')} />
      </Field>
      <Field label="Vibrancy" hint="Background blur strength.">
        <input type="range" min="0" max="60" step="2"
               value={t.blur} onChange={(e) => setTweak('blur', +e.target.value)} />
        <span className="num">{t.blur}px</span>
      </Field>
      <Field label="Accent" hint="A subtle hue applied to focused items.">
        <Seg value={t.accent}
             options={[
               { value: 'mono',  label: 'Mono'  },
               { value: 'graphite', label: 'Graphite' },
               { value: 'blue',  label: 'Blue'  },
               { value: 'olive', label: 'Olive' },
             ]}
             onChange={(v) => setTweak('accent', v)} />
      </Field>

      <h5 className="pane-h">Behavior</h5>
      <Field label="Launch at login">
        <Switch value={true} onChange={() => {}} />
      </Field>
      <Field label="Show recent first">
        <Switch value={true} onChange={() => {}} />
      </Field>
      <Field label="Detect colors and links">
        <Switch value={true} onChange={() => {}} />
      </Field>
      <Field label="Strip tracking parameters from URLs">
        <Switch value={true} onChange={() => {}} />
      </Field>
    </div>
  );
}

function Seg({ value, options, onChange }) {
  return (
    <div className="seg">
      {options.map((o) => (
        <button key={o.value}
                className={value === o.value ? 'on' : ''}
                onClick={() => onChange(o.value)}>{o.label}</button>
      ))}
    </div>
  );
}

const SHORTCUTS = [
  ['Open panel',         ['⌘', 'P']],
  ['Search',             ['/']],
  ['Move selection',     ['←', '→']],
  ['Paste selected',     ['↵']],
  ['Paste plain',        ['⇧', '↵']],
  ['Quick paste 1–9',    ['⌘', '1-9']],
  ['Toggle pin',         ['⌘', 'D']],
  ['Toggle queue mode',  ['⌘', 'Q']],
  ['Toggle preview',     ['␣']],
  ['Switch layout',      ['⌘', '\\']],
  ['Open settings',      ['⌘', ',']],
  ['Close',              ['Esc']],
];

function ShortcutsPane() {
  return (
    <div className="pane">
      <h5 className="pane-h">Keyboard</h5>
      <div className="kbd-table">
        {SHORTCUTS.map(([label, keys]) => (
          <div className="kbd-row" key={label}>
            <span className="kbd-label">{label}</span>
            <span className="kbd-keys">
              {keys.map((k, i) => <kbd className="kbd" key={i}>{k}</kbd>)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

function HistoryPane() {
  return (
    <div className="pane">
      <h5 className="pane-h">Storage</h5>
      <Field label="Keep history for">
        <select className="sel" defaultValue="30">
          <option value="7">7 days</option>
          <option value="30">30 days</option>
          <option value="90">90 days</option>
          <option value="forever">Forever</option>
        </select>
      </Field>
      <Field label="Max items" hint="Older items are trimmed first.">
        <input className="sel" type="number" defaultValue="2000" />
      </Field>
      <Field label="Ignore apps" hint="Don't capture from these.">
        <span className="muted">1Password, Keychain Access</span>
      </Field>
      <div className="danger">
        <button className="dgr">Clear history…</button>
      </div>
    </div>
  );
}

function PrivacyPane() {
  return (
    <div className="pane">
      <h5 className="pane-h">Privacy</h5>
      <Field label="Touch ID to unlock"><Switch value={true} onChange={() => {}} /></Field>
      <Field label="Encrypt local store"><Switch value={true} onChange={() => {}} /></Field>
      <Field label="Skip secret-looking content" hint="Detects keys, tokens, OTPs.">
        <Switch value={true} onChange={() => {}} />
      </Field>
      <Field label="Send analytics"><Switch value={false} onChange={() => {}} /></Field>
    </div>
  );
}

// ── Snippets ──────────────────────────────────────────────────────────────

function SnippetsRail({ open, onClose, onPick }) {
  if (!open) return null;
  return (
    <div className="rail">
      <div className="rail-head">
        <Icon name="snippet" size={12} />
        <span>Snippets</span>
        <button className="rail-x" onClick={onClose}><Icon name="close" size={11} /></button>
      </div>
      <div className="rail-body">
        {window.SNIPPETS.map((s) => (
          <button key={s.id} className="snip" onClick={() => onPick(s)}>
            <div className="snip-head">
              <code className="snip-sc">{s.shortcut}</code>
              <span className="snip-title">{s.title}</span>
            </div>
            <div className="snip-body">{s.body.split('\n').slice(0, 2).join(' / ')}</div>
          </button>
        ))}
        <button className="snip add">
          <Icon name="plus" size={11} /> <span>New snippet</span>
        </button>
      </div>
    </div>
  );
}

Object.assign(window, { Settings, SnippetsRail });
