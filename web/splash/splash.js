'use strict';

/* =========================================================
   ПУТЬ — сплайн по кольцу логотипа (домен 640×640).
   Гоним блик по верхней кромке кольца: от левого
   кончика к точке, где в исходнике стоит блик.
   ========================================================= */
const IMG = 640;

const TARGET = { x: 383, y: 247 }; // центр звёздочки сияния в оригинале (по пикселям)

// контрольные точки верхней кромки кольца (последняя = TARGET)
const CTRL = [
  { x: 104, y: 452 },
  { x: 119, y: 441 },
  { x: 133, y: 430 },
  { x: 147, y: 418 },
  { x: 160, y: 405 },
  { x: 174, y: 394 },
  { x: 188, y: 383 },
  { x: 201, y: 370 },
  { x: 209, y: 354 },
  { x: 213, y: 336 },
  { x: 217, y: 318 },
  { x: 221, y: 301 },
  { x: 227, y: 284 },
  { x: 237, y: 268 },
  { x: 250, y: 255 },
  { x: 264, y: 244 },
  { x: 280, y: 236 },
  { x: 297, y: 230 },
  { x: 315, y: 227 },
  { x: 333, y: 227 },
  { x: 351, y: 231 },
  { x: 368, y: 242 }
];

// Динамика «как машина»: разгон на прямой, торможение на поворотах
const DYN = {
  accel: 950,        // разгон, px/s²
  vCruise: 560,      // крейсерская скорость на прямом участке
  decel: 820,        // торможение перед остановкой
  brakeMargin: 12,   // запас тормозного пути: скорость в точке цели, даёт остаточную инерцию
  springK: 81,       // жёсткость пружины возврата (ω≈9 рад/с)
  springZeta: 0.3,   // демпфирование (0.3 — лёгкое колебание, «проскочил и вернулся»)
  curveGain: 6.5,    // сила замедления на поворотах
  curveFloor: 0.4    // минимальная доля крейсерской скорости
};

// Тайминг сцены (сек)
const T = {
  fadeIn: 0.45,      // появление блика на старте
  holdAfterArrival: 0.25,
  reveal: 1.8,       // проявление логотипа
  glintFade: 1.3,    // растворение блика-оверлея
  rise: 1.7,         // подъём логотипа наверх
  riseDist: 150,     // насколько высоко (px), чтобы влезла надпись
  riseScl: 0.02,     // едва заметный рост планеты за подъём
  title: 0.9         // проявление надписи DARKSIDE
};

/* Подготовка: очищенный от звёзд логотип лежит готовым файлом
   (logo-clean.jpg). Раньше он вычищался в браузере на лету, но это
   ~250 мс на десктопе и до секунды на телефоне — ровно в тот момент,
   когда и так грузится Flutter. Пока картинка не готова, таймлайн
   стоит на нуле, чтобы анимация не отыграла по пустому canvas. */
const logo = document.getElementById('logo');
const logoBase = document.getElementById('logoBase');
const logoSrc = new Image();
logoSrc.src = 'splash/logo-clean.jpg';
let assetsReady = false;
logoSrc.decode().catch(() => {}).then(() => {
  logo.getContext('2d').drawImage(logoSrc, 0, 0, 640, 640);
  logoBase.getContext('2d').drawImage(logoSrc, 0, 0, 640, 640);
  assetsReady = true;
});

/* =========================================================
   Сплайн Catmull-Rom → плотная таблица пути (длина дуги s)
   ========================================================= */
const SUB = 60; // сэмплов на сегмент
const samples = [];

function crPoint(p0, p1, p2, p3, t) {
  const t2 = t * t, t3 = t2 * t;
  return {
    x: 0.5 * ((2 * p1.x) + (-p0.x + p2.x) * t + (2 * p0.x - 5 * p1.x + 4 * p2.x - p3.x) * t2 + (-p0.x + 3 * p1.x - 3 * p2.x + p3.x) * t3),
    y: 0.5 * ((2 * p1.y) + (-p0.y + p2.y) * t + (2 * p0.y - 5 * p1.y + 4 * p2.y - p3.y) * t2 + (-p0.y + 3 * p1.y - 3 * p2.y + p3.y) * t3)
  };
}

