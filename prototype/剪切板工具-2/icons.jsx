// SF-Symbols-style monoline icons (16 / 13 / 11px versions). All stroke-based,
// 1.5px stroke, currentColor — so they tint with text.
//
// We're not pulling in a real icon library. These are just enough icons for
// the surfaces we actually render: search, pin, tags, content types, traffic
// lights. Each Icon has a fixed 16x16 viewBox so sizing is just width/height.

const Icon = ({ name, size = 16, ...rest }) => {
  const s = size;
  const common = {
    width: s, height: s, viewBox: '0 0 16 16',
    fill: 'none', stroke: 'currentColor',
    strokeWidth: 1.4, strokeLinecap: 'round', strokeLinejoin: 'round',
    ...rest,
  };
  switch (name) {
    case 'search': return (
      <svg {...common}><circle cx="7" cy="7" r="4.2" /><path d="M10 10l3 3" /></svg>
    );
    case 'pin': return (
      <svg {...common}><path d="M9.6 1.8l4.6 4.6-1.4 1.4-1.6-.4-3.5 3.5.6 3.3-1 1L4.5 11l-3.6.4 1-1 3.3-3.3-.4-1.6L6.2 4l1.4-1.4 2 1Z" /></svg>
    );
    case 'pinned': return (
      <svg {...common} fill="currentColor" stroke="none">
        <path d="M9.6 1.8l4.6 4.6-1.4 1.4-1.6-.4-3.5 3.5.6 3.3-1 1L4.5 11l-3.6.4 1-1 3.3-3.3-.4-1.6L6.2 4l1.4-1.4 2 1Z" />
      </svg>
    );
    case 'tag': return (
      <svg {...common}><path d="M2 8.5V2h6.5L14 7.5 7.5 14 2 8.5Z" /><circle cx="5" cy="5" r=".9" fill="currentColor" /></svg>
    );
    case 'text': return (
      <svg {...common}><path d="M3 4h10M5 4v9M11 4v9M3 13h4M9 13h4" /></svg>
    );
    case 'code': return (
      <svg {...common}><path d="M5 4l-3 4 3 4M11 4l3 4-3 4M9 3l-2 10" /></svg>
    );
    case 'image': return (
      <svg {...common}><rect x="2" y="3" width="12" height="10" rx="1.6" /><circle cx="6" cy="6.5" r="1" /><path d="M2.5 12l3.5-3.5 3 3 2-2 2.5 2.5" /></svg>
    );
    case 'file': return (
      <svg {...common}><path d="M3.5 2h6L13 5.5V14H3.5V2Z" /><path d="M9 2v4h4" /></svg>
    );
    case 'link': return (
      <svg {...common}><path d="M9 7l-2 2M6.5 4.5l1-1a2.5 2.5 0 013.5 3.5l-1 1M9.5 11.5l-1 1a2.5 2.5 0 01-3.5-3.5l1-1" /></svg>
    );
    case 'folder': return (
      <svg {...common}><path d="M2 5a1.5 1.5 0 011.5-1.5h3l1.5 1.5h5A1.5 1.5 0 0114.5 6.5v5A1.5 1.5 0 0113 13H3a1 1 0 01-1-1V5Z" /></svg>
    );
    case 'all': return (
      <svg {...common}><rect x="2.5" y="2.5" width="4.5" height="4.5" rx="1" /><rect x="9" y="2.5" width="4.5" height="4.5" rx="1" /><rect x="2.5" y="9" width="4.5" height="4.5" rx="1" /><rect x="9" y="9" width="4.5" height="4.5" rx="1" /></svg>
    );
    case 'queue': return (
      <svg {...common}><path d="M3 4h10M3 8h7M3 12h10" /></svg>
    );
    case 'snippet': return (
      <svg {...common}><path d="M3 3h7l3 3v7H3V3Z" /><path d="M10 3v3h3M5.5 9h5M5.5 11h3" /></svg>
    );
    case 'settings': return (
      <svg {...common}><circle cx="8" cy="8" r="2.2" /><path d="M8 1.5v2M8 12.5v2M14.5 8h-2M3.5 8h-2M12.6 3.4l-1.4 1.4M4.8 11.2l-1.4 1.4M12.6 12.6l-1.4-1.4M4.8 4.8L3.4 3.4" /></svg>
    );
    case 'close': return (
      <svg {...common}><path d="M4 4l8 8M12 4l-8 8" /></svg>
    );
    case 'enter': return (
      <svg {...common}><path d="M13 4v3a2 2 0 01-2 2H3M3 9l3-2.5M3 9l3 2.5" /></svg>
    );
    case 'cmd': return (
      <svg {...common}><path d="M5 5h6v6H5V5Z" /><path d="M5 5a1.5 1.5 0 11-1.5 1.5H5M11 5a1.5 1.5 0 101.5 1.5H11M5 11a1.5 1.5 0 11-1.5-1.5H5M11 11a1.5 1.5 0 101.5-1.5H11" /></svg>
    );
    case 'arrow': return (
      <svg {...common}><path d="M4 8h8M9 5l3 3-3 3" /></svg>
    );
    case 'arrowUp': return (
      <svg {...common}><path d="M8 13V3M5 6l3-3 3 3" /></svg>
    );
    case 'arrowDn': return (
      <svg {...common}><path d="M8 3v10M5 10l3 3 3-3" /></svg>
    );
    case 'check': return (
      <svg {...common}><path d="M3 8.5l3 3 7-7" /></svg>
    );
    case 'plus': return (
      <svg {...common}><path d="M8 3v10M3 8h10" /></svg>
    );
    case 'sun': return (
      <svg {...common}><circle cx="8" cy="8" r="3" /><path d="M8 1.5v1.5M8 13v1.5M14.5 8H13M3 8H1.5M12.6 3.4l-1.1 1.1M4.5 11.5l-1.1 1.1M12.6 12.6l-1.1-1.1M4.5 4.5L3.4 3.4" /></svg>
    );
    case 'moon': return (
      <svg {...common}><path d="M13 9.5A5.5 5.5 0 116.5 3a4.5 4.5 0 006.5 6.5Z" /></svg>
    );
    case 'kbd': return (
      <svg {...common}><rect x="1.5" y="4" width="13" height="8" rx="1.5" /><path d="M4 7h.5M6.5 7H7M9 7h.5M11.5 7h.5M4.5 9.5h7" /></svg>
    );
    case 'history': return (
      <svg {...common}><path d="M2.5 8a5.5 5.5 0 105.5-5.5A5.5 5.5 0 003 5" /><path d="M3 2.5V5h2.5M8 5v3l2 1.5" /></svg>
    );
    default: return null;
  }
};

window.Icon = Icon;
