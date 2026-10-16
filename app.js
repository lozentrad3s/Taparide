document.addEventListener('DOMContentLoaded', () => {
  const buttons = document.querySelectorAll('.primary-btn, .secondary-btn, .ghost-btn, .tiny-btn');

  buttons.forEach((button) => {
    button.addEventListener('mouseenter', () => {
      button.style.transform = 'translateY(-2px)';
    });

    button.addEventListener('mouseleave', () => {
      button.style.transform = 'translateY(0)';
    });
  });

  const routeTimes = document.querySelectorAll('.route-time');
  const cycle = ['4 min away', '6 min away', '8 min away', '10 min away', '12 min away'];

  let index = 0;
  setInterval(() => {
    routeTimes.forEach((element) => {
      index = (index + 1) % cycle.length;
      element.textContent = cycle[index];
    });
  }, 2600);

  const tabButtons = document.querySelectorAll('.tab-btn');
  const tabPanels = document.querySelectorAll('.tab-panel');

  tabButtons.forEach((button) => {
    button.addEventListener('click', () => {
      const selected = button.dataset.view;

      tabButtons.forEach((tab) => tab.classList.toggle('active', tab === button));
      tabPanels.forEach((panel) => {
        panel.classList.toggle('active', panel.dataset.panel === selected);
      });
    });
  });
});