{
  const P = [CTRL[0], ...CTRL, CTRL[CTRL.length - 1]];
  let prev = P[1];
  for (let i = 1; i < P.length - 2; i++) {
    for (let j = 0; j < SUB; j++) {
      const p = crPoint(P[i - 1], P[i], P[i + 1], P[i + 2], j / SUB);
      samples.push(p);
    }
  }
  samples.push(CTRL[CTRL.length - 1]);
}

// кумулятивная длина
const cumS = [0];
let sTotal = 0;
for (let i = 1; i < samples.length; i++) {
  sTotal += Math.hypot(samples[i].x - samples[i - 1].x, samples[i].y - samples[i - 1].y);
  cumS[i] = sTotal;
}

function pointAtS(sv) {
  const s = Math.min(Math.max(sv, 0), sTotal);
  // бинарный поиск
  let lo = 0, hi = cumS.length - 1;
  while (lo < hi) {
    const mid = (lo + hi) >> 1;
    if (cumS[mid] < s) lo = mid + 1; else hi = mid;
  }
  const i = Math.max(1, lo);
  const f = (s - cumS[i - 1]) / (cumS[i] - cumS[i - 1] || 1);
  return {
    x: samples[i - 1].x + (samples[i].x - samples[i - 1].x) * f,
    y: samples[i - 1].y + (samples[i].y - samples[i - 1].y) * f
  };
}

function tangentAtS(sv) {
  const p1 = pointAtS(Math.max(0, sv - 2)), p2 = pointAtS(sv + 2);
  const dx = p2.x - p1.x, dy = p2.y - p1.y, L = Math.hypot(dx, dy) || 1;
  return { x: dx / L, y: dy / L };
}

// кривизна по таблице: скорость на поворотах режем
let curveFactorIdx = sv => 0;
let smoothArrLookup = i => 1;
function speedFactor(sv) {
  const i = Math.min(samples.length - 1, Math.max(0, curveFactorIdx(sv)));
  return smoothArrLookup(i);
}

// простая связка: пересобрать фабрику в две функции
{
  const kappa = samples.map(() => 0);
  for (let i = 1; i < samples.length - 1; i++) {
    const d1 = { x: samples[i].x - samples[i - 1].x, y: samples[i].y - samples[i - 1].y };
    const d2 = { x: samples[i + 1].x - samples[i].x, y: samples[i + 1].y - samples[i].y };
    const l1 = Math.hypot(d1.x, d1.y) || 1, l2 = Math.hypot(d2.x, d2.y) || 1;
    const cross = Math.abs(d1.x * d2.y - d1.y * d2.x) / (l1 * l2);
    const ds = Math.max((cumS[i + 1] - cumS[i - 1]) / 2, 1e-6);
    kappa[i] = Math.asin(Math.min(1, cross)) / ds;
  }
  const kMax = Math.max(1e-9, ...kappa);
  const raw = kappa.map(kn0 => Math.max(DYN.curveFloor, 1 / (1 + DYN.curveGain * (kn0 / kMax))));
  const smooth = raw.map((_, i) => {
    let s = 0, n = 0;
    for (let j = Math.max(0, i - 8); j <= Math.min(samples.length - 1, i + 8); j++) { s += raw[j]; n++; }
    return s / n;
  });
  curveFactorIdx = sv => Math.min(samples.length - 1, Math.max(0, Math.round(sv / sTotal * (samples.length - 1))));
  smoothArrLookup = i => smooth[i];
}
const tangentEnd = tangentAtS(sTotal);

/* =========================================================
   Машина состояний
   ========================================================= */
const stage = document.getElementById('stage');
const logoGroup = document.getElementById('logoGroup');
const title = document.getElementById('title');
const subtitle = document.getElementById('subtitle');
const ST = { FADE_IN: 1, TRAVEL: 2, SETTLE: 3, REVEAL: 4, GLINT_FADE: 5, RISE: 6, TITLE: 7, END: 8 };

