/* Theme toggle and narrow-screen menu. The pages work without this file. */
(function () {
  var KEY = "ra-tfm-learning-theme";
  var root = document.documentElement;

  function stored() {
    try { return window.localStorage.getItem(KEY); } catch (e) { return null; }
  }
  function store(v) {
    try { window.localStorage.setItem(KEY, v); } catch (e) { /* private window etc. */ }
  }
  function current() {
    var t = root.getAttribute("data-theme");
    if (t) return t;
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
  }

  var saved = stored();
  if (saved === "light" || saved === "dark") root.setAttribute("data-theme", saved);

  document.addEventListener("DOMContentLoaded", function () {
    var btn = document.querySelector(".theme-toggle");
    if (btn) {
      var label = function () { btn.textContent = current() === "dark" ? "Light theme" : "Dark theme"; };
      label();
      btn.addEventListener("click", function () {
        var next = current() === "dark" ? "light" : "dark";
        root.setAttribute("data-theme", next);
        store(next);
        label();
      });
    }
    var menu = document.querySelector(".menu-toggle");
    var side = document.querySelector(".sidebar");
    if (menu && side) {
      menu.addEventListener("click", function () {
        var open = side.classList.toggle("open");
        menu.setAttribute("aria-expanded", open ? "true" : "false");
      });
    }
  });
})();
