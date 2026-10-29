'use strict';

/* Заставка Mini App: единая canvas-сцена (порт mini-app/loading.html).
   Раньше блик был DOM-элементом поверх canvas (в координатах #stage) —
   при масштабировании сцены и на высоком devicePixelRatio он уезжал и
   «плыл» относительно планеты. Теперь планета, световое проявление,
   след и блик рисуются в ОДНОЙ canvas 640×640: геометрия физически
   не может разъехаться.

   Жизненный цикл — в конце файла: анимация отыгрывает ЦЕЛИКОМ,
   уходим, когда отыграл финал И Flutter отрисовал первый кадр
   (window.finalsSplash.finish() — от события flutter-first-frame). */

const IMG = 640;
const TARGET = { x: 383, y: 247 }; // центр звёздочки сияния в оригинале

// Динамика «как машина»: пружинный доезд после остановки блика.
const DYN = {
  accel: 950,        // разгон, px/s² (маршрут убран — оставлено для совместимости)
  springK: 81,       // жёсткость пружины возврата (ω≈9 рад/с)
  springZeta: 0.3,   // демпфирование (0.3 — лёгкое колебание, «проскочил и вернулся»)
};

// Тайминг сцены (сек)
const T = {
  fadeIn: 0.45,      // появление блика на старте
  holdAfterArrival: 0.25,
  reveal: 1.8,       // проявление логотипа световым фронтом
  glintFade: 1.3,    // растворение блика
  rise: 1.7,         // подъём логотипа наверх
  riseDist: 150,     // насколько высоко (px), чтобы влезла надпись
  riseScl: 0.02,     // едва заметный рост планеты за подъём
  title: 0.9         // проявление надписи DARKSIDE
};

const params = new URLSearchParams(location.search);

/* --- элементы разметки --- */
const scene = document.getElementById('scene');
const sceneCtx = scene.getContext('2d');
const stage = document.getElementById('stage');
const logoGroup = document.getElementById('logoGroup');
const title = document.getElementById('title');
const subtitle = document.getElementById('subtitle');
const splashEl = document.getElementById('splash');

/* --- буферы единой сцены --- */
const baseBuf = document.createElement('canvas'); baseBuf.width = 640; baseBuf.height = 640;
const topBuf = document.createElement('canvas'); topBuf.width = 640; topBuf.height = 640;
const scratch = document.createElement('canvas'); scratch.width = 640; scratch.height = 640;
const scratchCtx = scratch.getContext('2d');
const trailBuf = document.createElement('canvas'); trailBuf.width = 640; trailBuf.height = 640;
const trailCtx = trailBuf.getContext('2d');

/* Логотип: вычищенный от звёзд кадр заготовлен офлайн (logo-clean.jpg),
   звезда-сияние в нём сохранена. Чистка в браузере не нужна — это
   ~250 мс на десктопе и до секунды на телефоне ровно в тот момент,
   когда и так грузится Flutter. Пока картинка не готова, таймлайн
   стоит на нуле, чтобы анимация не отыграла по пустому canvas. */
const logoSrc = new Image();
logoSrc.src = 'splash/logo-clean.jpg';
let assetsReady = false;
logoSrc.decode().catch(() => {}).then(() => {
  baseBuf.getContext('2d').drawImage(logoSrc, 0, 0, IMG, IMG);
  topBuf.getContext('2d').drawImage(logoSrc, 0, 0, IMG, IMG);
  assetsReady = true;
  startLoop(); // на случай, если старт ждал картинку (?t= отладка)
});

/* =========================================================
   Машина состояний
   ========================================================= */
const ST = { FADE_IN: 1, TRAVEL: 2, SETTLE: 3, REVEAL: 4, GLINT_FADE: 5, RISE: 6, TITLE: 7, END: 8 };

let state = ST.FADE_IN, tState = 0, tAbs = 0;
let glintAlpha = 0;
let settleOff = 0, settleVel = 0;
let revealAt = -1;
let groupY = 0, groupScale = 1, glintFadeStart = null;
/* маска проявления и прозрачности слоёв — считаются в JS (единая сцена) */
let maskA = -76, maskB = 0, baseO = 0, topO = 0, baseFlash = 0, burstT = -9;