let state = ST.FADE_IN, tState = 0, tAbs = 0;
let s = 0, v = 0, arriveTime = 0, glintAlpha = 0;
let settleOff = 0, settleVel = 0;
let settled = false, revealPending = null;
let groupY = 0, groupScale = 1, glintFadeStart = null;

const glint = document.getElementById('glint');
const hint = document.getElementById('hint');
const core = glint.querySelector('.core');
const flareH = glint.querySelector('.flare.h');
const flareV = glint.querySelector('.flare.v');
let tangentAt = { x: 1, y: 0 };
const glintHead = { x: TARGET.x, y: TARGET.y }; // голова следа (координаты блика)

 // след блика: цельная сглаженная линия по истории головы
const trail = document.getElementById('trail');
const trailCtx = trail.getContext('2d');
const headHist = [];        // история позиций блика {x, y, t}
const TRAIL_AGE = 1.6;      // точка следа живёт 1.6 с и мягко гаснет по возрасту
let trailHasGone = false;   // след уже полностью угас
const TRAIL_HALO_W = 5.5;   // толщина ореола (постоянная вдоль линии)
const TRAIL_CORE_W = 2;     // толщина сердечника

function reset() {
  state = ST.FADE_IN; tState = 0;
  s = 0; v = 0; arriveTime = 0; glintAlpha = 0;
  if (revealPending !== null) { clearTimeout(revealPending); revealPending = null; }
  settled = false; settleOff = 0; settleVel = 0;
  logo.style.setProperty('--a', -76);
  logo.style.setProperty('--b', 0);
  logo.style.opacity = 0;
  logoBase.style.opacity = 0;
  logoBase.style.filter = 'brightness(1)';
  groupY = 0;
  groupScale = 1;
  glintFadeStart = null;
  logoGroup.style.transform = 'translate(0px, 0px)';
  title.style.opacity = 0;
  title.style.transform = 'translateY(14px)';
  title.classList.remove('shimmer');
  subtitle.style.opacity = 0;
  subtitle.style.transform = 'translateY(10px)';
  trailCtx.clearRect(0, 0, 640, 640);
  headHist.length = 0;
  trailHasGone = false;
  hint.style.opacity = 1;
}

/* --- шаг динамики: машина едет по дуге ---
   скорость = min( крейсер·кривизна, торможение по остатку ).
   Тормозной профиль оставляет остаточную скорость на цели →
   естественный инерционный проскок и пружинный возврат. */
function travelStep(dt) {
  const remaining = Math.max(sTotal + DYN.brakeMargin - s, 0);
  const vBrake = Math.sqrt(2 * DYN.decel * remaining);
  const vCurve = DYN.vCruise * speedFactor(Math.min(s, sTotal));
  const vTarget = Math.min(vCurve, vBrake);
  if (v < vTarget) v = Math.min(vTarget, v + DYN.accel * dt);
  else v = Math.max(vTarget, v - DYN.decel * 1.4 * dt);
  s += v * dt;
  if (s >= sTotal) {
    settleVel = Math.max(v, 0);
    if (settleVel < 30) settleVel = Math.max(settleVel, 30); // пусть будет живой проскок
    s = sTotal;
    v = 0;
    if (!settled) { settled = true; arriveTime = tAbs; onArrive(); }
  }
}

function onArrive() {
  state = ST.SETTLE; tState = 0;
  burst();
  revealPending = setTimeout(() => { state = ST.REVEAL; tState = 0; }, T.holdAfterArrival * 1000);
}

/* --- пружина инерции: полузатухающая, блик "доезжает" и откатывается --- */
function settleStep(dt) {
  const w = Math.sqrt(DYN.springK), c = 2 * DYN.springZeta * w;
  settleVel += (-DYN.springK * settleOff - c * settleVel) * dt;
  settleOff += settleVel * dt;
}

