// Splatoon theme — squid mascot + ink animations
//
// Two squids (yellow + purple) live above the panel. When the panel opens
// (Cmd+P), an ink splat blooms on the desktop and the squid pops out of it.
// When the panel closes, the squid dives back into the puddle and the
// splat shrinks away.
//
// Everything is hidden unless data-accent="splat" — so toggling the theme in
// Tweaks switches the whole experience on without affecting other accents.

// Splatoon-style squid silhouette built from clean primitives:
//   • body  : a soft triangle/teardrop (the "mantle")
//   • fins  : two horizontal flaps with finger-fringe at the tips, on the sides
//   • tents : 4 short teardrop tentacles fringing the bottom
//   • eyes  : two HUGE white circles with big black pupils
// Body uses an SVG gradient (lighter top → saturated bottom).
const SquidIcon = ({ team = 'yellow', flip = false, gradId = 'sq' }) => {
  // Cache-bust so a previously-loaded broken-eyes PNG isn't served from cache.
  const src = (team === 'purple' ? 'assets/squid-purple.png' : 'assets/squid-yellow.png') + '?v=2';
  return (
    <img src={src} alt="" draggable={false}
         className={`squid-img ${flip ? 'is-flip' : ''}`} />
  );
  // (legacy SVG kept below for reference only — never reached)
  /* eslint-disable */
  const lightId = `${gradId}-light`;
  return (
    <svg viewBox="0 0 200 200" className={`squid-svg ${flip ? 'is-flip' : ''}`}>
      <defs>
        <linearGradient id={lightId} x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"  className="grad-top" />
          <stop offset="100%" className="grad-bot" />
        </linearGradient>
      </defs>

      {/* Tentacle fringe — 4 stubby teardrops at the bottom of the body.
          Drawn first so they sit BEHIND the body. */}
      <g className="squid-tents">
        <path d="M 60 138 Q 56 158 60 172 Q 68 174 70 158 Q 70 144 66 138 Z" />
        <path d="M 80 142 Q 76 168 82 184 Q 92 184 92 168 Q 90 150 86 142 Z" />
        <path d="M 114 142 Q 108 150 108 168 Q 108 184 118 184 Q 124 168 120 142 Z" />
        <path d="M 134 138 Q 130 144 130 158 Q 132 174 140 172 Q 144 158 140 138 Z" />
      </g>

      {/* Fin "ears" — horizontal flaps with finger-fringe tips, one each side.
          Drawn before the body so the body slightly overlaps them. */}
      <g className="squid-fins">
        {/* left fin */}
        <path d="
          M 38 70
          Q 22 66 8 70
          Q 4 76 8 80
          Q 14 80 14 84
          Q 6 86 6 92
          Q 12 94 16 92
          Q 14 98 18 100
          Q 24 98 24 92
          Q 30 96 34 92
          Q 36 84 38 78 Z" />
        {/* right fin (mirror) */}
        <path d="
          M 162 70
          Q 178 66 192 70
          Q 196 76 192 80
          Q 186 80 186 84
          Q 194 86 194 92
          Q 188 94 184 92
          Q 186 98 182 100
          Q 176 98 176 92
          Q 170 96 166 92
          Q 164 84 162 78 Z" />
      </g>

      {/* Body — soft triangle with rounded apex (the mantle) */}
      <path
        className="squid-body"
        fill={`url(#${lightId})`}
        d="
          M 100 22
          C 130 22 152 52 158 88
          C 162 116 154 138 144 142
          C 124 148 76 148 56 142
          C 46 138 38 116 42 88
          C 48 52 70 22 100 22 Z" />

      {/* Eyes — two huge white ovals with big black pupils */}
      <g className="squid-eyes">
        <ellipse cx="78" cy="92" rx="22" ry="26" fill="#fff"
                 stroke="#0e0e10" strokeWidth="3" />
        <ellipse cx="122" cy="92" rx="22" ry="26" fill="#fff"
                 stroke="#0e0e10" strokeWidth="3" />
        {/* pupils — big and slightly off-center for personality */}
        <ellipse cx="83" cy="98" rx="11" ry="14" fill="#0e0e10" />
        <ellipse cx="117" cy="98" rx="11" ry="14" fill="#0e0e10" />
        {/* pupil highlights */}
        <ellipse cx="79" cy="92" rx="3.5" ry="5" fill="#fff" />
        <ellipse cx="113" cy="92" rx="3.5" ry="5" fill="#fff" />
      </g>
    </svg>
  );
};