/* след блика: буферная канва с историей головы */
const glintHead = { x: TARGET.x, y: TARGET.y };
const headHist = [];        // история позиций блика {x, y, t}
const TRAIL_AGE = 1.6;      // точка следа живёт 1.6 с и мягко гаснет по возрасту
const TRAIL_HALO_W = 5.5;   // толщина ореола
const TRAIL_CORE_W = 2;     // толщина сердечника

/* --- пружина инерции: блик «доезжает» и откатывается --- */
function settleStep(dt) {
  const w = Math.sqrt(DYN.springK), c = 2 * DYN.springZeta * w;
  settleVel += (-DYN.springK * settleOff - c * settleVel) * dt;
  settleOff += settleVel * dt;
}

/* --- вспышка при остановке: процедурная (внутри drawGlint) --- */
function burst() {
  burstT = tAbs;
}

/* плавное проявление: easeInOutSine — очень мягкий, ровный драпинг слева направо */
const easeReveal = u => 0.5 - 0.5 * Math.cos(Math.PI * u);

function onArrive() {
  state = ST.SETTLE; tState = 0;
  burst();
  // REVEAL открываем по таймлайну (не setTimeout): тогда ?t= для отладки
  // идёт ровно по тем же кадрам, что и живая анимация.
  revealAt = tAbs + T.holdAfterArrival;
}

/* =========================================================
   Цикл: step + render
   ========================================================= */
function step(dt) {
  switch (state) {
    case ST.FADE_IN:
      glintAlpha = Math.min(1, tState / T.fadeIn);
      if (tState >= T.fadeIn) onArrive();
      break;
    case ST.SETTLE:
      settleStep(dt);
      if (revealAt !== -1 && tAbs >= revealAt) {
        revealAt = -1;
        state = ST.REVEAL; tState = 0;
      }
      break;
    case ST.REVEAL:
      settleStep(dt);
      /* «Игра со светом»:
         — нижний слой: вся картинка медленно загорается (правый край висит ~30%);
         — верхний слой: очень широкий размытый фронт света ползёт слева направо;
         — в середине фазы нижний слой вспыхивает (яркость) и гаснет в норму. */
      const pr = Math.min(1, tState / T.reveal);
      const ev = easeReveal(pr);
      const c = -0.38 + 1.76 * ev;             // фронт света
      const WA = 0.38;                          // полширины «дымки» фронта
      maskA = (c - WA) * 100;                   // front-параметры читает render()
      maskB = (c + WA) * 100;
      topO = 1;
      baseO = 0.3 * easeReveal(Math.min(1, pr / 0.8));
      baseFlash = 0.28 * Math.exp(-Math.pow((ev - 0.5) / 0.22, 2)); // «вспышка» середины фазы
      if (tState >= T.reveal) { state = ST.GLINT_FADE; tState = 0; }
      break;
    case ST.GLINT_FADE:
      if (glintFadeStart === null) glintFadeStart = tAbs;
      glintAlpha = Math.max(0, 1 - (tAbs - glintFadeStart) / T.glintFade);
      // подъём стартует, пока блик ещё растворяется (~55%) — без паузы
      if (glintAlpha <= 0.55) { state = ST.RISE; tState = 0; }
      break;
    case ST.RISE: {
      /* Подъём: easeInOutQuint — долгий разгон, плавный центральный ход,
         долгое торможение. Без перелётов. */
      if (glintFadeStart !== null) glintAlpha = Math.max(0, 1 - (tAbs - glintFadeStart) / T.glintFade);
      const p = Math.min(1, tState / T.rise);
      const q = p < 0.5 ? 16 * p ** 5 : 1 - Math.pow(-2 * p + 2, 5) / 2;
      groupY = -T.riseDist * q;
      groupScale = 1 + T.riseScl * q;
      if (tState >= T.rise) { state = ST.TITLE; tState = 0; groupY = -T.riseDist; title.classList.add('shimmer'); }
      break;
    }
    case ST.TITLE: {
      const p = Math.min(1, tState / T.title);
      const o = easeReveal(p);
      title.style.opacity = o.toFixed(3);
      title.style.transform = `translateY(${(14 * (1 - o)).toFixed(2)}px)`;
      // подпись выезжает чуть позже основной надписи
      const p2 = Math.min(1, Math.max(0, (tState - T.title * 0.3) / (T.title * 0.7)));
      subtitle.style.opacity = easeReveal(p2).toFixed(3);
      subtitle.style.transform = `translateY(${(10 * (1 - easeReveal(p2))).toFixed(2)}px)`;
      if (tState >= T.title) {
        state = ST.END; tState = 0;
        // Анимация отыграла целиком: можно уходить, если приложение готово.
        animationEnded = true;
        tryClose();
      }
      break;
    }
    case ST.END: {
      /* Финальный кадр держим, пока не придёт первый кадр Flutter:
         надпись уже проявилась, блик погас — заставка «стоит». */
      break;
    }
  }
  // след: перерисовка цельной линией по истории головы
  drawTrail();
}

