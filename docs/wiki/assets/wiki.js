// WarpFactor вики: поиск по заранее собранному индексу и подсветка связей в дереве.
// Файл генерируется make_wiki.py. Индекс — window.WIKI_INDEX из search-index.js (fetch на file:// не работает).
(function () {
  "use strict";
  var root = document.body.getAttribute("data-root") || "";
  var index = (window.WIKI_INDEX || []).map(function (e) {
    return {t: e[0], u: e[1], k: e[2], n: norm(e[0]), x: norm(e[0] + " " + (e[3] || ""))};
  });

  function norm(s) { return String(s).toLowerCase().replace(/ё/g, "е"); }

  function find(q) {
    q = norm(q).trim();
    if (!q) return [];
    var words = q.split(/\s+/), out = [];
    index.forEach(function (e, i) {
      for (var w = 0; w < words.length; w++) if (e.x.indexOf(words[w]) < 0) return;
      var score = e.n === q ? 0 : e.n.indexOf(q) === 0 ? 1 : e.n.indexOf(q) >= 0 ? 2 : 3;
      if (e.k === "Раздел") score -= 0.5;
      out.push([score, i, e]);
    });
    out.sort(function (a, b) { return a[0] - b[0] || a[1] - b[1]; });
    return out.slice(0, 40).map(function (x) { return x[2]; });
  }

  function esc(s) {
    return String(s).replace(/[&<>"]/g, function (c) { return {"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;"}[c]; });
  }

  Array.prototype.forEach.call(document.querySelectorAll("[data-search]"), function (input) {
    var list = input.parentNode.querySelector(".results"), active = -1, found = [];
    function render() {
      found = find(input.value);
      active = found.length ? 0 : -1;
      if (!input.value.trim()) { list.hidden = true; return; }
      list.innerHTML = found.length ? found.map(function (e, i) {
        return '<li><a href="' + esc(root + e.u) + '"' + (i === active ? ' class="on"' : "") + ">" + esc(e.t) +
          '<span class="k">' + esc(e.k) + "</span></a></li>";
      }).join("") : '<li class="none">Ничего не нашлось</li>';
      list.hidden = false;
    }
    function mark() {
      Array.prototype.forEach.call(list.querySelectorAll("a"), function (a, i) {
        a.className = i === active ? "on" : "";
        if (i === active) a.scrollIntoView({block: "nearest"});
      });
    }
    input.addEventListener("input", render);
    input.addEventListener("focus", function () { if (input.value.trim()) render(); });
    input.addEventListener("keydown", function (ev) {
      if (ev.key === "ArrowDown" && found.length) { active = (active + 1) % found.length; mark(); ev.preventDefault(); }
      else if (ev.key === "ArrowUp" && found.length) { active = (active - 1 + found.length) % found.length; mark(); ev.preventDefault(); }
      else if (ev.key === "Enter" && active >= 0) { location.href = root + found[active].u; ev.preventDefault(); }
      else if (ev.key === "Escape") { list.hidden = true; input.blur(); }
    });
    document.addEventListener("click", function (ev) { if (!input.parentNode.contains(ev.target)) list.hidden = true; });
  });

  // Горячая клавиша: «/» — в поиск.
  document.addEventListener("keydown", function (ev) {
    var t = ev.target.tagName;
    if (ev.key === "/" && t !== "INPUT" && t !== "TEXTAREA") {
      var input = document.querySelector("[data-search]");
      if (input) { input.focus(); ev.preventDefault(); }
    }
  });

  // Дерево исследований: наведение на узел подсвечивает его связи и соседей.
  var tree = document.querySelector("svg.tree");
  if (tree) {
    var edges = tree.querySelectorAll(".edge");
    function light(id, on) {
      Array.prototype.forEach.call(edges, function (e) {
        var a = e.getAttribute("data-a"), b = e.getAttribute("data-b");
        if (a === id || b === id) {
          e.classList.toggle("hl", on);
          var other = tree.querySelector('[data-id="' + (a === id ? b : a) + '"]');
          if (other) other.classList.toggle("hl", on);
        }
      });
    }
    Array.prototype.forEach.call(tree.querySelectorAll(".tn"), function (n) {
      var id = n.getAttribute("data-id");
      n.addEventListener("mouseenter", function () { light(id, true); });
      n.addEventListener("mouseleave", function () { light(id, false); });
    });
    var focus = location.hash && document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (focus && tree.contains(focus)) {
      focus.classList.add("focus");
      light(focus.getAttribute("data-id"), true);
      var wrap = tree.parentNode, box = focus.getBBox();
      wrap.scrollLeft = Math.max(0, box.x - wrap.clientWidth / 2 + box.width / 2);
      wrap.scrollTop = Math.max(0, box.y - wrap.clientHeight / 2 + box.height / 2);
      wrap.scrollIntoView({block: "start"});
    }
  }
})();
