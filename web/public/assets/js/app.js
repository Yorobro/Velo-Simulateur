/* Vélo libre-service — comportements légers, sans dépendance. */
(() => {
  'use strict';

  // Confirmation avant les actions irréversibles : <form data-confirmer="Message">
  document.addEventListener('submit', (e) => {
    const message = e.target.dataset.confirmer;
    if (message && !window.confirm(message)) {
      e.preventDefault();
    }
  });

  // Listes qui soumettent leur formulaire dès le choix : <select data-auto>
  document.querySelectorAll('select[data-auto]').forEach((select) => {
    select.addEventListener('change', () => select.form.submit());
  });

  // Menu latéral sur petit écran
  const barre = document.getElementById('barre-laterale');
  document.querySelectorAll('[data-menu]').forEach((bouton) => {
    bouton.addEventListener('click', () => barre && barre.classList.toggle('ouverte'));
  });

  // Messages : fermeture manuelle et disparition automatique
  document.querySelectorAll('.flash').forEach((flash, i) => {
    const fermer = () => {
      flash.classList.add('sortie');
      setTimeout(() => flash.remove(), 300);
    };
    flash.querySelector('button')?.addEventListener('click', fermer);
    if (!flash.classList.contains('flash-erreur')) {
      setTimeout(fermer, 6000 + i * 500);
    }
  });

  // Durée écoulée depuis une date : <span data-depuis="2026-11-05T10:15:00">
  const chronos = document.querySelectorAll('[data-depuis]');
  const actualiser = () => chronos.forEach((el) => {
    const minutes = Math.max(0, Math.floor((Date.now() - new Date(el.dataset.depuis).getTime()) / 60000));
    const h = Math.floor(minutes / 60);
    el.textContent = h > 0 ? `${h} h ${String(minutes % 60).padStart(2, '0')}` : `${minutes} min`;
  });
  if (chronos.length) {
    actualiser();
    setInterval(actualiser, 20000);
  }

  // Comptes de démonstration (page de connexion)
  document.querySelectorAll('[data-compte]').forEach((bouton) => {
    bouton.addEventListener('click', () => {
      const form = bouton.closest('form') || document.querySelector('form');
      form.querySelector('[name=email]').value = bouton.dataset.compte;
      form.querySelector('[name=mot_de_passe]').value = bouton.dataset.motDePasse;
      form.querySelector('[name=mot_de_passe]').focus();
    });
  });

  // Graphiques Chart.js : <canvas data-graphique='{"type": …}'>
  const toiles = document.querySelectorAll('canvas[data-graphique]');
  if (toiles.length && window.Chart) {
    const style = getComputedStyle(document.documentElement);
    Chart.defaults.font.family = style.getPropertyValue('--font');
    Chart.defaults.font.size = 12;
    Chart.defaults.color = '#64748b';
    Chart.defaults.borderColor = '#e2e8f0';
    Chart.defaults.plugins.legend.labels.boxWidth = 12;
    Chart.defaults.plugins.legend.labels.boxHeight = 12;
    Chart.defaults.plugins.tooltip.backgroundColor = '#0f172a';
    Chart.defaults.plugins.tooltip.padding = 10;
    Chart.defaults.maintainAspectRatio = false;
    toiles.forEach((toile) => new Chart(toile, JSON.parse(toile.dataset.graphique)));
  }
})();