/* --- след блика: одна непрерывная сглаженная линия с градиентной тенью --- */
function drawTrail() {
  const c = trailCtx;
  c.clearRect(0, 0, IMG, IMG);
  if (glintAlpha <= 0) return;

  // историю пополняем ТОЛЬКО пока блик «летит» (у нас это фаза появления) —
  // пружинный доезд после остановки не рисуется; после остановки
  // история просто старится и выцветает
  if (state === ST.FADE_IN) {
    headHist.push({ x: glintHead.x, y: glintHead.y, t: tAbs });
  }
  // история стареет: точки старше TRAIL_AGE — удаляем
  const tCut = tAbs - TRAIL_AGE;
  while (headHist.length > 2 && headHist[0].t < tCut) headHist.shift();

  const n = headHist.length;
  if (n < 2) return;

  // рисуем ПО СЕГМЕНТАМ с прозрачностью по возрасту: каждая точка гаснет
  // сама через TRAIL_AGE после рождения — «эстафетное» затухание следа
  c.lineCap = 'round';
  c.lineJoin = 'round';
  for (let i = 1; i < n; i++) {
    const a = headHist[i - 1], b = headHist[i];
    if (a.t < tCut) continue;
    const midAge = (tAbs - (a.t + b.t) / 2) / TRAIL_AGE;   // 0 (свежий) .. 1 (гаснет)
    if (midAge >= 1) continue;
    const fade = Math.pow(1 - midAge, 1.3);               // мягкое угасание
    // ореол-дымка
    c.strokeStyle = `rgba(255,150,205,${(fade * 0.62).toFixed(3)})`;
    c.lineWidth = TRAIL_HALO_W;
    c.beginPath();
    c.moveTo(a.x, a.y);
    c.lineTo(b.x, b.y);
    c.stroke();
    // светлое ядро
    c.strokeStyle = `rgba(255,236,245,${(fade * 0.72).toFixed(3)})`;
    c.lineWidth = TRAIL_CORE_W;
    c.beginPath();
    c.moveTo(a.x, a.y);
    c.lineTo(b.x, b.y);
    c.stroke();
  }
}

