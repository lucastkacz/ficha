/*
 * Ficha mock kit: React components, written with htm so no build step runs.
 *
 * Each component is named after its SwiftUI counterpart in the repo, so a
 * mock that's settled translates screen by screen:
 *   MenuContent      -> App/MenuContent.swift (MenuBarExtra's menu)
 *   ReviewPanelView  -> App/ReviewPanelView.swift
 *   CaptureView      -> App/CaptureView.swift
 *   Button, IconButton, KeyLabel, Capsule, Segmented, Field -> SwiftUI controls
 * The scenery (Stage, MenuBar, Window, DocumentWindow, CallWindow) and
 * MockControls belong to the mock only.
 *
 * Needs React 18, ReactDOM 18, htm, then engine.js, loaded before it.
 */
(function (root) {
  'use strict';

  const { useState, useEffect, useLayoutEffect, useRef, useContext, useSyncExternalStore, createContext } = React;
  // htm returns an array for a template with several roots; a Fragment
  // holds them instead, so React doesn't ask for keys.
  const bound = htm.bind(React.createElement);
  const html = (...args) => {
    const out = bound(...args);
    return Array.isArray(out) ? React.createElement(React.Fragment, null, ...out) : out;
  };
  const E = root.FichaEngine;

  // ---------------------------------------------------------------------
  // Time, as the Mac shows it: English, with the viewer's 12 or 24 hours.
  // ---------------------------------------------------------------------
  const hourCycle = new Intl.DateTimeFormat(undefined, { hour: 'numeric' }).resolvedOptions().hourCycle;
  const h12 = hourCycle === 'h12' || hourCycle === 'h11';
  const fmt = (opts) => new Intl.DateTimeFormat('en-US', { hour12: h12, ...opts });
  const clockFmt = fmt({ weekday: 'short', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  const timeFmt = fmt({ hour: 'numeric', minute: '2-digit' });
  const dayFmt = fmt({ weekday: 'short', month: 'short', day: 'numeric' });
  const monthDayFmt = fmt({ month: 'short', day: 'numeric' });
  const formatClock = (t) => clockFmt.format(t).replace(/,/g, '').replace(/ at /, '  ');
  const formatTime = (t) => timeFmt.format(t);
  const formatDay = (t) => dayFmt.format(t);
  /** "Nov 23", "Nov 23 – 25" or "Nov 29 – Dec 2". */
  function formatDayRange(a, b) {
    if (E.startOfDay(a) === E.startOfDay(b)) return monthDayFmt.format(a);
    const da = new Date(a);
    const db = new Date(b);
    if (da.getMonth() === db.getMonth()) return `${monthDayFmt.format(a)} – ${db.getDate()}`;
    return `${monthDayFmt.format(a)} – ${monthDayFmt.format(b)}`;
  }
  /** "in 12 min", "in 2 h 5 min", "tomorrow at 9:00". */
  function formatWait(ms, at) {
    const min = Math.round(ms / E.MINUTE);
    if (min <= 0) return 'now';
    if (min < 60) return `in ${min} min`;
    if (E.startOfDay(at) !== E.startOfDay(at - ms)) return `${formatDay(at)}, ${formatTime(at)}`;
    const h = Math.floor(min / 60);
    return `in ${h} h${min % 60 ? ` ${min % 60} min` : ''}`;
  }

  // ---------------------------------------------------------------------
  // The store and the clock.
  // ---------------------------------------------------------------------
  function useStore(app) {
    return useSyncExternalStore(
      (fn) => app.subscribe(fn),
      () => app.getState(),
    );
  }
  /** Runs the toy clock in real time; the app's speed multiplies it. */
  function useClock(app, everyMs = 100) {
    useEffect(() => {
      let last = performance.now();
      const id = setInterval(() => {
        const now = performance.now();
        app.tick(Math.min(now - last, 1000));
        last = now;
      }, everyMs);
      return () => clearInterval(id);
    }, [app]);
  }
  /** Keeps a value on screen a moment after it goes, so it can animate out. */
  function usePresence(value, ms = 160) {
    const [shown, setShown] = useState(value);
    const [leaving, setLeaving] = useState(false);
    useEffect(() => {
      if (value) {
        setShown(value);
        setLeaving(false);
        return;
      }
      if (!shown) return;
      setLeaving(true);
      const id = setTimeout(() => {
        setShown(null);
        setLeaving(false);
      }, ms);
      return () => clearTimeout(id);
    }, [value]);
    return [value || shown, leaving && !value];
  }

  // ---------------------------------------------------------------------
  // Icons: outlines close to the SF Symbols the app uses.
  // ---------------------------------------------------------------------
  const svg = (paths, size = 16, extra = {}) =>
    html`<svg width=${size} height=${size} viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.35"
      strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" ...${extra}>${paths}</svg>`;
  const Icon = {
    // character.book.closed: Ficha in the menu bar.
    book: (s) =>
      svg(html`<path d="M4.6 1.9h7.3a.9.9 0 0 1 .9.9v9.6a.9.9 0 0 1-.9.9H4.6A1.6 1.6 0 0 1 3 11.7V3.5a1.6 1.6 0 0 1 1.6-1.6z" />
        <path d="M3 11.7a1.6 1.6 0 0 1 1.6-1.6h8.2" /><path d="M6.4 8.4 8 4.3l1.6 4.1M6.9 7.1h2.2" />`, s),
    undo: (s) => svg(html`<path d="M6 3.8 3 6.8l3 3" /><path d="M3 6.8h7a3.3 3.3 0 0 1 0 6.6H8.2" />`, s),
    ask: (s) =>
      svg(html`<path d="M3.5 2.4h9A1.6 1.6 0 0 1 14.1 4v6a1.6 1.6 0 0 1-1.6 1.6H8.3l-3 2.4v-2.4H3.5A1.6 1.6 0 0 1 1.9 10V4a1.6 1.6 0 0 1 1.6-1.6z" />
        <path d="M6.7 5.3a1.4 1.4 0 1 1 2 1.3c-.5.2-.7.6-.7 1v.2" /><circle cx="8" cy="9.4" r=".55" fill="currentColor" stroke="none" />`, s),
    flag: (s) => svg(html`<path d="M3.8 14.2V2.4" /><path d="M3.8 2.8h8.6l-2 3 2 3H3.8" />`, s),
    bury: (s) =>
      svg(html`<path d="M1.8 8S4 3.6 8 3.6 14.2 8 14.2 8 12 12.4 8 12.4 1.8 8 1.8 8z" /><circle cx="8" cy="8" r="2" /><path d="m2.6 2.6 10.8 10.8" />`, s),
    close: (s) => svg(html`<path d="m4 4 8 8M12 4l-8 8" />`, s),
    wifi: (s) =>
      svg(html`<path d="M2 6.2a8.6 8.6 0 0 1 12 0M4.1 8.4a5.6 5.6 0 0 1 7.8 0M6.2 10.6a2.6 2.6 0 0 1 3.6 0" /><circle cx="8" cy="12.6" r=".6" fill="currentColor" stroke="none" />`, s),
    battery: () =>
      html`<svg width="25" height="12" viewBox="0 0 25 12" fill="none" aria-hidden="true">
        <rect x=".75" y=".75" width="21" height="10.5" rx="3" stroke="currentColor" strokeOpacity=".45" strokeWidth="1" />
        <rect x="2.4" y="2.4" width="14" height="7.2" rx="1.6" fill="currentColor" />
        <path d="M23.2 4.2v3.6" stroke="currentColor" strokeOpacity=".45" strokeWidth="1.4" strokeLinecap="round" /></svg>`,
    play: (s) => svg(html`<path d="M5 3.2v9.6L12.6 8z" fill="currentColor" />`, s),
    pause: (s) => svg(html`<path d="M5.2 3.4v9.2M10.8 3.4v9.2" strokeWidth="2.2" />`, s),
    skip: (s) => svg(html`<path d="M3.5 3.6v8.8L9.6 8z" fill="currentColor" /><path d="M12.4 3.6v8.8" strokeWidth="1.8" />`, s),
  };

  // ---------------------------------------------------------------------
  // Controls.
  // ---------------------------------------------------------------------
  /** KeyLabel: a button's title and the key that presses it. */
  const KeyLabel = ({ title, k }) => html`<span>${title}</span>${k != null && html`<span className="key">${k}</span>`}`;

  /** Button with .bordered, or .borderedProminent when `prominent`. */
  function Button({ title, k, prominent, wide, disabled, pressed, onClick, children, ...rest }) {
    const cls = ['btn', prominent && 'prominent', wide && 'wide', pressed && 'pressed'].filter(Boolean).join(' ');
    return html`<button type="button" className=${cls} disabled=${disabled} onClick=${onClick} ...${rest}>
      ${children || html`<${KeyLabel} title=${title} k=${k} />`}</button>`;
  }
  /** An icon-only, borderless button, with its key in the tooltip. */
  const IconButton = ({ icon, label, onClick, disabled }) =>
    html`<button type="button" className="icon-btn" title=${label} aria-label=${label} disabled=${disabled}
      onClick=${onClick}>${icon()}</button>`;
  const Capsule = ({ children, tint }) => html`<span className=${tint ? 'capsule tint' : 'capsule'}>${children}</span>`;
  const Divider = () => html`<hr className="divider" />`;
  /** Picker with .pickerStyle(.segmented). */
  const Segmented = ({ options, value, onChange, label }) =>
    html`<div className="segmented" role="group" aria-label=${label}>
      ${options.map(
        (o) => html`<button type="button" key=${String(o.value)} aria-pressed=${o.value === value}
          onClick=${() => onChange(o.value)}>${o.label}</button>`,
      )}</div>`;

  // ---------------------------------------------------------------------
  // The fake Mac.
  // ---------------------------------------------------------------------
  const ScreenContext = createContext({ scale: 1, w: 1280, h: 800, menuBar: 24, notch: false });
  const useScreen = () => useContext(ScreenContext);

  /**
   * Macs' screens, at macOS's default "looks like" size. A MacBook with a
   * notch has a taller menu bar, 37 points, with the notch in its middle.
   */
  const SCREENS = [
    { id: 'fit', label: 'Fit the window' },
    { id: 'air13', label: 'MacBook Air 13″ · 1470×956', w: 1470, h: 956, notch: true },
    { id: 'pro14', label: 'MacBook Pro 14″ · 1512×982', w: 1512, h: 982, notch: true },
    { id: 'pro16', label: 'MacBook Pro 16″ · 1728×1117', w: 1728, h: 1117, notch: true },
    { id: 'small', label: 'Small, no notch · 1280×800', w: 1280, h: 800, notch: false },
    { id: 'studio', label: '27″ display · 2560×1440', w: 2560, h: 1440, notch: false },
  ];
  const DOCK = 66; // The Dock's height, its margin included.

  /**
   * The screen. "Fit the window" fills the page, 1:1 when it's big enough
   * and scaled down when it isn't (a phone). A Mac's size keeps that size,
   * centered, scaled down only when the page is smaller.
   */
  function Stage({ minWidth = 1024, minHeight = 660, wallpaper = 'sky', screen = 'fit', onScale, children }) {
    const ref = useRef(null);
    // Nothing renders until the stage is measured, so windows place
    // themselves on the real screen size.
    const [box, setBox] = useState(null);
    useLayoutEffect(() => {
      const el = ref.current;
      const measure = () => setBox({ w: el.clientWidth || 1280, h: el.clientHeight || 800 });
      measure();
      const ro = new ResizeObserver(measure);
      ro.observe(el);
      return () => ro.disconnect();
    }, []);
    const preset = SCREENS.find((x) => x.id === screen && x.w);
    // Tells the mock's bar how much a Mac's size is scaled down, if at all.
    const shown = box && preset ? Math.min(1, box.w / preset.w, box.h / preset.h) : 1;
    useEffect(() => onScale && onScale(shown), [shown]);
    if (!box) return html`<div className="stage" ref=${ref} />`;
    let scale, w, h;
    if (preset) {
      scale = Math.min(1, box.w / preset.w, box.h / preset.h);
      w = preset.w;
      h = preset.h;
    } else {
      scale = Math.min(1, box.w / minWidth, box.h / minHeight);
      w = box.w / scale;
      h = box.h / scale;
    }
    const dx = Math.max(0, (box.w - w * scale) / 2);
    const dy = Math.max(0, (box.h - h * scale) / 2);
    const notch = !!(preset && preset.notch);
    const value = { scale, w, h, notch, menuBar: notch ? 37 : 24, preset };
    return html`<div className=${preset ? 'stage letterbox' : 'stage'} ref=${ref}>
      <${ScreenContext.Provider} value=${value}>
        <div className="mac" data-wallpaper=${wallpaper}
          style=${{ width: w, height: h, transform: `translate(${dx}px, ${dy}px) scale(${scale})` }}>${children}</div>
      </${ScreenContext.Provider}>
    </div>`;
  }

  /** The menu bar: the app in front and its menus, status items, the clock. */
  function MenuBar({ appName, menus = [], now, status, autohide }) {
    const { menuBar, notch } = useScreen();
    const bar = html`<div className=${autohide ? 'menubar autohide' : 'menubar'} style=${{ height: menuBar }}>
      ${notch && html`<span className="notch" style=${{ height: menuBar }} />`}
      <span className="item app">${appName}</span>
      ${menus.map((m) => html`<span className="item" key=${m}>${m}</span>`)}
      <span className="spacer" />
      ${status}
      <span className="item">${Icon.wifi(15)}</span>
      <span className="item">${Icon.battery()}</span>
      <span className="item clock">${formatClock(now)}</span>
    </div>`;
    // Over a full-screen app, the menu bar shows when the pointer reaches the top.
    return autohide ? html`<div className="menubar-zone">${bar}</div>` : bar;
  }

  /** The Dock, with a dot under the apps that are open. */
  function Dock({ running = [] }) {
    const apps = [
      ['files', '🗂️', 'linear-gradient(#7cc4ff, #2f8cf0)'],
      ['web', '🧭', 'linear-gradient(#ffffff, #dfe6ee)'],
      ['mail', '✉️', 'linear-gradient(#6fb6ff, #1a74e8)'],
      ['writer', '📝', 'linear-gradient(#fff6d6, #f5d36b)'],
      ['call', '📹', 'linear-gradient(#5fd38a, #20a356)'],
      ['video', '🎬', 'linear-gradient(#3b3b45, #15151a)'],
      ['ficha', '🗃️', 'linear-gradient(#fdfdfd, #e6e1d6)'],
      ['settings', '⚙️', 'linear-gradient(#c9ccd3, #8e939c)'],
    ];
    return html`<div className="dock glass" aria-label="Dock">
      ${apps.map(
        ([id, glyph, bg]) => html`<span key=${id} className=${running.includes(id) ? 'tile running' : 'tile'}
          style=${{ background: bg }}>${glyph}</span>`,
      )}</div>`;
  }

  /** A menu under the menu bar; a click anywhere else closes it. */
  function Menu({ left, onDismiss, children }) {
    const { menuBar } = useScreen();
    useEffect(() => {
      // Esc closes the menu and nothing else.
      const onKey = (e) => e.key === 'Escape' && (e.stopPropagation(), onDismiss());
      window.addEventListener('keydown', onKey, true);
      return () => window.removeEventListener('keydown', onKey, true);
    }, [onDismiss]);
    return html`<div style=${{ position: 'absolute', inset: 0, zIndex: 55 }} onPointerDown=${onDismiss} />
      <div className="menu glass" role="menu" style=${{ left, top: menuBar + 3 }}>${children}</div>`;
  }
  const MenuRow = ({ title, shortcut, disabled, onClick }) =>
    html`<button type="button" role="menuitem" className="row" disabled=${disabled} onClick=${onClick}>
      <span className="title">${title}</span>${shortcut && html`<span className="shortcut">${shortcut}</span>`}</button>`;
  const MenuSeparator = () => html`<div className="sep" />`;
  const MenuNote = ({ children }) => html`<div className="note">${children}</div>`;

  /**
   * A window: drag it by its title bar, resize it from its lower right
   * corner, and the green button takes it to full screen when `onZoom` is
   * given. The front one is active.
   */
  function Window({
    id, title, x, y, width, height, minWidth = 320, minHeight = 200, resizable = true, full = false, active = true,
    centeredTitle, onClose, onZoom, onFocus, z = 10, children,
  }) {
    const { scale, w: sw, h: sh, menuBar, notch } = useScreen();
    const [frame, setFrame] = useState({ x, y, w: width, h: height });
    const drag = useRef(null);
    const begin = (mode) => (e) => {
      onFocus && onFocus(id);
      if (mode === 'move' && e.target.closest('.traffic')) return;
      e.stopPropagation();
      drag.current = { mode, sx: e.clientX, sy: e.clientY, f: frame };
      e.currentTarget.setPointerCapture(e.pointerId);
    };
    const move = (e) => {
      const d = drag.current;
      if (!d) return;
      const dx = (e.clientX - d.sx) / scale;
      const dy = (e.clientY - d.sy) / scale;
      if (d.mode === 'move') setFrame({ ...d.f, x: d.f.x + dx, y: Math.max(menuBar, d.f.y + dy) });
      else setFrame({ ...d.f, w: Math.max(minWidth, d.f.w + dx), h: Math.max(minHeight, d.f.h + dy) });
    };
    const end = () => (drag.current = null);
    const top = notch ? menuBar : 0;
    const style = full
      ? { left: 0, top, width: sw, height: sh - top, zIndex: 35 }
      : { left: frame.x, top: frame.y, width: frame.w, height: frame.h, zIndex: z };
    const cls = ['window', !active && 'inactive', full && 'full'].filter(Boolean).join(' ');
    return html`<section className=${cls} aria-label=${title} style=${style} onPointerDown=${() => onFocus && onFocus(id)}>
      <div className=${centeredTitle ? 'titlebar centered' : 'titlebar'} onPointerDown=${full ? undefined : begin('move')}
        onPointerMove=${move} onPointerUp=${end}>
        <div className="traffic">
          <span className="r" title="Close" onClick=${onClose} /><span className="y" />
          <span className=${onZoom ? 'g zoom' : 'g'} title=${onZoom ? (full ? 'Exit Full Screen' : 'Enter Full Screen') : undefined}
            onClick=${onZoom} />
        </div>
        <span className="title">${title}</span>
      </div>
      <div className="body">${children}</div>
      ${resizable && !full && html`<div className="grip" aria-hidden="true" onPointerDown=${begin('resize')}
        onPointerMove=${move} onPointerUp=${end} />`}
    </section>`;
  }

  /** Scenery: a document someone is writing, behind everything. */
  function DocumentWindow(props) {
    return html`<${Window} ...${props} centeredTitle=${true}>
      <div style=${{ position: 'absolute', inset: 0, background: 'var(--doc-paper)', color: 'var(--doc-ink)',
        padding: '28px 44px', fontFamily: 'var(--font-serif)', fontSize: 15, lineHeight: 1.6, overflow: 'hidden' }}>
        <h2 style=${{ font: '600 22px var(--font-serif)', margin: '0 0 14px' }}>Mendoza, cuatro días</h2>
        <p style=${{ margin: '0 0 12px' }}>Salimos el jueves temprano. La idea es dormir dos noches en Chacras y dos
          en el Valle de Uco, y dejar un día libre por si llueve, aunque en Mendoza casi nunca llueve.</p>
        <p style=${{ margin: '0 0 12px' }}>Para el viernes: subir hasta Potrerillos y, si el cielo está limpio, ver el
          Aconcagua desde el mirador. Llevar abrigo: a esa altura el viento corta.</p>
        <p style=${{ margin: 0 }}>Pendiente: reservar la bodega del sábado, comprar el repelente y averiguar si el
          camino a Las Cuevas está abierto<span style=${{ borderLeft: '2px solid var(--accent)', marginLeft: 1 }} /></p>
      </div>
    </${Window}>`;
  }

  /** Scenery: a video playing, while the mock watches one. */
  function VideoWindow(props) {
    return html`<${Window} ...${props}>
      <div className="video">
        <div className="frame"><span className="caption">Las nubes, episodio 3</span></div>
        <div className="bar"><span>12:41</span><span className="track"><i /></span><span>48:10</span></div>
      </div>
    </${Window}>`;
  }

  /** Scenery: a video call, while the mock is in a meeting. */
  function CallWindow({ onLeave, ...props }) {
    const people = [
      ['AL', '#5e8bd6'],
      ['MR', '#c77d4a'],
      ['JP', '#4fa37a'],
      ['You', '#8c6cc9'],
    ];
    return html`<${Window} ...${props} onClose=${onLeave}>
      <div style=${{ position: 'absolute', inset: 0, background: 'var(--call-bg)', padding: 10, display: 'grid',
        gridTemplateColumns: '1fr 1fr', gridTemplateRows: '1fr 1fr auto', gap: 8 }}>
        ${people.map(
          ([who, c]) => html`<div key=${who} style=${{ background: 'var(--call-tile)', borderRadius: 10, display: 'grid',
            placeItems: 'center', position: 'relative' }}>
            <span style=${{ width: 44, height: 44, borderRadius: '50%', background: c, color: '#fff', display: 'grid',
              placeItems: 'center', fontWeight: 600, fontSize: 13 }}>${who}</span>
            <span style=${{ position: 'absolute', left: 8, bottom: 6, fontSize: 10, color: 'var(--call-label)' }}>${who}</span>
          </div>`,
        )}
        <div style=${{ gridColumn: '1 / 3', display: 'flex', justifyContent: 'center', paddingTop: 2 }}>
          <button type="button" className="btn" style=${{ background: 'var(--red)', color: '#fff' }} onClick=${onLeave}>
            Leave</button>
        </div>
      </div>
    </${Window}>`;
  }

  // ---------------------------------------------------------------------
  // MenuContent: Ficha's menu in the menu bar.
  // ---------------------------------------------------------------------
  function MenuContent({ app, state, onCapture, onReviewNow, onAddDeck, dismiss, extraRows }) {
    const due = app.dueCount();
    const run = (fn) => () => {
      dismiss();
      fn && fn();
    };
    return html`
      <${MenuRow} title="Capture…" shortcut="⌃⌥⌘C" onClick=${run(onCapture)} />
      <${MenuRow} title=${`Review now (${due} due)`} onClick=${run(onReviewNow)} />
      <${MenuSeparator} />
      <${MenuNote}>${app.learnedCount()} cards learned · ${state.inbox} in the inbox</${MenuNote}>
      ${extraRows}
      <${MenuRow} title="Diagnostics" disabled=${true} />
      <${MenuRow} title="Settings…" shortcut="⌘ ," disabled=${true} />
      <${MenuSeparator} />
      <${MenuRow} title="Quit" shortcut="⌘ Q" disabled=${true} />`;
  }

  // ---------------------------------------------------------------------
  // ReviewPanelView.
  // ---------------------------------------------------------------------
  const RATINGS = {
    four: [
      { g: 1, name: 'Again', key: '1' },
      { g: 2, name: 'Hard', key: '2' },
      { g: 3, name: 'Good', key: '3' },
      { g: 4, name: 'Easy', key: '4' },
    ],
    // A simpler face for the same stored ratings: Forgot is Again, Got it is Good.
    two: [
      { g: 1, name: 'Forgot', key: '1' },
      { g: 3, name: 'Got it', key: '2' },
    ],
  };
  const isTyping = (el) => el && (el.tagName === 'TEXTAREA' || el.tagName === 'INPUT');

  /**
   * The review panel, centered 40 points under the menu bar. ⌘+, ⌘− and ⌘0
   * change the card's size: its text grows, and the panel widens above 100%,
   * while its buttons keep their size. A card taller than two thirds of the
   * screen's free height scrolls, its buttons staying in view.
   */
  function ReviewPanelView({ app, state, ratings = 'four', dock = true }) {
    const { w, h, menuBar } = useScreen();
    const [panel, leaving] = usePresence(state.panel);
    const [text, setText] = useState('');
    const field = useRef(null);
    const buttons = RATINGS[ratings] || RATINGS.four;

    // The keys, as the real panel takes them while it has the keyboard.
    useEffect(() => {
      if (!state.panel) return;
      const onKey = (e) => {
        const p = app.state.panel;
        if (!p) return;
        const typing = isTyping(e.target);
        const handled = () => {
          e.preventDefault();
          e.stopPropagation();
        };
        if (typing) {
          if (e.key === 'Escape' && p.mode) {
            handled();
            app.setMode(null);
          }
          return;
        }
        if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'z') return handled(), app.undo();
        if ((e.metaKey || e.ctrlKey) && ['+', '=', '-', '0'].includes(e.key)) {
          return handled(), app.setCardSize(e.key === '=' ? '+' : e.key);
        }
        if (e.metaKey || e.ctrlKey || e.altKey) return;
        if (e.key === 'Escape') return handled(), p.mode ? app.setMode(null) : app.close();
        if (p.kind === 'empty' || p.done) {
          if (e.key === 'Enter') handled(), app.close();
          return;
        }
        if (e.key === ' ') return handled(), p.flipped ? app.rate(3) : app.flip();
        if (p.flipped) {
          const b = buttons.find((b) => b.key === e.key);
          if (b) return handled(), app.rate(b.g);
        }
        const k = e.key.toLowerCase();
        if (k === 'a') return handled(), setText(''), app.setMode('ask');
        if (k === 'm') return handled(), setText(''), app.setMode('flag');
        if (k === 'e') return handled(), app.bury();
      };
      window.addEventListener('keydown', onKey, true);
      return () => window.removeEventListener('keydown', onKey, true);
    }, [!!state.panel, ratings]);

    useEffect(() => {
      if (panel && panel.mode && field.current) field.current.focus();
    }, [panel && panel.mode]);

    if (!panel) return null;
    const width = Math.max(400, 4 * state.cardSize);
    const maxHeight = Math.floor(((h - menuBar - (dock ? DOCK : 0)) * 2) / 3);
    const style = {
      left: Math.round((w - width) / 2),
      top: menuBar + 40,
      width,
      maxHeight,
      '--card-scale': state.cardSize / 100,
    };
    const cls = `panel glass${leaving ? ' leaving' : ''}`;
    const toast = state.toast && html`<div className="toast glass">${state.toast.text}</div>`;
    const close = html`<${IconButton} icon=${Icon.close} label="Close (esc)" onClick=${() => app.close()} />`;
    const undo = html`<${IconButton} icon=${Icon.undo} label="Undo (⌘Z)" disabled=${!panel.undo.length}
      onClick=${() => app.undo()} />`;

    if (panel.kind === 'empty') {
      return html`<div className=${cls} style=${style} role="dialog" aria-label="Review">
        <div className="header"><div className="lead"><span className="done-title">No cards to review right now.</span></div>
          <div className="icons">${close}</div></div>${toast}</div>`;
    }
    if (panel.done) {
      return html`<div className=${cls} style=${style} role="dialog" aria-label="Review">
        <div className="header"><div className="lead"><span className="done-title">You went through every card.</span></div>
          <div className="icons">${undo}${close}</div></div>
        <div className="flip-row"><${Button} prominent title="Done" k="↩" onClick=${() => app.close()} /></div>
        ${toast}</div>`;
    }

    const card = app.card(panel.queue[panel.index]);
    const deck = app.deck(card.deckId);
    const isNew = card.state === 'new';
    const previews = panel.flipped ? E.preview(card, state.now, app.scheduler) : null;
    const writing = panel.mode;
    const submit = () => {
      app.saveToInbox(writing);
      setText('');
    };
    return html`<div className=${cls} style=${style} role="dialog" aria-label="Review"
      onPointerDown=${() => app.touch()}>
      <div className="sides">
      <div className="header">
        <div className="lead">
          <div className="topline">
            <${Capsule}>${deck.emoji} ${deck.name}</${Capsule}>
            ${card.tags.map((t) => html`<${Capsule} key=${t}>${t}</${Capsule}>`)}
            ${isNew && html`<${Capsule} tint>New</${Capsule}>`}
          </div>
          <div className="upper">${card.front}</div>
        </div>
        <div className="icons">
          ${!writing && html`${undo}
            <${IconButton} icon=${Icon.ask} label="Ask… (a)" onClick=${() => (setText(''), app.setMode('ask'))} />
            <${IconButton} icon=${Icon.flag} label="Flag… (m)" onClick=${() => (setText(''), app.setMode('flag'))} />
            <${IconButton} icon=${Icon.bury} label="Bury (e)" onClick=${() => app.bury()} />`}
          ${close}
        </div>
      </div>
      ${panel.flipped &&
      html`<div className="lower"><${Divider} /><div className="text">${card.back}</div>
        ${card.source && html`<div className="source">${card.source}</div>`}</div>`}
      </div>
      ${writing
        ? html`<form className="writing controls" onSubmit=${(e) => (e.preventDefault(), text.trim() && submit())}>
            <textarea ref=${field} id="panel-writing" className="field" rows="2" value=${text}
              placeholder=${writing === 'ask' ? 'What do you want to know?' : 'What needs fixing?'}
              onInput=${(e) => setText(e.target.value)}
              onKeyDown=${(e) => e.key === 'Enter' && !e.shiftKey && (e.preventDefault(), text.trim() && submit())} />
            <div className="actions">
              <${Button} title="Cancel" k="esc" onClick=${() => app.setMode(null)} />
              <${Button} prominent title=${writing === 'ask' ? 'Ask' : 'Flag'} k="↩" disabled=${!text.trim()}
                onClick=${submit} />
            </div>
          </form>`
        : panel.flipped
          ? html`<div className="ratings controls" style=${{ '--count': buttons.length }}>
              ${buttons.map(
                (b) => html`<div className="rating" key=${b.g}>
                  <span className="ivl">${E.formatInterval(previews[b.g].wait)}</span>
                  <${Button} wide title=${b.name} k=${b.key} onClick=${() => app.rate(b.g)} />
                </div>`,
              )}</div>`
          : html`<div className="flip-row"><${Button} prominent title="Flip" k="space" onClick=${() => app.flip()} /></div>`}
      ${toast}
    </div>`;
  }

  // ---------------------------------------------------------------------
  // CaptureView, in its window.
  // ---------------------------------------------------------------------
  function CaptureView({ onSave, onCancel, ...win }) {
    const [text, setText] = useState('');
    const [note, setNote] = useState('');
    const [source, setSource] = useState('');
    const first = useRef(null);
    useEffect(() => first.current && first.current.focus(), []);
    const save = () => text.trim() && onSave({ text, note, source });
    return html`<${Window} title="Capture" width=${420} height=${248} onClose=${onCancel} ...${win}>
      <form style=${{ padding: '4px 16px 16px', display: 'flex', flexDirection: 'column', gap: 10 }}
        onSubmit=${(e) => (e.preventDefault(), save())}
        onKeyDown=${(e) => e.key === 'Escape' && (e.stopPropagation(), onCancel())}>
        <textarea ref=${first} id="capture-text" className="field" rows="3" placeholder="A word, a concept, a quote or a question"
          value=${text} onInput=${(e) => setText(e.target.value)} />
        <input id="capture-note" className="field" placeholder="Note (optional)" value=${note}
          onInput=${(e) => setNote(e.target.value)} />
        <input id="capture-source" className="field" placeholder="Source (optional): a book, a podcast…" value=${source}
          onInput=${(e) => setSource(e.target.value)} />
        <div style=${{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 2 }}>
          <${Button} title="Cancel" onClick=${onCancel} />
          <${Button} prominent title="Save" disabled=${!text.trim()} onClick=${save} />
        </div>
      </form>
    </${Window}>`;
  }

  /** A note on the desktop, under the menu bar, when no panel is open. */
  const DeskToast = ({ state }) =>
    state.toast && !state.panel ? html`<div className="desk-toast glass">${state.toast.text}</div>` : null;

  // ---------------------------------------------------------------------
  // MockControls: the bar under the fake Mac. Not part of Ficha.
  // ---------------------------------------------------------------------
  const SPEEDS = [
    { value: 1, label: 'Real time' },
    { value: 60, label: '1 min/s' },
    { value: 600, label: '10 min/s' },
    { value: 3600, label: '1 h/s' },
  ];
  function HudGroup({ label, children, grow }) {
    return html`<div className=${grow ? 'hud-group grow' : 'hud-group'}><span className="hud-label">${label}</span>
      <div className="hud-row">${children}</div></div>`;
  }
  function HudChoice({ options, value, onChange, label }) {
    return html`<div className="hud-choice" role="group" aria-label=${label}>
      ${options.map(
        (o) => html`<button type="button" key=${String(o.value)} aria-pressed=${o.value === value}
          onClick=${() => onChange(o.value)}>${o.label}</button>`,
      )}</div>`;
  }
  const BUSY = [
    { value: null, label: 'Free' },
    { value: 'meeting', label: 'Meeting' },
    { value: 'video', label: 'Video' },
    { value: 'fullScreen', label: 'Full-screen app' },
  ];
  const WALLPAPERS = [
    { value: 'sky', label: 'Sky' },
    { value: 'dunes', label: 'Dunes' },
    { value: 'forest', label: 'Forest' },
  ];
  function nextLine(app, state) {
    if (state.panel) return 'The panel is open';
    const next = app.nextAppearance();
    if (!next) return 'Nothing to bring yet';
    if (next.heldBack && next.at <= state.now) return `Held back: ${E.SUPPRESSIONS[state.suppression]}`;
    return `Next appearance ${formatWait(next.at - state.now, next.at)}`;
  }
  const HudSelect = ({ id, label, value, options, onChange }) =>
    html`<select id=${id} className="hud-select" aria-label=${label} value=${value} onChange=${(e) => onChange(e.target.value)}>
      ${options.map((o) => html`<option key=${o.value} value=${o.value}>${o.label}</option>`)}</select>`;

  /** The browser's own full screen, for the whole page. */
  function useFullscreen(onRefused) {
    const [full, setFull] = useState(!!document.fullscreenElement);
    useEffect(() => {
      const on = () => setFull(!!document.fullscreenElement);
      document.addEventListener('fullscreenchange', on);
      return () => document.removeEventListener('fullscreenchange', on);
    }, []);
    const toggle = () => {
      if (document.fullscreenElement) return document.exitFullscreen();
      const el = document.documentElement;
      const request = el.requestFullscreen || el.webkitRequestFullscreen;
      if (!request) return onRefused();
      try {
        const done = request.call(el);
        if (done && done.catch) done.catch(onRefused);
      } catch (_) {
        onRefused();
      }
    };
    return [full, toggle];
  }

  function MockControls({ app, state, look, setLook, screen, setScreen, screenScale = 1, variants, about, onReset }) {
    const [open, setOpen] = useState(null);
    const [hidden, setHidden] = useState(false);
    const refused = () => {
      app.toast("The browser didn't allow full screen here. Open the mock in a tab of its own.");
      app.emit();
    };
    const [full, toggleFull] = useFullscreen(refused);
    // Full screen hides the bar, and leaving it brings the bar back.
    useEffect(() => setHidden(full), [full]);
    const toggle = (what) => setOpen(open === what ? null : what);
    if (hidden) {
      return html`<button type="button" className="hud-pill" title="Show the mock's bar" onClick=${() => setHidden(false)}>
        Mock ▴</button>`;
    }
    return html`<footer className="hud">
      ${open === 'log' &&
      html`<div className="hud-pop" role="log">
        <strong>What happened</strong>
        ${state.log.length
          ? html`<ol>${state.log.map(
              (l, i) => html`<li key=${i} data-kind=${l.kind}><time>${formatTime(l.t)}</time> ${l.text}</li>`,
            )}</ol>`
          : html`<p>Nothing yet. Speed the clock up, or skip to the next appearance.</p>`}
      </div>`}
      ${open === 'about' && html`<div className="hud-pop">${about}</div>`}
      <div className="hud-inner">
        <span className="hud-badge" title="Everything in this bar is the mock's, not Ficha's">Mock</span>
        <${HudGroup} label="Clock">
          <button type="button" className="hud-btn icon" aria-label=${state.paused ? 'Run the clock' : 'Pause the clock'}
            onClick=${() => app.togglePause()}>${state.paused ? Icon.play(14) : Icon.pause(14)}</button>
          <${HudChoice} label="Speed" options=${SPEEDS} value=${state.paused ? null : state.speed}
            onChange=${(v) => app.setSpeed(v)} />
        </${HudGroup}>
        <${HudGroup} label=${nextLine(app, state)} grow>
          <button type="button" className="hud-btn" onClick=${() => app.skipToNextAppearance()}
            disabled=${!!state.panel}>${Icon.skip(13)} Skip to it</button>
          <${HudChoice} label="What you're doing" options=${BUSY} value=${state.suppression}
            onChange=${(v) => app.setSuppression(v)} />
        </${HudGroup}>
        ${variants}
        <${HudGroup} label=${screenScale < 1 ? `Screen · shown at ${Math.round(screenScale * 100)}%` : 'Screen'}>
          <${HudSelect} id="mock-screen" label="Screen size" value=${screen} onChange=${setScreen}
            options=${SCREENS.map((x) => ({ value: x.id, label: x.label }))} />
          <button type="button" className="hud-btn" aria-pressed=${full} onClick=${toggleFull}>
            ${full ? 'Exit full screen' : 'Full screen'}</button>
        </${HudGroup}>
        <${HudGroup} label="Card size">
          <div className="hud-choice">
            <button type="button" aria-label="Smaller (⌘−)" onClick=${() => app.setCardSize('-')}>−</button>
            <button type="button" aria-label="Normal size (⌘0)" title="⌘0" onClick=${() => app.setCardSize('0')}>
              ${state.cardSize}%</button>
            <button type="button" aria-label="Larger (⌘+)" onClick=${() => app.setCardSize('+')}>+</button>
          </div>
        </${HudGroup}>
        <${HudGroup} label="Look">
          <${HudChoice} label="Appearance" value=${look.theme} onChange=${(theme) => setLook({ ...look, theme })}
            options=${[{ value: 'auto', label: 'Auto' }, { value: 'light', label: 'Light' }, { value: 'dark', label: 'Dark' }]} />
          <${HudSelect} id="mock-wallpaper" label="Wallpaper" value=${look.wallpaper} options=${WALLPAPERS}
            onChange=${(wallpaper) => setLook({ ...look, wallpaper })} />
        </${HudGroup}>
        <div className="hud-group end">
          <button type="button" className="hud-btn" aria-pressed=${open === 'log'} onClick=${() => toggle('log')}>
            Log ${state.log.length ? html`<span className="hud-count">${state.log.length}</span>` : null}</button>
          <button type="button" className="hud-btn" aria-pressed=${open === 'about'} onClick=${() => toggle('about')}>
            About</button>
          <button type="button" className="hud-btn" onClick=${onReset}>Reset</button>
          <button type="button" className="hud-btn" title="Hide this bar" onClick=${() => setHidden(true)}>Hide ▾</button>
        </div>
      </div>
    </footer>`;
  }

  /** Sets the page's light or dark, putting back the viewer's own on Auto. */
  function useTheme(theme) {
    const original = useRef(document.documentElement.getAttribute('data-theme'));
    useEffect(() => {
      const el = document.documentElement;
      if (theme === 'auto') {
        if (original.current) el.setAttribute('data-theme', original.current);
        else el.removeAttribute('data-theme');
      } else el.setAttribute('data-theme', theme);
    }, [theme]);
  }

  root.FichaUI = {
    html,
    Icon,
    useStore,
    useClock,
    usePresence,
    useScreen,
    useTheme,
    formatClock,
    formatTime,
    formatDay,
    formatDayRange,
    formatWait,
    Button,
    IconButton,
    KeyLabel,
    Capsule,
    Divider,
    Segmented,
    Stage,
    MenuBar,
    Menu,
    MenuRow,
    MenuSeparator,
    MenuNote,
    Window,
    Dock,
    DocumentWindow,
    VideoWindow,
    CallWindow,
    SCREENS,
    DOCK,
    MenuContent,
    ReviewPanelView,
    CaptureView,
    DeskToast,
    MockControls,
    HudGroup,
    HudChoice,
    RATINGS,
  };
})(window);
