const state = {
  token: '',
};

const loginForm = document.querySelector('#loginForm');
const codeForm = document.querySelector('#codeForm');
const loginStatus = document.querySelector('#loginStatus');
const codeStatus = document.querySelector('#codeStatus');
const codes = document.querySelector('#codes');

function setStatus(element, text, type = '') {
  element.textContent = text;
  element.className = `status ${type}`.trim();
}

function randomCode() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  const part = () => Array.from({ length: 4 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join('');
  return `SECT-${part()}-${part()}`;
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(state.token ? { Authorization: `Bearer ${state.token}` } : {}),
      ...(options.headers ?? {}),
    },
  });
  if (!response.ok) throw new Error(await response.text());
  return response.json();
}

async function refreshCodes() {
  if (!state.token) {
    codes.innerHTML = '<p class="status">Connectez-vous pour voir les codes.</p>';
    return;
  }

  const data = await api('/api/driver-codes');
  if (data.length === 0) {
    codes.innerHTML = '<p class="status">Aucun code cree pour le moment.</p>';
    return;
  }

  codes.innerHTML = data.map((item) => `
    <article class="codeCard">
      <div>
        <strong>${item.label}</strong>
        <span>${item.sector_name} - ${item.driver_email}</span><br>
        <span>Mots-cles : ${(item.sector_keywords ?? []).join(', ') || 'toutes lignes'}</span><br>
        <span>Cree le ${new Date(item.created_at).toLocaleString('fr-FR')}</span>
      </div>
      <div class="pill">${item.active ? 'Actif' : 'Desactive'}</div>
    </article>
  `).join('');
}

loginForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  setStatus(loginStatus, 'Connexion en cours...');
  try {
    const data = await api('/api/auth/login', {
      method: 'POST',
      body: JSON.stringify({
        email: document.querySelector('#email').value,
        password: document.querySelector('#password').value,
      }),
    });
    state.token = data.token;
    setStatus(loginStatus, `Connecte : ${data.user.name}`, 'ok');
    await refreshCodes();
  } catch {
    setStatus(loginStatus, 'Connexion impossible.', 'error');
  }
});

document.querySelector('#generate').addEventListener('click', () => {
  document.querySelector('#code').value = randomCode();
});

document.querySelector('#refresh').addEventListener('click', refreshCodes);

codeForm.addEventListener('submit', async (event) => {
  event.preventDefault();
  if (!state.token) {
    setStatus(codeStatus, 'Connectez-vous avant de creer un code de secteur.', 'error');
    return;
  }

  setStatus(codeStatus, 'Creation du code...');
  try {
    const data = await api('/api/driver-codes', {
      method: 'POST',
      body: JSON.stringify({
        code: document.querySelector('#code').value.trim(),
        driverEmail: document.querySelector('#driverEmail').value.trim(),
        label: document.querySelector('#label').value.trim(),
        sectorName: document.querySelector('#sectorName').value.trim(),
        sectorKeywords: document.querySelector('#sectorKeywords').value.split(',').map((item) => item.trim()).filter(Boolean),
      }),
    });
    setStatus(codeStatus, `Code cree : ${data.code}`, 'ok');
    await refreshCodes();
  } catch {
    setStatus(codeStatus, 'Creation impossible. Verifiez le conducteur et la connexion.', 'error');
  }
});

refreshCodes();