function render() {
  // блик всегда в финальной точке (маршрут убран)
  const x = TARGET.x, y = TARGET.y;
  glintHead.x = x; glintHead.y = y;

  // === ЕДИНАЯ СЦЕНА: планета, маска-проявление, след и блик —
  // === одна canvas, одна система координат (640×640).
  // === Блик физически не может «уехать»: рисуется там же, где планета. ===
  const rc = sceneCtx;
  rc.setTransform(1, 0, 0, 1, 0, 0);
  rc.globalCompositeOperation = 'source-over';
  rc.globalAlpha = 1;
  rc.clearRect(0, 0, IMG, IMG);

  // слой 1: вся картинка медленно набирает свет (+вспышка середины фазы)
  if (baseO > 0.001) {
    rc.globalAlpha = baseO;
    rc.drawImage(baseBuf, 0, 0);
    if (baseFlash > 0.001) {
      rc.globalCompositeOperation = 'lighter';
      rc.globalAlpha = baseFlash;
      rc.drawImage(baseBuf, 0, 0);
      rc.globalCompositeOperation = 'source-over';
    }
    rc.globalAlpha = 1;
  }

  // слой 2: проявление мягким световым фронтом (маска по горизонтали)
  if (topO > 0.001) {
    const s2 = scratchCtx;
    s2.setTransform(1, 0, 0, 1, 0, 0);
    s2.globalCompositeOperation = 'source-over';
    s2.globalAlpha = 1;
    s2.clearRect(0, 0, IMG, IMG);
    s2.drawImage(topBuf, 0, 0);
    s2.globalCompositeOperation = 'destination-in';
    const Apx = maskA * 6.4, Bpx = maskB * 6.4;
    const mg = s2.createLinearGradient(0, 0, IMG, 0);
    if (Apx <= 0) {
      mg.addColorStop(0, `rgba(0,0,0,${Math.max(0, 1 - (0 - Apx) / (Bpx - Apx || 1)).toFixed(3)})`);
      mg.addColorStop(Math.min(1, Bpx / IMG), 'rgba(0,0,0,0)');
    } else {
      mg.addColorStop(0, 'rgba(0,0,0,1)');
      mg.addColorStop(Math.min(1, Apx / IMG), 'rgba(0,0,0,1)');
      mg.addColorStop(Math.min(1, Bpx / IMG), 'rgba(0,0,0,0)');
    }
    s2.fillStyle = mg;
    s2.fillRect(0, 0, IMG, IMG);
    s2.globalCompositeOperation = 'source-over';
    rc.globalAlpha = topO;
    rc.drawImage(scratch, 0, 0);
    rc.globalAlpha = 1;
  }

  // след: рисуется своим буфером, тает вместе с бликом
  if (glintAlpha > 0.001) {
    rc.globalAlpha = glintAlpha;
    rc.drawImage(trailBuf, 0, 0);
    rc.globalAlpha = 1;
  }

  // блик: процедурно — на тех же самых координатах планеты
  if (glintAlpha > 0.001) drawGlint(rc, x, y, glintAlpha);

  // сдвиг группы (подъём наверх + лёгкий рост масштаба) — вся сцена едет одна
  logoGroup.style.transform = `translate(0px, ${groupY.toFixed(2)}px) scale(${groupScale.toFixed(4)})`;
}

/* --- процедурный блик: ореол+ядро+крест лучей (в координатах сцены) --- */
function drawGlint(rc, x, y, alpha) {
  const flash = Math.max(0, 1 - (tAbs - burstT) / 0.7);   // пик вспышки при появлении
  const grow = 1 + flash * 0.35;

  rc.save();
  rc.globalCompositeOperation = 'lighter';

  // ореол-дымка
  const haloR = 44 * grow;
  let g = rc.createRadialGradient(x, y, 0, x, y, haloR);
  g.addColorStop(0, `rgba(255,160,205,${Math.min(1, 0.14 * alpha * (1 + flash)).toFixed(3)})`);
  g.addColorStop(0.45, `rgba(255,160,205,${(0.05 * alpha).toFixed(3)})`);
  g.addColorStop(1, 'rgba(255,160,205,0)');
  rc.fillStyle = g;
  rc.beginPath(); rc.arc(x, y, haloR, 0, Math.PI * 2); rc.fill();

  // ядро
  const coreR = 19 * (1 + flash * 0.6);
  g = rc.createRadialGradient(x, y, 0, x, y, coreR);
  g.addColorStop(0, `rgba(255,255,255,${alpha.toFixed(3)})`);
  g.addColorStop(0.12, `rgba(255,255,255,${alpha.toFixed(3)})`);
  g.addColorStop(0.3, `rgba(255,236,245,${(0.92 * alpha).toFixed(3)})`);
  g.addColorStop(0.55, `rgba(255,175,210,${(0.5 * alpha).toFixed(3)})`);
  g.addColorStop(1, 'rgba(255,175,210,0)');
  rc.fillStyle = g;
  rc.beginPath(); rc.arc(x, y, coreR, 0, Math.PI * 2); rc.fill();

  // крест лучей (главный диагональный + вертикальный)
  const flares = [[118, 2.4, -18, 0.8], [84, 2.8, 72, 0.72]];
  for (const [len, wid, deg, opa] of flares) {
    rc.save();
    rc.translate(x, y);
    rc.rotate(deg * Math.PI / 180);
    const s = 1 + flash * 0.3;
    rc.scale(s, s);
    const lg = rc.createLinearGradient(-len / 2, 0, len / 2, 0);
    lg.addColorStop(0, 'rgba(255,255,255,0)');
    lg.addColorStop(0.5, `rgba(255,255,255,${(opa * alpha).toFixed(3)})`);
    lg.addColorStop(1, 'rgba(255,255,255,0)');
    rc.fillStyle = lg;
    rc.fillRect(-len / 2, -wid / 2, len, wid);
    rc.restore();
  }

  rc.restore();
}

