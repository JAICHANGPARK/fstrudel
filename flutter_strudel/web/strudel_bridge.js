const state = {
  initPromise: null,
  ctx: null,
  evaluate: null,
  stop: null,
};

async function loadModules() {
  const [core, mini, webaudio, tonal, transpiler, superdough, draw] = await Promise.all([
    import('@strudel/core'),
    import('@strudel/mini'),
    import('@strudel/webaudio'),
    import('@strudel/tonal'),
    import('@strudel/transpiler'),
    import('superdough'),
    import('@strudel/draw'),
  ]);
  return { core, mini, webaudio, tonal, transpiler, superdough, draw };
}

async function init() {
  if (state.initPromise) return state.initPromise;
  state.initPromise = (async () => {
    const { core, mini, webaudio, tonal, transpiler, superdough, draw } = await loadModules();
    state.ctx = webaudio.getAudioContext();
    webaudio.initAudioOnFirstClick();
    const ds = 'https://raw.githubusercontent.com/felixroos/dough-samples/main';
    const ts = 'https://raw.githubusercontent.com/todepond/samples/main';
    const tc = 'https://raw.githubusercontent.com/tidalcycles/uzu-drumkit/main';

    core.evalScope(
      Promise.resolve(core),
      Promise.resolve(mini),
      Promise.resolve(webaudio),
      Promise.resolve(tonal),
      Promise.resolve(draw)
    );

    const scopeFn = core.Pattern?.prototype?.scope;
    if (scopeFn) {
      if (!core.Pattern.prototype._scope) {
        core.Pattern.prototype._scope = scopeFn;
      }
      if (!core.Pattern.prototype.tscope) {
        core.Pattern.prototype.tscope = scopeFn;
      }
    } else if (core.Pattern?.prototype) {
      const noop = function () {
        return this;
      };
      core.Pattern.prototype._scope ??= noop;
      core.Pattern.prototype.tscope ??= noop;
      core.Pattern.prototype.scope ??= noop;
    }

    const soundfontTask = import('@strudel/soundfonts')
      .then((module) => module.registerSoundfonts?.())
      .catch((err) => {
        console.warn('[soundfonts] init failed:', err);
      });

    await Promise.all([
      webaudio.registerSynthSounds(),
      webaudio.registerZZFXSounds(),
      soundfontTask,
      webaudio.samples(`${ds}/tidal-drum-machines.json`),
      webaudio.samples(`${ds}/piano.json`),
      webaudio.samples(`${ds}/Dirt-Samples.json`),
      webaudio.samples(`${ds}/vcsl.json`),
      webaudio.samples(`${ds}/mridangam.json`),
      webaudio.samples(`${tc}/strudel.json`),
    ]);

    const aliasBank = webaudio.aliasBank || superdough.aliasBank;
    if (aliasBank) {
      await aliasBank(`${ts}/tidal-drum-machines-alias.json`);
    }

    const repl = core.repl({
      defaultOutput: webaudio.webaudioOutput,
      getTime: () => state.ctx.currentTime,
      transpiler: transpiler.transpiler,
    });
    state.evaluate = repl.evaluate;
    state.stop = repl.stop;
  })();
  return state.initPromise;
}

async function evalCode(code) {
  await init();
  if (state.ctx) {
    await state.ctx.resume();
    if (state.ctx.state !== 'running') {
      console.warn('[audio] context state:', state.ctx.state);
    }
  }
  if (!state.evaluate) {
    throw new Error('Strudel REPL is not initialized.');
  }
  try {
    await state.evaluate(code);
  } catch (err) {
    console.error('[strudel] eval error:', err);
    throw err;
  }
}

async function hush() {
  await init();
  if (state.evaluate) {
    await state.evaluate('hush()');
  }
  if (state.stop) {
    state.stop();
  }
}

window.strudelBridge = {
  init,
  eval: evalCode,
  hush,
};