/* --- вспышка при остановке --- */
function burst() {
  flareH.animate([
    { transform: 'translate(-50%,-50%) rotate(-18deg) scale(.72)', opacity: .5 },
    { transform: 'translate(-50%,-50%) rotate(-18deg) scale(1.35)', offset: .3, opacity: 1 },
    { transform: 'translate(-50%,-50%) rotate(-18deg) scale(1)', opacity: 1 }
  ], { duration: 650, easing: 'cubic-bezier(.2,.8,.25,1)' });
  flareV.animate([
    { transform: 'translate(-50%,-50%) rotate(72deg) scale(.5)', opacity: .4 },
    { transform: 'translate(-50%,-50%) rotate(72deg) scale(1.25)', offset: .35, opacity: .9 },
    { transform: 'translate(-50%,-50%) rotate(72deg) scale(1)', opacity: .85 }
  ], { duration: 750, easing: 'cubic-bezier(.2,.8,.25,1)' });
  core.animate([
    { filter: 'blur(.5px) brightness(1)', transform: 'translate(-50%,-50%) scale(1)' },
    { filter: 'blur(0) brightness(1.6)', transform: 'translate(-50%,-50%) scale(1.5)', offset: .25 },
    { filter: 'blur(.5px) brightness(1)', transform: 'translate(-50%,-50%) scale(1)' }
  ], { duration: 850, easing: 'ease-out' });
}

/* плавное проявление: easeInOutSine — очень мягкий, ровный драпинг слева направо */
const easeReveal = u => 0.5 - 0.5 * Math.cos(Math.PI * u);

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
      break;
    case ST.REVEAL:
      settleStep(dt);
      /* «Игра со светом»:
         — нижний слой: вся картинка медленно загорается (правый край висит ~30%);
         — верхний слой: очень широкий размытый фронт света ползёт слева направо;
         — в середине фазы нижний слой вспыхивает (brightness) и гаснет в норму. */
      const pr = Math.min(1, tState / T.reveal);
      const ev = easeReveal(pr);
      const c = -0.38 + 1.76 * ev;             // фронт света
      const WA = 0.38;                          // полширины «дымки» фронта
      logo.style.setProperty('--a', ((c - WA) * 100).toFixed(2));
      logo.style.setProperty('--b', ((c + WA) * 100).toFixed(2));
      logo.style.opacity = 1;
      const baseO = 0.3 * easeReveal(Math.min(1, pr / 0.8));
      logoBase.style.opacity = baseO.toFixed(3);
      logoBase.style.filter = `brightness(${(1 + 0.28 * Math.exp(-Math.pow((ev - 0.5) / 0.22, 2))).toFixed(3)})`;
      if (tState >= T.reveal) { state = ST.GLINT_FADE; tState = 0; }
      break;
    case ST.GLINT_FADE:
      if (glintFadeStart === null) glintFadeStart = tAbs;
      glintAlpha = Math.max(0, 1 - (tAbs - glintFadeStart) / T.glintFade);
      // подъём стартует, пока блик ещё растворяется (~55%) — без паузы
      if (glintAlpha <= 0.55) { state = ST.RISE; tState = 0; hint.style.opacity = 0; }
      break;
    case ST.RISE: {
      /* Подъём: escalate-easing (easeInOutQuint) — долгий разгон,
         плавный центральный ход, долгое торможение. Без перелётов. */
      if (glintFadeStart !== null) glintAlpha = Math.max(0, 1 - (tAbs - glintFadeStart) / T.glintFade);
      const p = Math.min(1, tState / T.rise);
      const q = p < 0.5 ? 16 * p ** 5 : 1 - Math.pow(-2 * p + 2, 5) / 2; // easeInOutQuint
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
  c.clearRect(0, 0, 640, 640);
  if (glintAlpha <= 0) return;
  trail.style.opacity = glintAlpha.toFixed(3);

  // добавить текущую голову в историю; телепорт головы сбрасывает историю
  const lastPt = headHist.length ? headHist[headHist.length - 1] : { x: glintHead.x, y: glintHead.y };
  if (Math.hypot(glintHead.x - lastPt.x, glintHead.y - lastPt.y) > 60) headHist.length = 0;
  // историю пополняем ТОЛЬКО пока блик летит — пружинный доезд после
  // остановки не рисуется, чтобы не appeared «завиток»; после остановки
  // история просто старится и выцветает
  if (state === ST.TRAVEL || state === ST.FADE_IN) {
    const lastPt = headHist.length ? headHist[headHist.length - 1] : { x: glintHead.x, y: glintHead.y };
    if (Math.hypot(glintHead.x - lastPt.x, glintHead.y - lastPt.y) > 60) headHist.length = 0;
    headHist.push({ x: glintHead.x, y: glintHead.y, t: tAbs });
  }
  // история стареет: точки старше TRAIL_AGE с 0 — удаляем
  const tCut = tAbs - TRAIL_AGE;
  while (headHist.length > 2 && headHist[0].t < tCut) headHist.shift();

  const n = headHist.length;
  if (n < 2) { if (!headHist.length) trailHasGone = true; return; }

  // сглаженная кривая: рисуем ПО СЕГМЕНТАМ с прозрачностью по возрасту —
  // каждая точка гаснет сама через TRAIL_AGE после рождения (и в полёте,
  // и после остановки блика) — «эстафетное» затухание следа
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
  if (n <= 2 && headHist[0].t < tCut && state !== ST.TRAVEL && state !== ST.FADE_IN) trailHasGone = true;
}

