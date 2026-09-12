(function () {
  var root = document.documentElement;
  var toggle = document.querySelector(".theme-toggle");

  if (!toggle) return;

  function updateToggle(theme) {
    var isDark = theme === "dark";
    toggle.setAttribute("aria-pressed", String(isDark));
    toggle.setAttribute("aria-label", isDark ? "Switch to light mode" : "Switch to dark mode");
  }

  updateToggle(root.getAttribute("data-theme") || "light");

  toggle.addEventListener("click", function () {
    var theme = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", theme);
    localStorage.setItem("theme", theme);
    updateToggle(theme);
  });
}());