// An organic ink splat shape — randomized blobs around a center.
// We bake a few preset SVG paths so each puddle/splat looks different.
const SPLAT_PATHS = [
  // big central blob with 5 droplets
  "M50 6 C70 6 92 18 96 38 C100 58 86 76 70 84 C92 92 98 102 88 110 C78 116 72 104 64 102 C66 116 56 122 48 114 C40 106 50 96 44 90 C30 96 14 92 8 78 C2 64 14 50 22 46 C8 38 6 24 16 16 C28 8 38 22 50 6 Z",
  // wide horizontal splat
  "M10 50 C0 38 8 22 24 22 C30 12 50 8 60 18 C70 6 92 12 96 30 C112 32 118 50 104 60 C106 76 90 84 78 78 C72 92 50 92 44 78 C30 88 14 80 14 66 C2 64 -2 56 10 50 Z",
  // chunky drip with tail
  "M20 30 C20 14 38 8 52 14 C62 4 84 8 90 22 C108 22 114 44 100 56 C108 70 92 84 80 78 C82 96 64 102 56 90 C46 100 30 92 32 78 C16 78 8 64 16 52 C8 44 10 32 20 30 Z",
];

// Random rotation/scale per puddle
function pickSplat(seed) {
  const i = Math.abs(seed) % SPLAT_PATHS.length;
  const rot = (seed * 47) % 360;
  return { d: SPLAT_PATHS[i], rot };
}

const InkPuddle = ({ side, team, visible, seed = 1 }) => {
  const { d, rot } = pickSplat(seed);
  return (
    <div className={`ink-puddle ink-${side} team-${team} ${visible ? 'is-on' : ''}`}>
      <svg viewBox="0 0 120 120" className="puddle-svg">
        <g style={{ transform: `rotate(${rot}deg)`, transformOrigin: '60px 60px' }}>
          <path d={d} className="puddle-fill" />
          {/* halftone dots over the puddle for paper-print feel */}
          <path d={d} className="puddle-dots" />
        </g>
      </svg>
    </div>
  );
};

// Squid mascot: emerges from a puddle. visible=false → dives back in.
const SquidMascot = ({ side, team, visible, seed }) => {
  return (
    <div className={`squid-stage stage-${side} team-${team} ${visible ? 'is-out' : 'is-in'}`}>
      <InkPuddle side={side} team={team} visible={visible} seed={seed} />
      <div className="squid-wrap">
        <SquidIcon team={team} flip={side === 'right'} gradId={`sq-${side}`} />
      </div>
    </div>
  );
};

// Background splatter — decorative scattered drops behind the panel
const SplatBackdrop = () => {
  return (
    <div className="splat-bg">
      <svg viewBox="0 0 1600 600" preserveAspectRatio="xMidYMid slice">
        {/* yellow splats */}
        <g className="bg-team-y">
          <path d={SPLAT_PATHS[0]} transform="translate(80 60) scale(.8) rotate(20)" />
          <path d={SPLAT_PATHS[2]} transform="translate(1280 80) scale(1.3) rotate(-25)" />
          <path d={SPLAT_PATHS[1]} transform="translate(220 380) scale(.5) rotate(140)" />
          <path d={SPLAT_PATHS[2]} transform="translate(1480 420) scale(.6) rotate(60)" />
        </g>
        {/* purple splats */}
        <g className="bg-team-p">
          <path d={SPLAT_PATHS[1]} transform="translate(900 40) scale(.9) rotate(-40)" />
          <path d={SPLAT_PATHS[0]} transform="translate(440 120) scale(.45) rotate(75)" />
          <path d={SPLAT_PATHS[2]} transform="translate(60 280) scale(.55) rotate(200)" />
          <path d={SPLAT_PATHS[1]} transform="translate(1140 320) scale(.7) rotate(-110)" />
        </g>
      </svg>
    </div>
  );
};

// Burst splat that fires when paste happens (instead of the paste-flash pill)
const SplatBurst = ({ team = 'yellow' }) => {
  const path = SPLAT_PATHS[Math.floor(Math.random() * SPLAT_PATHS.length)];
  const rot = Math.floor(Math.random() * 360);
  return (
    <div className={`splat-burst team-${team}`}>
      <svg viewBox="0 0 120 120">
        <g style={{ transform: `rotate(${rot}deg)`, transformOrigin: '60px 60px' }}>
          <path d={path} className="burst-fill" />
        </g>
      </svg>
      <div className="burst-label">SPLAT!</div>
    </div>
  );
};

Object.assign(window, { SquidMascot, SplatBackdrop, SplatBurst, InkPuddle, SquidIcon });