/* масштабирование сцены под окно */
function fit() {
  const k = Math.min(innerWidth / IMG, innerHeight / IMG);
  stage.style.transform = `scale(${k})`;
}
addEventListener('resize', fit);
fit();

// рестарт по касанию выключен: в Mini App случайный тап не должен сбрасывать заставку

let lastNow = performance.now();
function loop(now) {
  const dt = Math.min((now - lastNow) / 1000, 0.05);
  lastNow = now;
  // ждём логотип, чтобы анимация не началась по пустому canvas
  if (!assetsReady) {
    requestAnimationFrame(loop);
    return;
  }
  // ?hold=1 — стоп-кадр: таймлайн стоит (отладка через ?t=)
  if (params.get('hold') === '1') {
    requestAnimationFrame(loop);
    return;
  }
  tAbs += dt;
  tState += dt;
  step(dt);
  render();
  requestAnimationFrame(loop);
}

/* старт; ?t=SECONDS — прыжок по таймлайну для отладки кадров.
   Если ?t= запрошен раньше, чем готов логотип, старт откладывается:
   seek отыгрывается от правильного нуля по тому же таймлайну,
   что и живая анимация; decode вызовет startLoop() повторно. */
let started = false;
function startLoop() {
  if (started) return;
  const seek = parseFloat(params.get('t'));
  if (!isNaN(seek) && !assetsReady) return;
  started = true;
  if (!isNaN(seek)) {
    const steps = Math.round(seek / 0.016);
    for (let i = 0; i < steps; i++) {
      if (state === ST.END) break;
      tAbs += 0.016;
      tState += 0.016;
      step(0.016);
      render(); // обновляем голову следа и слои, чтобы история не выглядела телепортом
    }
  }
  requestAnimationFrame(loop);
}

requestAnimationFrame(() => {
  requestAnimationFrame(() => { startLoop(); });
});

/* =========================================================
   Жизненный цикл заставки.
   Анимация проигрывается ЦЕЛИКОМ: блик → проявление логотипа →
   подъём → надпись DARKSIDE. Flutter сообщает о первом кадре через
   window.finalsSplash.finish(), но уходим мы только когда отыграл
   финал и приложение уже отрисовано: что наступит позже — того и ждём.
   ========================================================= */
const SHOW_AFTER_MS = 280;    // раньше не показываем: быстрый старт — без мигания
const HOLD_FINAL_MS = 450;    // пауза на финальном кадре, чтобы надпись прочиталась
const WATCHDOG_MS = 15000;    // страховка: заставка не должна держать вечно
let firstFrameAt = 0;
let animationEnded = false;
let closing = false;
let closeTimer = null;

// Показываем заставку, только если приложение ещё не готово.
setTimeout(function () {
  if (closing || firstFrameAt) return;
  splashEl.classList.add('splash-visible');
}, SHOW_AFTER_MS);

// Уходим, когда отыграл финал И приложение отрисовалось.
function tryClose() {
  if (closing || !animationEnded || !firstFrameAt || closeTimer) return;
  closeTimer = setTimeout(closeSplash, HOLD_FINAL_MS);
}

function closeSplash() {
  if (closing || !splashEl) return;
  closing = true;
  clearTimeout(closeTimer);
  splashEl.classList.add('splash-out');
  setTimeout(function () {
    if (splashEl.parentNode) splashEl.parentNode.removeChild(splashEl);
  }, 420);
}

window.finalsSplash = {
  finish: function () {
    if (firstFrameAt || closing) return;
    // ?splash=1 — режим отладки: держим заставку, чтобы рассмотреть кадры
    if (params.get('splash') === '1') return;
    firstFrameAt = performance.now();
    tryClose();
  },
  close: closeSplash,
  get done() { return closing; },
};

/* отладочная ручка для проверки кадров из консоли/автотестов */
window.__finalsDebug = {
  state: () => state,
  t: () => tAbs,
  assetsReady: () => assetsReady,
};

// Страховка: если анимация почему-то не доехала до финала (например,
// не загрузилась картинка), приложение всё равно должно открыться.
setTimeout(function () {
  if (firstFrameAt) closeSplash();
}, WATCHDOG_MS);
