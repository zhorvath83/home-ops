// Vendored from kelchm/home-lab (MIT), kubernetes/apps/identity/kanidm/app/theme/style.js
// Mirror of kanidm's pkg/style.js (sets data-bs-theme from the OS colour scheme,
// live on change and after htmx swaps) with ONE addition: keep the
// <meta name="theme-color"> in sync with the mode, so the mobile browser chrome
// — the Safari bars and the notch / home-indicator insets — matches the theme
// instead of kanidm's hardcoded white. A meta tag can't be changed from CSS, so
// this small JS override is the only lever.
//
// This REPLACES kanidm's own style.js (mounted at /hpkg/style.js). Keep the
// data-bs-theme logic identical to upstream and re-check on kanidm upgrades — if
// upstream changes its theming JS, re-sync this file or the light/dark toggle
// breaks. Verified against kanidm v1.10.3.
function getPreferredTheme() {
  return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
}
function updateColourScheme() {
  const theme = getPreferredTheme();
  document.documentElement.setAttribute("data-bs-theme", theme);
  const meta = document.querySelector('meta[name="theme-color"]');
  if (meta) meta.setAttribute("content", theme === "dark" ? "#13172a" : "#f7f8fc");
}
updateColourScheme();
window.matchMedia("(prefers-color-scheme: light)").addEventListener("change", updateColourScheme);
window.matchMedia("(prefers-color-scheme: dark)").addEventListener("change", updateColourScheme);
document.body.addEventListener("htmx:afterOnLoad", updateColourScheme);
