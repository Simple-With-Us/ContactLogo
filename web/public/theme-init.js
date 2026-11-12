// Apply a saved choice before CSS and the first paint, under script-src self.
try {
  const theme = localStorage.getItem("contactlogo.theme");
  if (theme === "light" || theme === "dark") {
    document.documentElement.setAttribute("data-theme", theme);
  }
} catch {
  // Storage can be unavailable. The device theme remains the fallback.
}