function render() {
  // блик появляется всегда в финальной точке (маршрут убран)
  const x = TARGET.x, y = TARGET.y;

  tangentAt = tangentEnd;
  glintHead.x = x; glintHead.y = y;

  glint.style.opacity = glintAlpha;
  glint.style.transform = `translate(${x}px, ${y}px)`;

  // сдвиг группы логотипа (подъём наверх + лёгкий рост масштаба)
  logoGroup.style.transform = `translate(0px, ${groupY.toFixed(2)}px) scale(${groupScale.toFixed(4)})`;

  // след тает вместе с бликом
  if (glintAlpha <= 0) trail.style.opacity = 0;

}

/* параметры нужны только для отладки: ?t=SECONDS — прыжок по таймлайну */
const params = new URLSearchParams(location.search);

/* масштабирование сцены под окно */
function fit() {
  const k = Math.min(innerWidth / IMG, innerHeight / IMG);
  stage.style.transform = `scale(${k})`;
}
addEventListener('resize', fit);
fit();

// рестарт по касанию выключен: в Mini App случайный тап не должен сбрасывать заставку.// addEventListener('pointerdown', ...итоговый перезапуск отключён...);


/* старт; ?t=SECONDS — прыжок по таймлайну для отладки */
let lastNow = performance.now();
function loop(now) {
  const dt = Math.min((now - lastNow) / 1000, 0.05);
  lastNow = now;
  // ждём очищенный логотип, чтобы анимация не началась по пустому canvas
  if (!assetsReady) {
    requestAnimationFrame(loop);
    return;
  }
  tAbs += dt;
  tState += dt;
  step(dt);
  render();
  requestAnimationFrame(loop);
}

requestAnimationFrame(now => {
  requestAnimationFrame(() => {
    const seek = parseFloat(params.get('t'));
    if (!isNaN(seek) && assetsReady) {
      const steps = Math.round(seek / 0.016);
      for (let i = 0; i < steps; i++) {
        if (state === ST.END) break;
        tAbs += 0.016;
        tState += 0.016;
        step(0.016);
        render(); // обновляем голову следа и слои, чтобы история не звучала телепортом
      }
    }
    requestAnimationFrame(loop);
  });
});

/* =========================================================
   Жизненный цикл заставки.
   Анимация проигрывается ЦЕЛИКОМ: блик → проявление логотипа →
   подъём → надпись DARKSIDE. Flutter сообщает о первом кадре через
   window.finalsSplash.finish(), но уходим мы только когда отыграл
   финал и приложение уже отрисовано: что наступит позже — того и ждём.
   ========================================================= */
const splashEl = document.getElementById('splash');
const SHOW_AFTER_MS = 280;    // раньше не показываем: быстрый старт — без мигания
const HOLD_FINAL_MS = 450;    // пауза на финальном кадре, чтобы надпись прочиталась
const WATCHDOG_MS = 15000;    // страховка: картинка не пришла — не держим вечно
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

// Страховка: если анимация почему-то не доехала до финала (например,
// не загрузилась картинка), приложение всё равно должно открыться.
setTimeout(function () {
  if (firstFrameAt) closeSplash();
}, WATCHDOG_MS);
