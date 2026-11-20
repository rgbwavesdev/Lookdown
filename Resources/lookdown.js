/*
 * Lookdown renderer. Runs inside JavaScriptCore (no DOM), after markdown-it, its footnote and mark
 * plugins, highlight.js and KaTeX have been loaded.
 *
 *   Lookdown.render(markdown, optionsJSON) -> { html, math }
 *
 * html is the article body; math says whether KaTeX output is present (the host then adds KaTeX's
 * stylesheet and fonts). Images go through the host's __lookdownResolve(src, isWikiEmbed), which
 * returns a data: URI, or "" when the file can't be found.
 */
(function (global) {
  'use strict';

  var hljs = global.hljs;
  var katex = global.katex;

  // ---------------------------------------------------------------- helpers

  function esc(s) {
    return String(s)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function isSpace(code) {
    return code === 0x20 || code === 0x09 || code === 0x0a || code === 0x0d;
  }

  function svg(paths) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + paths + '</svg>';
  }

  // Icon paths in the style of Lucide (ISC license).
  var ICON = {
    pencil: svg('<path d="M21.17 6.81a1 1 0 0 0-3.98-3.98L3.84 16.17a2 2 0 0 0-.5.83l-1.32 4.35a.5.5 0 0 0 .62.62l4.35-1.32a2 2 0 0 0 .83-.5z"/><path d="m15 5 4 4"/>'),
    clipboard: svg('<rect width="8" height="4" x="8" y="2" rx="1"/><path d="M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2"/><path d="M12 11h4"/><path d="M12 16h4"/><path d="M8 11h.01"/><path d="M8 16h.01"/>'),
    info: svg('<circle cx="12" cy="12" r="10"/><path d="M12 16v-4"/><path d="M12 8h.01"/>'),
    circleCheck: svg('<circle cx="12" cy="12" r="10"/><path d="m9 12 2 2 4-4"/>'),
    bulb: svg('<path d="M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5"/><path d="M9 18h6"/><path d="M10 22h4"/>'),
    flame: svg('<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.07-2.14-.22-4.05 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.15.43-2.29 1-3a2.5 2.5 0 0 0 2.5 2.5z"/>'),
    report: svg('<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/><path d="M12 7v3"/><path d="M12 13.5h.01"/>'),
    check: svg('<path d="M20 6 9 17l-5-5"/>'),
    help: svg('<circle cx="12" cy="12" r="10"/><path d="M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3"/><path d="M12 17h.01"/>'),
    triangle: svg('<path d="m21.73 18-8-14a2 2 0 0 0-3.48 0l-8 14A2 2 0 0 0 4 21h16a2 2 0 0 0 1.73-3"/><path d="M12 9v4"/><path d="M12 17h.01"/>'),
    octagon: svg('<path d="M12 16h.01"/><path d="M12 8v4"/><path d="M15.31 2a2 2 0 0 1 1.42.59l4.68 4.68A2 2 0 0 1 22 8.69v6.62a2 2 0 0 1-.59 1.42l-4.68 4.68a2 2 0 0 1-1.42.59H8.69a2 2 0 0 1-1.42-.59l-4.68-4.68A2 2 0 0 1 2 15.31V8.69a2 2 0 0 1 .59-1.42l4.68-4.68A2 2 0 0 1 8.69 2z"/>'),
    x: svg('<path d="M18 6 6 18"/><path d="m6 6 12 12"/>'),
    zap: svg('<path d="M4 14a1 1 0 0 1-.78-1.63l9.9-10.2a.5.5 0 0 1 .86.46l-1.92 6.02A1 1 0 0 0 13 10h7a1 1 0 0 1 .78 1.63l-9.9 10.2a.5.5 0 0 1-.86-.46l1.92-6.02A1 1 0 0 0 11 14z"/>'),
    bug: svg('<path d="m8 2 1.88 1.88"/><path d="M14.12 3.88 16 2"/><path d="M9 7.13v-1a3 3 0 1 1 6 0v1"/><path d="M12 20c-3.3 0-6-2.7-6-6v-3a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v3c0 3.3-2.7 6-6 6"/><path d="M12 20v-9"/><path d="M6.53 9C4.6 8.8 3 7.1 3 5"/><path d="M6 13H2"/><path d="M3 21c0-2.1 1.7-3.9 3.8-4"/><path d="M20.97 5c0 2.1-1.6 3.8-3.5 4"/><path d="M22 13h-4"/><path d="M17.2 17c2.1.1 3.8 1.9 3.8 4"/>'),
    list: svg('<path d="M3 12h.01"/><path d="M3 18h.01"/><path d="M3 6h.01"/><path d="M8 12h13"/><path d="M8 18h13"/><path d="M8 6h13"/>'),
    quote: svg('<path d="M16 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z"/><path d="M5 3a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2 1 1 0 0 1 1 1v1a2 2 0 0 1-2 2 1 1 0 0 0-1 1v2a1 1 0 0 0 1 1 6 6 0 0 0 6-6V5a2 2 0 0 0-2-2z"/>'),
    chevron: svg('<path d="m9 18 6-6-6-6"/>'),
    image: svg('<rect width="18" height="18" x="3" y="3" rx="2"/><circle cx="9" cy="9" r="2"/><path d="m21 15-3.09-3.09a2 2 0 0 0-2.82 0L6 21"/>'),
    file: svg('<path d="M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z"/><path d="M14 2v4a2 2 0 0 0 2 2h4"/>'),
    minus: svg('<path d="M6 12h12"/>')
  };

  // ---------------------------------------------------------------- front matter

  var FRONT_MATTER = /^---[ \t]*\r?\n(?:([\s\S]*?)\r?\n)?(?:---|\.\.\.)[ \t]*(?:\r?\n|$)/;

  function splitFrontMatter(src) {
    var m = FRONT_MATTER.exec(src);
    if (!m) return { yaml: null, body: src };
    return { yaml: m[1] || '', body: src.slice(m[0].length) };
  }

  function indentOf(line) {
    return line.match(/^ */)[0].length;
  }

  function stripComment(s) {
    var c = s.search(/\s#/);
    return c >= 0 ? s.slice(0, c) : s;
  }

  function unquote(s) {
    s = s.trim();
    var q = s.charAt(0);
    if (s.length >= 2 && (q === '"' || q === "'") && s.charAt(s.length - 1) === q) {
      var inner = s.slice(1, -1);
      return q === '"'
        ? inner.replace(/\\n/g, '\n').replace(/\\t/g, '\t').replace(/\\(["\\])/g, '$1')
        : inner.replace(/''/g, "'");
    }
    return stripComment(s).trim();
  }

  function splitFlowList(s) {
    var inner = s.trim().replace(/^\[/, '').replace(/\]$/, '');
    var out = [], cur = '', quote = null;
    for (var i = 0; i < inner.length; i++) {
      var ch = inner.charAt(i);
      if (quote) {
        cur += ch;
        if (ch === quote) quote = null;
      } else if (ch === '"' || ch === "'") {
        quote = ch;
        cur += ch;
      } else if (ch === ',') {
        out.push(unquote(cur));
        cur = '';
      } else {
        cur += ch;
      }
    }
    if (cur.trim()) out.push(unquote(cur));
    return out.filter(function (x) { return x !== ''; });
  }

  function dedent(lines) {
    var used = lines.filter(function (l) { return l.trim(); });
    var min = used.length ? Math.min.apply(null, used.map(indentOf)) : 0;
    return lines.map(function (l) { return l.slice(min); }).join('\n').replace(/\s+$/, '');
  }

  var KEY_LINE = /^\s*([^\s#:'"-][^:]*?|"[^"]*"|'[^']*')\s*:(?:[ \t]+(.*?))?\s*$/;

  // A small, display-oriented YAML reader: scalars, flow and block lists, block scalars and nested
  // maps. Anything it doesn't understand is shown as raw text rather than guessed at.
  function parseValue(rest, block) {
    rest = rest || '';
    if (/^[|>][+-]?\d*$/.test(rest)) {
      var body = dedent(block).split('\n');
      return rest.charAt(0) === '|' ? body.join('\n') : body.join(' ').replace(/[ \t]+/g, ' ').trim();
    }
    if (rest) {
      var more = block.map(function (l) { return l.trim(); }).filter(Boolean).join(' ');
      if (rest.charAt(0) === '[') return splitFlowList(rest + (more ? ' ' + more : ''));
      if (rest.charAt(0) === '{') return { raw: rest + (more ? ' ' + more : '') };
      return unquote(more ? rest + ' ' + more : rest);
    }
    var used = block.filter(function (l) { return l.trim(); });
    if (!used.length) return '';
    if (used.every(function (l) { return /^\s*-(\s|$)/.test(l); })) {
      var items = used.map(function (l) { return l.replace(/^\s*-\s?/, ''); });
      if (items.every(function (x) { return !KEY_LINE.test(x); })) return items.map(unquote);
      return { raw: dedent(block) };
    }
    var base = indentOf(used[0]);
    var pairs = [];
    for (var j = 0; j < block.length; j++) {
      var line = block[j];
      if (!line.trim()) continue;
      var m = indentOf(line) === base ? KEY_LINE.exec(line) : null;
      if (!m) return { raw: dedent(block) };
      var sub = [];
      while (j + 1 < block.length && (!block[j + 1].trim() || indentOf(block[j + 1]) > base ||
          (/^\s*-(\s|$)/.test(block[j + 1]) && indentOf(block[j + 1]) === base && !m[2]))) {
        sub.push(block[++j]);
      }
      pairs.push([unquote(m[1]), parseValue(m[2], sub)]);
    }
    return { map: pairs };
  }

  function parseYaml(text) {
    var lines = text.replace(/\t/g, '  ').split(/\r?\n/);
    var out = [];
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      if (!line.trim() || /^\s*#/.test(line)) continue;
      var m = indentOf(line) === 0 ? KEY_LINE.exec(line) : null;
      if (!m) {
        out.push({ key: '', value: { raw: line.trim() } });
        continue;
      }
      var block = [];
      while (i + 1 < lines.length && (!lines[i + 1].trim() || indentOf(lines[i + 1]) > 0 ||
          /^-(\s|$)/.test(lines[i + 1]))) {
        block.push(lines[++i]);
      }
      while (block.length && !block[block.length - 1].trim()) block.pop();
      out.push({ key: unquote(m[1]), value: parseValue(m[2], block) });
    }
    return out;
  }

  var LIST_PILL_KEYS = /^(tags?|aliases|keywords|categories|cssclass(es)?|authors?)$/i;

  function renderPropValue(key, value, md, env) {
    if (Array.isArray(value)) {
      if (!value.length) return '<span class="prop-empty">empty</span>';
      var isTag = /^tags?$/i.test(key);
      return value.map(function (item) {
        var text = String(item);
        if (/^\[\[.*\]\]$/.test(text)) return md.renderInline(text, env);
        if (/^https?:\/\/\S+$/i.test(text)) return '<a href="' + esc(text) + '">' + esc(text) + '</a>';
        return '<span class="pill' + (isTag ? ' tag' : '') + '">' +
          esc(isTag ? '#' + text.replace(/^#/, '') : text) + '</span>';
      }).join(' ');
    }
    if (value && typeof value === 'object' && value.map) {
      return '<div class="prop-sub">' + value.map.map(function (pair) {
        return '<div class="prop-sub-row"><span class="prop-sub-key">' + esc(pair[0]) + '</span>' +
          '<span class="prop-sub-val">' + renderPropValue(pair[0], pair[1], md, env) + '</span></div>';
      }).join('') + '</div>';
    }
    if (value && typeof value === 'object' && 'raw' in value) {
      return '<pre class="prop-raw">' + esc(value.raw) + '</pre>';
    }
    var s = String(value);
    if (s === '' || s === '~' || s === 'null') return '<span class="prop-empty">empty</span>';
    if (s === 'true' || s === 'false') {
      return '<span class="prop-bool ' + s + '">' + (s === 'true' ? ICON.check : ICON.minus) + s + '</span>';
    }
    if (LIST_PILL_KEYS.test(key) && /^tags?$/i.test(key)) {
      return s.split(/[\s,]+/).filter(Boolean).map(function (t) {
        return '<span class="pill tag">#' + esc(t.replace(/^#/, '')) + '</span>';
      }).join(' ');
    }
    if (s.indexOf('\n') >= 0) return '<span class="prop-multiline">' + esc(s) + '</span>';
    return md.renderInline(s, env);
  }

  function renderProperties(yaml, md, env, collapsed) {
    var props = parseYaml(yaml);
    if (!props.length) return '';
    var cells = props.map(function (p) {
      return '<div class="prop-key">' + esc(p.key) + '</div>' +
        '<div class="prop-val">' + renderPropValue(p.key, p.value, md, env) + '</div>';
    }).join('');
    return '<details class="properties"' + (collapsed ? '' : ' open') + '>' +
      '<summary><span class="prop-chevron">' + ICON.chevron + '</span>Properties</summary>' +
      '<div class="prop-grid">' + cells + '</div></details>\n';
  }

  // ---------------------------------------------------------------- images

  var IMAGE_EXT = /\.(png|jpe?g|gif|webp|svg|bmp|avif|heic|heif|tiff?|ico)$/i;

  // Returns a usable src, or null when the image can't be shown.
  function resolveSrc(src, env, wiki) {
    src = String(src || '').trim();
    if (!src) return null;
    if (/^data:image\//i.test(src)) return src;
    if (/^(https?:)?\/\//i.test(src)) {
      if (!env.opts.remoteImages) return null;
      return src.indexOf('//') === 0 ? 'https:' + src : src;
    }
    if (typeof global.__lookdownResolve === 'function') {
      var out = global.__lookdownResolve(src, !!wiki);
      return out ? String(out) : null;
    }
    return src;
  }

  function imageTag(src, alt, title, size, env, wiki) {
    var resolved = resolveSrc(src, env, wiki);
    if (resolved === null) {
      var remote = /^(https?:)?\/\//i.test(String(src));
      return '<span class="missing-image" title="' + esc(src) + '">' + ICON.image +
        '<span>' + esc(alt || String(src).split('/').pop() || 'image') +
        (remote ? ' <em>(web image)</em>' : '') + '</span></span>';
    }
    var attrs = ' src="' + esc(resolved) + '" alt="' + esc(alt || '') + '"';
    if (title) attrs += ' title="' + esc(title) + '"';
    if (size && size.w) attrs += ' width="' + esc(size.w) + '"';
    if (size && size.h) attrs += ' height="' + esc(size.h) + '"';
    return '<img' + attrs + '>';
  }

  // Obsidian puts a size after a pipe: ![caption|300](a.png), ![[a.png|300x200]].
  function splitSize(text) {
    var m = /^(.*?)\|\s*(\d+)(?:\s*x\s*(\d+))?\s*$/.exec(text || '');
    if (!m) return { text: text, size: null };
    return { text: m[1], size: { w: m[2], h: m[3] } };
  }

  // ---------------------------------------------------------------- raw HTML

  var DROP_TAGS = /<\/?(script|iframe|frame|frameset|object|embed|applet|meta|base|link|form)\b[^>]*>/gi;
  var SRC_ATTR = /(<(?:img|source|video|audio)\b[^>]*?\s(?:src|poster)\s*=\s*)(["'])([^"']*)\2/gi;

  function fixHtml(html, env) {
    return String(html)
      .replace(/<script\b[\s\S]*?<\/script\s*>/gi, '')
      .replace(DROP_TAGS, '')
      .replace(SRC_ATTR, function (all, before, q, url) {
        var resolved = resolveSrc(url, env, false);
        return before + q + esc(resolved === null ? url : resolved) + q;
      });
  }

  // ---------------------------------------------------------------- code

  var LANG_ALIASES = {
    shell: 'bash', terminal: 'bash', sh: 'bash', zsh: 'bash', fish: 'bash', command: 'bash',
    jsonc: 'json', json5: 'json', yml: 'yaml', env: 'bash', dotenv: 'bash', toml: 'ini',
    vue: 'xml', svelte: 'xml', html: 'xml', xhtml: 'xml', plist: 'xml', svg: 'xml',
    'objective-c': 'objectivec', 'c++': 'cpp', 'c#': 'csharp', py: 'python', rb: 'ruby',
    rs: 'rust', kt: 'kotlin', golang: 'go', ps1: 'powershell', docker: 'dockerfile',
    tex: 'latex', patch: 'diff', text: '', txt: '', plain: '', plaintext: ''
  };

  function highlight(code, lang) {
    var name = Object.prototype.hasOwnProperty.call(LANG_ALIASES, lang) ? LANG_ALIASES[lang] : lang;
    if (name && hljs && hljs.getLanguage(name) && code.length < 150000) {
      try {
        return hljs.highlight(code, { language: name, ignoreIllegals: true }).value;
      } catch (e) { /* fall through */ }
    }
    return esc(code);
  }

  function parseInfo(info) {
    info = String(info || '').trim();
    var title = null;
    var t = /\b(?:title|file(?:name)?)\s*=\s*"([^"]+)"/.exec(info) || /\b(?:title|file(?:name)?)\s*=\s*(\S+)/.exec(info);
    if (t) title = t[1];
    var first = info.split(/\s+/)[0] || '';
    first = first.replace(/^\{\.?/, '').replace(/\}$/, '');
    var colon = first.indexOf(':');
    if (colon > 0) {
      title = title || first.slice(colon + 1);
      first = first.slice(0, colon);
    }
    return { lang: first.toLowerCase(), label: first, title: title };
  }

  function codeBlock(code, info, env) {
    var p = parseInfo(info);
    if (p.lang === 'math' || p.lang === 'katex') {
      env.math = true;
      return '<div class="math-display">' + renderMath(code, true) + '</div>\n';
    }
    var label = p.title ? p.title : p.label;
    var cls = p.lang ? ' language-' + esc(p.lang.replace(/[^\w+#-]/g, '')) : '';
    var note = p.lang === 'mermaid'
      ? '<span class="code-note">diagram source</span>' : '';
    var head = label
      ? '<div class="code-head"><span class="code-lang">' + esc(label) + '</span>' + note + '</div>'
      : '';
    var body = highlight(code.replace(/\n$/, ''), p.lang);
    return '<div class="code-block' + (label ? ' has-head' : '') + '">' + head +
      '<pre><code class="hljs' + cls + '">' + body + '</code></pre></div>\n';
  }

  // ---------------------------------------------------------------- math

  function renderMath(tex, display) {
    if (!katex) return '<code class="math-source">' + esc(tex) + '</code>';
    try {
      return katex.renderToString(tex, {
        displayMode: display, throwOnError: false, output: 'html', strict: 'ignore', trust: false
      });
    } catch (e) {
      return '<code class="math-source">' + esc(tex) + '</code>';
    }
  }

  function mathInlineRule(state, silent) {
    var src = state.src, pos = state.pos, max = state.posMax;
    var ch = src.charCodeAt(pos);
    var token, content, end;

    if (ch === 0x5c /* \ */) {
      var next = src.charCodeAt(pos + 1);
      if (next !== 0x28 /* ( */) return false;
      end = src.indexOf('\\)', pos + 2);
      if (end < 0 || end + 2 > max) return false;
      content = src.slice(pos + 2, end);
      if (!content.trim()) return false;
      if (!silent) {
        token = state.push('math_inline', 'math', 0);
        token.content = content;
      }
      state.pos = end + 2;
      return true;
    }

    if (ch !== 0x24 /* $ */) return false;

    if (src.charCodeAt(pos + 1) === 0x24) {
      end = src.indexOf('$$', pos + 2);
      if (end < 0 || end + 2 > max) return false;
      content = src.slice(pos + 2, end);
      if (!content.trim()) return false;
      if (!silent) {
        token = state.push('math_inline', 'math', 0);
        token.content = content;
        token.meta = { display: true };
      }
      state.pos = end + 2;
      return true;
    }

    // Single $: the opener can't be followed by a space, the closer can't follow a space or be
    // followed by a digit. That keeps "$5 and $10" as text.
    var after = src.charCodeAt(pos + 1);
    if (pos + 1 >= max || isSpace(after)) return false;
    var search = pos + 1;
    while (true) {
      end = src.indexOf('$', search);
      if (end < 0 || end >= max) return false;
      var bs = 0;
      while (src.charCodeAt(end - 1 - bs) === 0x5c) bs++;
      if (bs % 2 === 0) break;
      search = end + 1;
    }
    if (end === pos + 1) return false;
    if (isSpace(src.charCodeAt(end - 1))) return false;
    var follow = src.charCodeAt(end + 1);
    if (follow >= 0x30 && follow <= 0x39) return false;
    if (!silent) {
      token = state.push('math_inline', 'math', 0);
      token.content = src.slice(pos + 1, end);
    }
    state.pos = end + 1;
    return true;
  }

  function mathBlockRule(state, startLine, endLine, silent) {
    var pos = state.bMarks[startLine] + state.tShift[startLine];
    var max = state.eMarks[startLine];
    if (state.sCount[startLine] - state.blkIndent >= 4) return false;
    var opener = state.src.slice(pos, pos + 2);
    var closer;
    if (opener === '$$') closer = '$$';
    else if (opener === '\\[') closer = '\\]';
    else return false;

    var firstLine = state.src.slice(pos + 2, max);
    var lastLine = '';
    var next = startLine;
    var found = false;
    var trimmed = firstLine.trim();
    if (trimmed.length >= 2 && trimmed.slice(-2) === closer) {
      firstLine = trimmed.slice(0, -2);
      found = true;
    } else if (trimmed && opener === '$$' && trimmed.indexOf('$$') >= 0) {
      return false; // "$$a$$ text" on one line is inline math
    }

    while (!found) {
      next++;
      if (next >= endLine) return false;
      pos = state.bMarks[next] + state.tShift[next];
      max = state.eMarks[next];
      if (pos < max && state.sCount[next] < state.blkIndent) return false;
      var line = state.src.slice(pos, max);
      if (line.trim().slice(-2) === closer) {
        var cut = state.src.slice(0, max).lastIndexOf(closer);
        lastLine = state.src.slice(pos, cut);
        found = true;
      }
    }
    if (silent) return true;

    state.line = next + 1;
    var token = state.push('math_block', 'math', 0);
    token.block = true;
    token.content = (firstLine.trim() ? firstLine + '\n' : '') +
      (next > startLine ? state.getLines(startLine + 1, next, state.sCount[startLine], true) : '') +
      (lastLine.trim() ? lastLine : '');
    token.map = [startLine, state.line];
    token.markup = opener;
    return true;
  }

  function mathPlugin(md) {
    md.inline.ruler.before('escape', 'math_inline', mathInlineRule);
    md.block.ruler.before('fence', 'math_block', mathBlockRule, {
      alt: ['paragraph', 'reference', 'blockquote', 'list']
    });
    md.renderer.rules.math_inline = function (tokens, idx, options, env) {
      env.math = true;
      var t = tokens[idx];
      return renderMath(t.content, !!(t.meta && t.meta.display));
    };
    md.renderer.rules.math_block = function (tokens, idx, options, env) {
      env.math = true;
      return '<div class="math-display">' + renderMath(tokens[idx].content, true) + '</div>\n';
    };
  }

  // ---------------------------------------------------------------- callouts

  // Obsidian callouts and GitHub alerts share the "> [!type] Title" syntax.
  var CALLOUT_TYPES = {
    note: 'note', abstract: 'abstract', summary: 'abstract', tldr: 'abstract', info: 'info',
    todo: 'todo', tip: 'tip', hint: 'tip', important: 'important', success: 'success',
    check: 'success', done: 'success', question: 'question', help: 'question', faq: 'question',
    warning: 'warning', attention: 'warning', caution: 'caution', failure: 'failure',
    fail: 'failure', missing: 'failure', danger: 'danger', error: 'danger', bug: 'bug',
    example: 'example', quote: 'quote', cite: 'quote'
  };
  var CALLOUT_ICONS = {
    note: ICON.pencil, abstract: ICON.clipboard, info: ICON.info, todo: ICON.circleCheck,
    tip: ICON.bulb, important: ICON.report, success: ICON.check, question: ICON.help,
    warning: ICON.triangle, caution: ICON.octagon, failure: ICON.x, danger: ICON.zap,
    bug: ICON.bug, example: ICON.list, quote: ICON.quote
  };
  var CALLOUT_HEAD = /^\[!([A-Za-z][\w-]*)\]([+-]?)[ \t]*(.*)$/;

  function calloutPlugin(md) {
    md.core.ruler.after('block', 'lookdown_callouts', function (state) {
      var tokens = state.tokens;
      for (var i = 0; i < tokens.length; i++) {
        if (tokens[i].type !== 'blockquote_open') continue;
        var para = tokens[i + 1], inline = tokens[i + 2];
        if (!para || para.type !== 'paragraph_open' || !inline || inline.type !== 'inline') continue;
        var nl = inline.content.indexOf('\n');
        var first = nl >= 0 ? inline.content.slice(0, nl) : inline.content;
        var m = CALLOUT_HEAD.exec(first);
        if (!m) continue;

        var name = m[1].toLowerCase();
        var kind = CALLOUT_TYPES[name] || 'note';
        var fold = m[2];
        var title = m[3].trim() || name.charAt(0).toUpperCase() + name.slice(1).replace(/[-_]/g, ' ');
        var rest = nl >= 0 ? inline.content.slice(nl + 1) : '';

        var depth = 0, close = -1;
        for (var j = i; j < tokens.length; j++) {
          if (tokens[j].type === 'blockquote_open') depth++;
          else if (tokens[j].type === 'blockquote_close' && --depth === 0) { close = j; break; }
        }
        if (close < 0) continue;

        var wrap = fold ? 'details' : 'div';
        var head = fold ? 'summary' : 'div';
        var open = new state.Token('html_block', '', 0);
        open.content = '<' + wrap + ' class="callout callout-' + kind + '" data-callout="' + esc(name) + '"' +
          (fold === '+' ? ' open' : '') + '><' + head + ' class="callout-title">' +
          '<span class="callout-icon">' + (CALLOUT_ICONS[kind] || ICON.pencil) + '</span>' +
          '<span class="callout-title-text">';
        var titleToken = new state.Token('inline', '', 0);
        titleToken.content = title;
        titleToken.children = [];
        titleToken.map = inline.map;
        var mid = new state.Token('html_block', '', 0);
        mid.content = '</span>' + (fold ? '<span class="callout-fold">' + ICON.chevron + '</span>' : '') +
          '</' + head + '><div class="callout-content">';
        var end = new state.Token('html_block', '', 0);
        end.content = '</div></' + wrap + '>\n';

        tokens[close] = end;
        if (rest.trim()) {
          inline.content = rest;
        } else {
          tokens.splice(i + 1, 3);
        }
        tokens.splice(i, 1, open, titleToken, mid);
        i += 2;
      }
    });
  }

  // ---------------------------------------------------------------- task lists

  var TASK_STATES = { ' ': 'todo', x: 'done', X: 'done', '-': 'cancelled', '/': 'partial' };

  function taskPlugin(md) {
    md.core.ruler.push('lookdown_tasks', function (state) {
      var tokens = state.tokens;
      for (var i = 2; i < tokens.length; i++) {
        var inline = tokens[i];
        if (inline.type !== 'inline' || tokens[i - 1].type !== 'paragraph_open' ||
            tokens[i - 2].type !== 'list_item_open') continue;
        var kids = inline.children;
        if (!kids || !kids.length || kids[0].type !== 'text') continue;
        var m = /^\[([^\]])\](?:[ \t]+|$)/.exec(kids[0].content);
        if (!m) continue;
        var status = TASK_STATES[m[1]] || 'done';
        kids[0].content = kids[0].content.slice(m[0].length);
        var box = new state.Token('html_inline', '', 0);
        var mark = status === 'done' ? ICON.check : status === 'cancelled' || status === 'partial' ? ICON.minus : '';
        box.content = '<span class="task-box" aria-hidden="true">' + mark + '</span><span class="task-text">';
        var after = new state.Token('html_inline', '', 0);
        after.content = '</span>';
        kids.unshift(box);
        kids.push(after);
        var item = tokens[i - 2];
        item.attrJoin('class', 'task-list-item task-' + status);
        for (var j = i - 3; j >= 0; j--) {
          var t = tokens[j];
          if ((t.type === 'bullet_list_open' || t.type === 'ordered_list_open') && t.level === item.level - 1) {
            if (!/contains-task-list/.test(t.attrGet('class') || '')) t.attrJoin('class', 'contains-task-list');
            break;
          }
        }
      }
    });
  }

  // ---------------------------------------------------------------- wikilinks, embeds, tags

  function wikiRule(state, silent) {
    var src = state.src, pos = state.pos, embed = false;
    if (src.charCodeAt(pos) === 0x21 /* ! */) {
      embed = true;
      pos++;
    }
    if (src.charCodeAt(pos) !== 0x5b || src.charCodeAt(pos + 1) !== 0x5b) return false;
    var end = src.indexOf(']]', pos + 2);
    if (end < 0 || end + 2 > state.posMax) return false;
    var inner = src.slice(pos + 2, end);
    if (!inner.trim() || /[\n\[\]]/.test(inner)) return false;
    if (!silent) {
      var bar = inner.indexOf('|');
      var token = state.push(embed ? 'wiki_embed' : 'wikilink', '', 0);
      token.meta = {
        target: (bar >= 0 ? inner.slice(0, bar) : inner).trim(),
        alias: bar >= 0 ? inner.slice(bar + 1).trim() : ''
      };
    }
    state.pos = end + 2;
    return true;
  }

  function wikiLabel(target) {
    var hash = target.indexOf('#');
    if (hash < 0) return target.replace(/\.md$/i, '');
    var page = target.slice(0, hash).replace(/\.md$/i, '');
    var sub = target.slice(hash + 1).replace(/^\^/, '');
    return page ? page + ' › ' + sub : sub;
  }

  function tagRule(state, silent) {
    var src = state.src, pos = state.pos;
    if (src.charCodeAt(pos) !== 0x23 /* # */) return false;
    if (pos > 0) {
      var prev = src.charCodeAt(pos - 1);
      if (!isSpace(prev) && prev !== 0x28 /* ( */) return false;
    }
    var m = /^#([\p{L}\p{N}_\/-]+)/u.exec(src.slice(pos, Math.min(state.posMax, pos + 160)));
    if (!m || !/[^\d_\/-]/.test(m[1])) return false;
    if (!silent) {
      var token = state.push('tag', '', 0);
      token.content = m[1];
    }
    state.pos += m[0].length;
    return true;
  }

  function obsidianPlugin(md) {
    md.inline.ruler.before('link', 'wikilink', wikiRule);
    md.inline.ruler.before('link', 'tag', tagRule);
    md.renderer.rules.wikilink = function (tokens, idx) {
      var meta = tokens[idx].meta;
      return '<span class="wikilink" title="' + esc(meta.target) + '">' +
        esc(meta.alias || wikiLabel(meta.target)) + '</span>';
    };
    md.renderer.rules.wiki_embed = function (tokens, idx, options, env) {
      var meta = tokens[idx].meta;
      var file = meta.target.split('#')[0];
      if (IMAGE_EXT.test(file)) {
        var size = /^(\d+)(?:\s*x\s*(\d+))?$/.exec(meta.alias);
        var alt = size || !meta.alias ? file.split('/').pop() : meta.alias;
        return imageTag(file, alt, null, size ? { w: size[1], h: size[2] } : null, env, true);
      }
      return '<span class="embed-note" title="' + esc(meta.target) + '">' + ICON.file +
        '<span>' + esc(meta.alias || wikiLabel(meta.target)) + '</span></span>';
    };
    md.renderer.rules.tag = function (tokens, idx) {
      return '<span class="tag">#' + esc(tokens[idx].content) + '</span>';
    };
  }

  // ---------------------------------------------------------------- headings, tables, images

  function slugify(text) {
    return text.trim().toLowerCase()
      .replace(/[^\p{L}\p{N}\s_-]/gu, '')
      .replace(/\s/g, '-');
  }

  function structurePlugin(md) {
    md.core.ruler.push('lookdown_heading_ids', function (state) {
      var seen = {};
      var tokens = state.tokens;
      for (var i = 0; i < tokens.length - 1; i++) {
        if (tokens[i].type !== 'heading_open' || tokens[i + 1].type !== 'inline') continue;
        var text = (tokens[i + 1].children || []).map(function (t) {
          return t.type === 'text' || t.type === 'code_inline' ? t.content : '';
        }).join('');
        var slug = slugify(text) || 'section';
        var unique = slug, n = 1;
        while (seen[unique]) unique = slug + '-' + n++;
        seen[unique] = true;
        tokens[i].attrSet('id', unique);
      }
    });

    var rules = md.renderer.rules;
    rules.table_open = function () { return '<div class="table-wrap"><table>\n'; };
    rules.table_close = function () { return '</table></div>\n'; };

    rules.fence = function (tokens, idx, options, env) {
      var t = tokens[idx];
      return codeBlock(t.content, md.utils.unescapeAll(t.info || ''), env);
    };
    rules.code_block = function (tokens, idx, options, env) {
      return codeBlock(tokens[idx].content, '', env);
    };

    rules.image = function (tokens, idx, options, env, self) {
      var t = tokens[idx];
      var alt = splitSize(self.renderInlineAsText(t.children, options, env));
      return imageTag(t.attrGet('src'), alt.text, t.attrGet('title'), alt.size, env, false);
    };

    rules.html_block = function (tokens, idx, options, env) { return fixHtml(tokens[idx].content, env); };
    rules.html_inline = function (tokens, idx, options, env) { return fixHtml(tokens[idx].content, env); };

    // Footnote markers show as a bare number; the stylesheet adds the brackets.
    rules.footnote_caption = function (tokens, idx) {
      var meta = tokens[idx].meta;
      var n = String(Number(meta.id) + 1);
      return meta.subId > 0 ? n + ':' + meta.subId : n;
    };
  }

  // ---------------------------------------------------------------- setup

  var BAD_PROTOCOL = /^(javascript|vbscript):/i;
  var GOOD_DATA = /^data:image\/(gif|png|jpeg|webp|svg\+xml|avif|bmp)[;,]/i;

  var instances = {};

  function instance(opts) {
    var key = opts.softBreaks ? 'breaks' : 'standard';
    if (instances[key]) return instances[key];
    var md = global.markdownit({
      html: true,
      linkify: true,
      typographer: false,
      breaks: !!opts.softBreaks
    });
    md.validateLink = function (url) {
      var s = String(url).trim();
      if (BAD_PROTOCOL.test(s)) return false;
      if (/^data:/i.test(s)) return GOOD_DATA.test(s);
      return true;
    };
    md.linkify.set({ fuzzyEmail: false });
    if (global.markdownitFootnote) md.use(global.markdownitFootnote);
    if (global.markdownitMark) md.use(global.markdownitMark);
    md.use(mathPlugin);
    md.use(calloutPlugin);
    md.use(taskPlugin);
    md.use(obsidianPlugin);
    md.use(structurePlugin);
    instances[key] = md;
    return md;
  }

  function render(src, optionsJSON) {
    var opts = {};
    try { opts = JSON.parse(optionsJSON || '{}'); } catch (e) { opts = {}; }
    var env = { opts: opts, math: false };
    var md = instance(opts);
    var parts = splitFrontMatter(String(src).replace(/^\uFEFF/, ''));
    var props = '';
    if (parts.yaml !== null && opts.properties !== 'hidden') {
      props = renderProperties(parts.yaml, md, env, opts.properties === 'collapsed');
    }
    var html = props + md.render(parts.body, env);
    return { html: html, math: !!env.math };
  }

  global.Lookdown = { render: render, parseYaml: parseYaml };
})(this);
