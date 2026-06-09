(function () {
  const activeClasses = ['bg-slate-900', 'text-white', 'dark:bg-white', 'dark:text-slate-900'];
  const inactiveClasses = ['text-slate-600', 'hover:bg-slate-100', 'dark:text-slate-400', 'dark:hover:bg-slate-800'];

  function updateThemeUI(mode) {
    document.querySelectorAll('.theme-btn').forEach((button) => {
      button.classList.remove(...activeClasses, ...inactiveClasses);
      button.classList.add(...inactiveClasses);

      if (button.dataset.theme === mode) {
        button.classList.remove(...inactiveClasses);
        button.classList.add(...activeClasses);
      }
    });
  }

  function applyTheme(mode, persist) {
    const root = document.documentElement;
    root.classList.toggle('dark', mode === 'dark');

    if (persist) {
      localStorage.setItem('theme', mode);
    }

    updateThemeUI(mode);
  }

  window.setTheme = function setTheme(mode) {
    applyTheme(mode, true);
  };

  document.addEventListener('DOMContentLoaded', () => {
    const savedTheme = localStorage.getItem('theme');
    const prefersDark = window.matchMedia('(prefers-color-scheme: dark)').matches;
    const mode = savedTheme || (prefersDark ? 'dark' : 'light');
    applyTheme(mode, false);
  });
})();
